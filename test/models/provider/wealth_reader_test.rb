require "test_helper"
require "ostruct"

class Provider::WealthReaderTest < ActiveSupport::TestCase
  test "PKCE challenge is SHA-256 hex of the already-hex verifier" do
    challenge = Provider::WealthReader::Pkce.generate("bbva")

    assert_equal 82, challenge.nonce.length
    assert_equal 82, challenge.code_verifier.length
    assert_equal Digest::SHA256.hexdigest(challenge.code_verifier), challenge.challenge
    assert_includes [ challenge.wr_conf ].pack("H*"), "bbva"
  end

  test "authorize_url includes nonce and wr_conf" do
    provider = Provider::WealthReader.new(api_key: "key")
    result = provider.authorize_url(
      redirect_uri: "https://sure.example/wealth_reader_items/callback",
      state: "item-1",
      entity_code: "bbva"
    )

    uri = URI.parse(result[:url])
    params = URI.decode_www_form(uri.query).to_h
    assert_equal result[:nonce], params["nonce"]
    assert_equal result[:challenge].challenge, params["challenge_code"]
    assert_equal "S256", params["code_challenge_method"]
    assert result[:nonce].present?
  end

  test "payload_token requires statistics.token" do
    provider = Provider::WealthReader.new(api_key: "key")
    error = assert_raises(Provider::WealthReader::WealthReaderError) do
      provider.payload_token({ statistics: {} })
    end
    assert_equal :invalid_input, error.error_type
  end

  test "auth error codes require reauth" do
    provider = Provider::WealthReader.new(api_key: "key")
    response = OpenStruct.new(
      code: 200,
      success?: true,
      body: { success: false, error: { code: 1010, message: "login required" } }.to_json
    )

    Provider::WealthReader.stub :post, response do
      error = assert_raises(Provider::WealthReader::WealthReaderError) do
        provider.refresh(token: "t", entity_code: "bbva")
      end
      assert error.reauth_required?
    end
  end
end
