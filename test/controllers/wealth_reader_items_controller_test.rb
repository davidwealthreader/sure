require "test_helper"

class WealthReaderItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @item = WealthReaderItem.create!(
      family: @family,
      name: "WR",
      country_code: "ES",
      api_key: "key",
      pkce_nonce: "stored-nonce",
      pkce_state: "stored-state",
      pkce_code_verifier: "verifier",
      pkce_redirect_uri: "https://sure.test/wealth_reader_items/callback"
    )
  end

  test "callback can resolve the item by nonce when state is omitted" do
    provider = Provider::WealthReader.new(api_key: "key")
    WealthReaderItem.any_instance.stubs(:wealth_reader_provider).returns(provider)
    provider.stubs(:exchange_code).returns(
      statistics: { token: "tok", code: "bbva" },
      payload: { accounts: [] }
    )
    WealthReaderItem.any_instance.stubs(:sync_later)

    get callback_wealth_reader_items_path, params: { code: "auth", nonce: "stored-nonce" }

    assert_redirected_to accounts_path
    assert_equal "tok", @item.reload.token
  end
end
