class WealthReaderItem < ApplicationRecord
  include Syncable, Provided, Unlinking, Encryptable

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  if encryption_ready?
    encrypts :api_key, deterministic: true
    encrypts :token, deterministic: true
    encrypts :pkce_code_verifier
    encrypts :raw_payload
  end

  validates :name, presence: true
  validates :api_key, presence: true, on: :create
  validates :country_code, presence: true

  belongs_to :family
  has_one_attached :logo, dependent: :purge_later
  has_many :wealth_reader_accounts, dependent: :destroy
  has_many :accounts, through: :wealth_reader_accounts

  scope :active, -> { where(scheduled_for_deletion: false) }
  scope :syncable, -> { active }
  scope :ordered, -> { order(created_at: :desc) }

  def destroy_later
    update!(scheduled_for_deletion: true)
    DestroyJob.perform_later(self)
  end

  def credentials_configured?
    api_key.present? && country_code.present?
  end

  def session_valid?
    token.present? && entity_code.present?
  end

  def session_expired?
    requires_update?
  end

  def needs_authorization?
    !session_valid?
  end

  def institution_display_name
    institution_name.presence || entity_code.presence || name
  end

  def linked_accounts_count
    wealth_reader_accounts.joins(:account_provider).count
  end

  def unlinked_accounts_count
    wealth_reader_accounts.left_joins(:account_provider).where(account_providers: { id: nil }).count
  end

  def total_accounts_count
    wealth_reader_accounts.count
  end

  def sync_status_summary
    latest = respond_to?(:latest_sync) ? latest_sync : syncs.ordered.first
    return nil unless latest

    if latest.respond_to?(:sync_stats) && latest.sync_stats.present?
      stats = latest.sync_stats
      linked = stats["linked_accounts"] || 0
      unlinked = stats["unlinked_accounts"] || 0
      total = stats["total_accounts"] || 0

      if total == 0
        "No accounts found"
      elsif unlinked == 0
        "#{linked} #{'account'.pluralize(linked)} synced"
      else
        "#{linked} synced, #{unlinked} need setup"
      end
    else
      linked = accounts.count
      unlinked = unlinked_accounts_count
      return "No accounts found" if total_accounts_count.zero?

      unlinked.zero? ? "#{linked} #{'account'.pluralize(linked)} synced" : "#{linked} synced, #{unlinked} need setup"
    end
  end

  def start_authorization(entity_code:, redirect_url:, state: nil)
    provider = wealth_reader_provider
    raise StandardError, "Wealth Reader is not configured" unless provider

    result = provider.authorize_url(
      redirect_uri: redirect_url,
      state: state || id,
      entity_code: entity_code
    )
    challenge = result[:challenge]

    update!(
      entity_code: entity_code,
      institution_name: institution_name.presence || entity_code,
      pkce_nonce: challenge.nonce,
      pkce_state: state || id,
      pkce_code_verifier: challenge.code_verifier,
      pkce_redirect_uri: redirect_url,
      status: :good
    )

    result[:url]
  end

  def complete_authorization(code:)
    provider = wealth_reader_provider
    raise StandardError, "Wealth Reader is not configured" unless provider
    raise StandardError, "PKCE verifier missing. Restart the bank link." if pkce_code_verifier.blank?

    data = provider.exchange_code(
      code: code,
      redirect_uri: pkce_redirect_uri,
      code_verifier: pkce_code_verifier
    )
    token_data = provider.payload_token(data)

    update!(
      token: token_data[:token],
      entity_code: token_data[:code].presence || entity_code,
      pkce_nonce: nil,
      pkce_state: nil,
      pkce_code_verifier: nil,
      pkce_redirect_uri: nil,
      status: :good,
      pending_account_setup: true
    )

    import_accounts_from_payload(provider.payload_accounts(data))
    data
  end

  def import_latest_wealth_reader_data
    provider = wealth_reader_provider
    raise StandardError, "Wealth Reader is not configured" unless provider
    unless session_valid?
      update!(status: :requires_update)
      raise StandardError, "Wealth Reader token is missing. Reconnect the bank."
    end

    WealthReaderItem::Importer.new(self, wealth_reader_provider: provider).import
  end

  def process_accounts
    wealth_reader_accounts.joins(:account).merge(Account.visible).filter_map do |account|
      WealthReaderAccount::Processor.new(account).process
      { wealth_reader_account_id: account.id, success: true }
    rescue => e
      Rails.logger.error("WealthReaderItem #{id} - Failed to process #{account.id}: #{e.message}")
      { wealth_reader_account_id: account.id, success: false, error: e.message }
    end
  end

  def schedule_account_syncs(parent_sync: nil, window_start_date: nil, window_end_date: nil)
    accounts.visible.filter_map do |account|
      account.sync_later(
        parent_sync: parent_sync,
        window_start_date: window_start_date,
        window_end_date: window_end_date
      )
      { account_id: account.id, success: true }
    rescue => e
      { account_id: account.id, success: false, error: e.message }
    end
  end

  def import_accounts_from_payload(accounts)
    Array(accounts).each do |raw|
      account = raw.with_indifferent_access
      uid = account[:uuid].presence || account[:code].presence
      next if uid.blank?

      wr_account = wealth_reader_accounts.find_or_initialize_by(uid: uid)
      wr_account.assign_attributes(
        name: account[:name].presence || "Account",
        account_id: uid,
        currency: account[:currency].presence || "EUR",
        iban: account[:code],
        account_type: account[:subtype],
        current_balance: parse_balance(account[:balances]),
        raw_payload: account,
        institution_metadata: { name: institution_display_name, code: entity_code }
      )
      wr_account.save!
    end
  end

  private
    def parse_balance(balances)
      return nil unless balances.is_a?(Hash)

      value = balances[:available] || balances["available"] || balances[:current] || balances["current"]
      return nil if value.blank?

      parsed = BigDecimal(value.to_s)
      parsed if parsed.finite?
    rescue ArgumentError
      nil
    end
end
