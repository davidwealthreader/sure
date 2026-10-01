# Wealth Reader PKCE is not RFC 7636.
# nonce / state / code_verifier = hex(randomAlnum(41)).
# challenge_code = SHA-256 hex of the already-hex verifier.
# wr_conf is JSON encoded as hex.
# @see https://www.wealthreader.com/docs/en/oauth-backend/
class Provider::WealthReader::Pkce
  ALPHABET = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a
  ALNUM_LENGTH = 41

  Challenge = Data.define(:nonce, :wr_state, :code_verifier, :challenge, :wr_conf)

  def self.random_alnum(length = ALNUM_LENGTH)
    length.times.map { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join
  end

  def self.hex_alnum(length = ALNUM_LENGTH)
    random_alnum(length).unpack1("H*")
  end

  def self.generate(entity_code)
    nonce = hex_alnum
    wr_state = hex_alnum
    code_verifier = hex_alnum
    challenge = Digest::SHA256.hexdigest(code_verifier)
    wr_conf = {
      operation_id: "op_#{SecureRandom.hex(8)}",
      entities_to_display: entity_code.present? ? [ entity_code ] : [],
      wait_full_response: true
    }.to_json.unpack1("H*")

    Challenge.new(
      nonce: nonce,
      wr_state: wr_state,
      code_verifier: code_verifier,
      challenge: challenge,
      wr_conf: wr_conf
    )
  end
end
