require "test_helper"

class WealthReaderItemTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @item = WealthReaderItem.new(
      family: @family,
      name: "WR",
      country_code: "ES",
      api_key: "key"
    )
  end

  test "session is valid only with token and entity" do
    assert_not @item.session_valid?
    @item.token = "tok"
    @item.entity_code = "bbva"
    assert @item.session_valid?
  end

  test "unlinked_accounts_count ignores linked rows" do
    @item.save!
    @item.import_accounts_from_payload([
      { uuid: "a1", name: "One", currency: "EUR" },
      { uuid: "a2", name: "Two", currency: "EUR" }
    ])
    assert_equal 2, @item.unlinked_accounts_count
  end

  test "import skips accounts without uuid or iban" do
    @item.save!
    @item.import_accounts_from_payload([ { name: "orphan" }, { uuid: "acc-1", name: "Nomina", currency: "EUR" } ])
    assert_equal 1, @item.wealth_reader_accounts.count
    assert_equal "acc-1", @item.wealth_reader_accounts.first.uid
  end

  test "complete_authorization stores token and clears pkce" do
    @item.pkce_code_verifier = "verifier"
    @item.pkce_redirect_uri = "https://sure.test/wealth_reader_items/callback"
    @item.pkce_nonce = "nonce"
    @item.save!

    provider = Provider::WealthReader.new(api_key: "key")
    @item.stub :wealth_reader_provider, provider do
      provider.stub :exchange_code, {
        statistics: { token: "tok", code: "bbva" },
        payload: { accounts: [ { uuid: "a1", name: "Main", currency: "EUR", balances: { available: 10 } } ] }
      } do
        @item.complete_authorization(code: "auth-code")
      end
    end

    @item.reload
    assert_equal "tok", @item.token
    assert_equal "bbva", @item.entity_code
    assert_nil @item.pkce_nonce
    assert_equal "a1", @item.wealth_reader_accounts.first.uid
  end
end
