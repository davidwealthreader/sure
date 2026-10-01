class WealthReaderAccount::Processor
  include CurrencyNormalizable

  def initialize(wealth_reader_account)
    @wealth_reader_account = wealth_reader_account
  end

  def process
    account = wealth_reader_account.current_account
    return unless account

    if wealth_reader_account.current_balance.present?
      Account::ProviderImportAdapter.new(account).update_balance(
        balance: wealth_reader_account.current_balance,
        cash_balance: wealth_reader_account.current_balance
      )
    end

    Array(wealth_reader_account.raw_transactions_payload).each do |tx|
      WealthReaderEntry::Processor.new(tx, wealth_reader_account: wealth_reader_account).process
    end
  end

  private
    attr_reader :wealth_reader_account
end
