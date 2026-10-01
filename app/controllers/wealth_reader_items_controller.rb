require "uri"

class WealthReaderItemsController < ApplicationController
  before_action :set_wealth_reader_item, only: [ :update, :destroy, :sync, :select_bank, :authorize, :reauthorize, :setup_accounts, :complete_account_setup, :new_connection ]
  before_action :require_admin!, except: [ :callback ]
  skip_before_action :verify_authenticity_token, only: [ :callback ]

  def create
    @wealth_reader_item = Current.family.wealth_reader_items.build(wealth_reader_item_params)
    @wealth_reader_item.name ||= "Wealth Reader Connection"

    if @wealth_reader_item.save
      render_panel_or_redirect(notice: t(".success", default: "Wealth Reader configured."))
    else
      render_panel_or_redirect(alert: @wealth_reader_item.errors.full_messages.to_sentence, status: :unprocessable_entity)
    end
  end

  def update
    if @wealth_reader_item.update(wealth_reader_item_params)
      render_panel_or_redirect(notice: t(".success", default: "Wealth Reader updated."))
    else
      render_panel_or_redirect(alert: @wealth_reader_item.errors.full_messages.to_sentence, status: :unprocessable_entity)
    end
  end

  def destroy
    @wealth_reader_item.unlink_all!(dry_run: false)
    @wealth_reader_item.destroy_later
    redirect_to settings_providers_path, notice: t(".success", default: "Scheduled Wealth Reader connection for deletion.")
  end

  def sync
    @wealth_reader_item.sync_later unless @wealth_reader_item.syncing?
    respond_to do |format|
      format.html { redirect_back_or_to accounts_path }
      format.json { head :ok }
    end
  end

  def select_bank
    unless @wealth_reader_item.credentials_configured?
      redirect_to settings_providers_path, alert: t(".credentials_required", default: "Configure your Wealth Reader API key first.")
      return
    end

    @new_connection = params[:new_connection] == "true"

    begin
      @entities = @wealth_reader_item.wealth_reader_provider.list_entities(country: @wealth_reader_item.country_code)
    rescue Provider::WealthReader::WealthReaderError => e
      @error_message = e.message
      @entities = []
    end

    render layout: false
  end

  def authorize
    entity_code = params[:entity_code].presence
    unless entity_code
      redirect_to settings_providers_path, alert: t(".bank_required", default: "Please select a bank.")
      return
    end

    begin
      target_item = if params[:new_connection] == "true"
        Current.family.wealth_reader_items.create!(
          name: "Wealth Reader Connection",
          country_code: @wealth_reader_item.country_code,
          api_key: @wealth_reader_item.api_key
        )
      else
        @wealth_reader_item
      end

      entity = target_item.wealth_reader_provider.list_entities(country: target_item.country_code)
        .find { |row| row[:code] == entity_code }
      target_item.update!(institution_name: entity&.dig(:name) || entity_code)

      url = target_item.start_authorization(
        entity_code: entity_code,
        redirect_url: wealth_reader_callback_url,
        state: target_item.id
      )
      raise StandardError, "Unexpected Wealth Reader host" unless URI.parse(url).host == "oauth.wealthreader.com"
      redirect_to url, allow_other_host: true
    rescue Provider::WealthReader::WealthReaderError => e
      redirect_to settings_providers_path, alert: e.message
    end
  end

  def new_connection
    redirect_to select_bank_wealth_reader_item_path(@wealth_reader_item, new_connection: true), data: { turbo_frame: "modal" }
  end

  def reauthorize
    unless @wealth_reader_item.entity_code.present?
      redirect_to select_bank_wealth_reader_item_path(@wealth_reader_item)
      return
    end

    url = @wealth_reader_item.start_authorization(
      entity_code: @wealth_reader_item.entity_code,
      redirect_url: wealth_reader_callback_url,
      state: @wealth_reader_item.id
    )
    raise StandardError, "Unexpected Wealth Reader host" unless URI.parse(url).host == "oauth.wealthreader.com"
    redirect_to url, allow_other_host: true
  rescue Provider::WealthReader::WealthReaderError => e
    redirect_to settings_providers_path, alert: e.message
  end

  def callback
    if params[:error].present?
      redirect_to settings_providers_path, alert: t(".authorization_error", default: "Authorization failed: %{error}", error: params[:error])
      return
    end

    unless params[:code].present? && (params[:state].present? || params[:nonce].present?)
      redirect_to settings_providers_path, alert: t(".invalid_callback", default: "Invalid callback parameters.")
      return
    end

    item = find_callback_item
    unless item
      redirect_to settings_providers_path, alert: t(".item_not_found", default: "Connection not found.")
      return
    end

    item.complete_authorization(code: params[:code])
    item.sync_later
    redirect_to accounts_path, notice: t(".success", default: "Connected. Your accounts are being synced.")
  rescue Provider::WealthReader::WealthReaderError, StandardError => e
    Rails.logger.error("Wealth Reader callback failed: #{e.message}")
    redirect_to settings_providers_path, alert: e.message
  end

  def setup_accounts
    @unlinked_accounts = @wealth_reader_item.wealth_reader_accounts.left_joins(:account_provider).where(account_providers: { id: nil })
    render layout: false
  end

  def complete_account_setup
    created = 0
    Array(params[:account_types]).each do |wealth_reader_account_id, selected_type|
      next if selected_type.blank? || selected_type == "skip"

      wr_account = @wealth_reader_item.wealth_reader_accounts.find(wealth_reader_account_id)
      account = Account.create_from_wealth_reader_account(wr_account, selected_type)
      AccountProvider.create!(account: account, provider: wr_account)
      created += 1
    end

    @wealth_reader_item.update!(pending_account_setup: false)
    @wealth_reader_item.sync_later if created.positive?
    redirect_to accounts_path, notice: t(".success", default: "%{count} account(s) created.", count: created), status: :see_other
  end

  private
    def set_wealth_reader_item
      @wealth_reader_item = Current.family.wealth_reader_items.find(params[:id])
    end

    def wealth_reader_item_params
      params.require(:wealth_reader_item).permit(:name, :country_code, :api_key)
    end

    def find_callback_item
      items = Current.family.wealth_reader_items
      items.find_by(id: params[:state]) ||
        items.find_by(pkce_state: params[:state]) ||
        items.find_by(pkce_nonce: params[:nonce])
    end

    def wealth_reader_callback_url
      helpers.wealth_reader_callback_url
    end

    def render_panel_or_redirect(notice: nil, alert: nil, status: :see_other)
      @wealth_reader_items = Current.family.wealth_reader_items.ordered
      if turbo_frame_request?
        flash.now[:notice] = notice if notice.present?
        flash.now[:alert] = alert if alert.present?
        streams = [
          turbo_stream.replace(
            "wealth_reader-providers-panel",
            partial: "settings/providers/wealth_reader_panel",
            locals: {
              wealth_reader_items: @wealth_reader_items,
              error_message: alert
            }
          )
        ]
        streams.concat(Array(flash_notification_stream_items))
        render turbo_stream: streams, status: alert.present? ? :unprocessable_entity : :ok
      elsif alert.present?
        redirect_to settings_providers_path, alert: alert, status: status
      else
        redirect_to settings_providers_path, notice: notice, status: status
      end
    end
end
