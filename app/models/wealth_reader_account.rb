class WealthReaderAccount < ApplicationRecord
  include CurrencyNormalizable, Encryptable

  if encryption_ready?
    encrypts :raw_payload
    encrypts :raw_transactions_payload
  end

  belongs_to :wealth_reader_item
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, through: :account_provider, source: :account

  validates :name, :currency, presence: true
  validates :uid, presence: true, uniqueness: { scope: :wealth_reader_item_id }

  def current_account
    account
  end

  def suggested_account_type
    case account_type.to_s.downcase
    when /card|credit/
      "CreditCard"
    when /loan|mortgage/
      "Loan"
    else
      "Depository"
    end
  end
end
