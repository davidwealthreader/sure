module Family::WealthReaderConnectable
  extend ActiveSupport::Concern

  included do
    has_many :wealth_reader_items, dependent: :destroy
  end

  def can_connect_wealth_reader?
    true
  end
end
