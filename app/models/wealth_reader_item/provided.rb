module WealthReaderItem::Provided
  extend ActiveSupport::Concern

  def wealth_reader_provider
    return nil unless credentials_configured?

    Provider::WealthReader.new(api_key: api_key)
  end
end
