# frozen_string_literal: true

module WealthReaderItem::Unlinking
  extend ActiveSupport::Concern

  def unlink_all!(dry_run: false)
    results = []

    wealth_reader_accounts.find_each do |wra|
      links = AccountProvider.where(provider_type: "WealthReaderAccount", provider_id: wra.id).to_a
      result = { wra_id: wra.id, name: wra.name, provider_link_ids: links.map(&:id) }
      results << result
      next if dry_run

      ActiveRecord::Base.transaction do
        Holding.where(account_provider_id: links.map(&:id)).update_all(account_provider_id: nil) if links.any?
        links.each(&:destroy!)
      end
    rescue => e
      Rails.logger.warn("WealthReaderItem Unlinker: failed for #{wra.id}: #{e.message}")
      result[:error] = e.message
    end

    results
  end
end
