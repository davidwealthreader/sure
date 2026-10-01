class WealthReaderItem::Importer
  attr_reader :wealth_reader_item, :wealth_reader_provider

  def initialize(wealth_reader_item, wealth_reader_provider:)
    @wealth_reader_item = wealth_reader_item
    @wealth_reader_provider = wealth_reader_provider
  end

  def import
    unless wealth_reader_item.session_valid?
      wealth_reader_item.update!(status: :requires_update)
      return { success: false, error: "Token missing", accounts_updated: 0, transactions_imported: 0 }
    end

    date_from = wealth_reader_item.sync_start_date&.to_date&.iso8601
    data = wealth_reader_provider.refresh(
      token: wealth_reader_item.token,
      entity_code: wealth_reader_item.entity_code,
      date_from: date_from
    )
    wealth_reader_item.update!(raw_payload: data, status: :good)
    accounts = wealth_reader_provider.payload_accounts(data)
    wealth_reader_item.import_accounts_from_payload(accounts)

    transactions_imported = 0
    accounts_updated = 0

    Array(accounts).each do |raw|
      account = raw.with_indifferent_access
      uid = account[:uuid].presence || account[:code].presence
      wr_account = wealth_reader_item.wealth_reader_accounts.find_by(uid: uid)
      next unless wr_account

      txs = Array(account[:transactions]).filter_map { |tx| normalize_tx(tx) }
      wr_account.update!(raw_transactions_payload: txs)
      transactions_imported += txs.size
      accounts_updated += 1
    end

    { success: true, accounts_updated: accounts_updated, transactions_imported: transactions_imported }
  rescue Provider::WealthReader::WealthReaderError => e
    if e.reauth_required?
      wealth_reader_item.update!(status: :requires_update)
      return { success: false, error: e.message, accounts_updated: 0, transactions_imported: 0 }
    end
    raise
  end

  private
    def normalize_tx(raw)
      tx = raw.with_indifferent_access
      return nil if tx[:amount].blank?

      amount = BigDecimal(tx[:amount].to_s)
      return nil unless amount.finite?

      date = (tx[:operation_date].presence || tx[:value_date].presence).to_s.slice(0, 10)
      return nil unless date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      {
        uuid: tx[:uuid],
        date: date,
        amount: amount.to_s,
        currency: tx[:currency],
        description: tx[:description].presence || tx.dig(:transfer_details, :sender_receiver),
        notes: tx.dig(:transfer_details, :concept)
      }
    rescue ArgumentError
      nil
    end
end
