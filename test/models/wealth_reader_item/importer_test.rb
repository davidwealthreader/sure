require "test_helper"

class WealthReaderItem::ImporterTest < ActiveSupport::TestCase
  setup do
    @item = WealthReaderItem.create!(
      family: families(:dylan_family),
      name: "WR",
      country_code: "ES",
      api_key: "key",
      token: "tok",
      entity_code: "bbva"
    )
    @provider = Provider::WealthReader.new(api_key: "key")
  end

  test "skips transactions with non-numeric amounts" do
    @provider.stub :refresh, {
      payload: {
        accounts: [ {
          uuid: "acc-1",
          name: "Main",
          currency: "EUR",
          balances: { available: 10 },
          transactions: [
            { uuid: "bad", amount: "n/a", operation_date: "2024-02-01" },
            { uuid: "ok", amount: -12.5, operation_date: "2024-02-01", description: "Cafe" }
          ]
        } ]
      }
    } do
      result = WealthReaderItem::Importer.new(@item, wealth_reader_provider: @provider).import
      assert result[:success]
      assert_equal 1, result[:transactions_imported]
      txs = @item.wealth_reader_accounts.find_by(uid: "acc-1").raw_transactions_payload
      assert_equal 1, txs.size
      assert_equal "ok", txs.first["uuid"] || txs.first[:uuid]
    end
  end
end
