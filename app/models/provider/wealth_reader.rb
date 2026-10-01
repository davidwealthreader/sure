require "uri"

class Provider::WealthReader
  include HTTParty

  API_BASE = "https://api.wealthreader.com".freeze
  OAUTH_BASE = "https://oauth.wealthreader.com".freeze
  AUTH_ERROR_CODES = [ 1010, 1020, 2010, 2020 ].freeze

  headers "User-Agent" => "Sure Finance Wealth Reader Client"
  default_options.merge!(timeout: 120)

  attr_reader :api_key

  def initialize(api_key:)
    @api_key = api_key
  end

  def list_entities(country: nil)
    query = {}
    query[:country_code] = country.upcase if country.present?
    data = interpret(self.class.get("#{API_BASE}/entities/", query: query, headers: json_headers), "GET /entities/")
    raw = data[:payload] || data[:entities] || data
    Array(raw).filter_map do |item|
      next unless item.is_a?(Hash)

      row = item.with_indifferent_access
      next if row[:code].blank?

      {
        code: row[:code].to_s,
        name: (row[:name].presence || row[:code]).to_s,
        country: (row[:country_code].presence || row[:country]).to_s.upcase,
        logo: row[:logo]
      }
    end
  end

  def authorize_url(redirect_uri:, state:, entity_code:)
    challenge = Provider::WealthReader::Pkce.generate(entity_code)
    query = {
      challenge_code: challenge.challenge,
      code_challenge_method: "S256",
      redirect_uri: redirect_uri,
      response_type: "code",
      state: state,
      nonce: challenge.nonce,
      wr_conf: challenge.wr_conf
    }
    {
      url: "#{OAUTH_BASE}/oauth2/?#{URI.encode_www_form(query)}",
      nonce: challenge.nonce,
      challenge: challenge
    }
  end

  def exchange_code(code:, redirect_uri:, code_verifier:)
    interpret(
      self.class.post(
        "#{OAUTH_BASE}/token/",
        headers: form_headers,
        body: {
          grant_type: "authorization_code",
          redirect_uri: redirect_uri,
          code: code,
          code_verifier: code_verifier
        }
      ),
      "POST /token/"
    )
  end

  def refresh(token:, entity_code:, date_from: nil)
    body = {
      api_key: api_key,
      code: entity_code,
      token: token,
      product_types: "accounts"
    }
    body[:date_from] = date_from if date_from.present?
    interpret(
      self.class.post("#{API_BASE}/entities/", headers: form_headers, body: body),
      "POST /entities/"
    )
  end

  def payload_accounts(data)
    payload = data[:payload] || data["payload"] || {}
    accounts = payload[:accounts] || payload["accounts"] || []
    Array(accounts)
  end

  def payload_token(data)
    stats = data[:statistics] || data["statistics"] || {}
    token = stats[:token] || stats["token"]
    raise WealthReaderError.new("Token exchange returned no statistics.token — register the redirect with tokenize=1", :invalid_input) if token.blank?

    {
      token: token,
      code: stats[:code] || stats["code"]
    }
  end

  private
    def json_headers
      { "Accept" => "application/json" }
    end

    def form_headers
      { "Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json" }
    end

    def interpret(response, path)
      if response.code == 429
        raise WealthReaderError.new("Wealth Reader #{path} → 429", :rate_limited)
      end
      if [ 401, 410 ].include?(response.code)
        raise WealthReaderError.new("Wealth Reader #{path} → #{response.code}", :invalid_access_token)
      end
      unless response.success?
        raise WealthReaderError.new("Wealth Reader #{path} → #{response.code}", :internal_error)
      end

      data = parse_body(response)
      if data[:success] == false || data["success"] == false
        error = data[:error] || data["error"] || {}
        code = (error[:code] || error["code"]).to_i
        message = error[:message] || error["message"] || "success=false"
        if AUTH_ERROR_CODES.include?(code)
          raise WealthReaderError.new("Wealth Reader error #{code}: #{message}", :invalid_access_token)
        end
        raise WealthReaderError.new("Wealth Reader error #{code}: #{message}", :internal_error)
      end
      data
    end

    def parse_body(response)
      return {} if response.body.blank?

      JSON.parse(response.body, symbolize_names: true)
    rescue JSON::ParserError
      raise WealthReaderError.new("Failed to parse Wealth Reader response", :parse_error)
    end

    class WealthReaderError < StandardError
      attr_reader :error_type

      def initialize(message, error_type = :unknown)
        super(message)
        @error_type = error_type
      end

      def reauth_required?
        error_type == :invalid_access_token
      end
    end
end
