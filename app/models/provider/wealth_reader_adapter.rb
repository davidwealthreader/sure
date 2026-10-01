class Provider::WealthReaderAdapter < Provider::Base
  include Provider::Syncable
  include Provider::InstitutionMetadata

  Provider::Factory.register("WealthReaderAccount", self)

  def self.supported_account_types
    %w[Depository CreditCard]
  end

  def self.connection_configs(family:)
    return [] unless family.can_connect_wealth_reader?

    [ {
      key: "wealth_reader",
      name: "Wealth Reader",
      description: "Connect to your bank via Wealth Reader",
      can_connect: true,
      new_account_path: ->(_accountable_type, _return_to) {
        Rails.application.routes.url_helpers.settings_providers_path
      },
      existing_account_path: ->(_account_id) {
        Rails.application.routes.url_helpers.settings_providers_path
      }
    } ]
  end

  def provider_name
    "wealth_reader"
  end

  def self.build_provider(family: nil)
    return nil unless family.present?

    item = family.wealth_reader_items.where.not(api_key: nil).first
    return nil unless item&.credentials_configured?

    Provider::WealthReader.new(api_key: item.api_key)
  end

  def sync_path
    Rails.application.routes.url_helpers.sync_wealth_reader_item_path(item)
  end

  def item
    provider_account.wealth_reader_item
  end

  def can_delete_holdings?
    false
  end

  def institution_name
    item&.institution_display_name
  end
end
