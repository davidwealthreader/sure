class WealthReaderEntry::Processor
  def initialize(raw_transaction, wealth_reader_account:)
    @raw = raw_transaction.with_indifferent_access
    @wealth_reader_account = wealth_reader_account
  end

  def process
    account = wealth_reader_account.account
    return if account.blank?
    return if amount.nil? || date.blank?

    Account::ProviderImportAdapter.new(account).import_transaction(
      external_id: external_id,
      amount: amount,
      currency: currency,
      date: date,
      name: name,
      source: "wealth_reader",
      notes: @raw[:notes]
    )
  end

  private
    attr_reader :wealth_reader_account

    def external_id
      id = @raw[:uuid].presence
      return "wealth_reader_#{id}" if id

      "wealth_reader_#{date}_#{amount}_#{name}"
    end

    def amount
      BigDecimal(@raw[:amount].to_s)
    rescue ArgumentError
      nil
    end

    def date
      Date.iso8601(@raw[:date].to_s)
    rescue ArgumentError
      nil
    end

    def currency
      @raw[:currency].presence || wealth_reader_account.currency
    end

    def name
      @raw[:description].presence || "Wealth Reader"
    end
end
