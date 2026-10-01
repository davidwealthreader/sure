class WealthReaderItem::Syncer
  include SyncStats::Collector

  attr_reader :wealth_reader_item

  def initialize(wealth_reader_item)
    @wealth_reader_item = wealth_reader_item
  end

  def perform_sync(sync)
    unless wealth_reader_item.session_valid?
      sync.update!(status_text: "Re-authorization required") if sync.respond_to?(:status_text)
      wealth_reader_item.update!(status: :requires_update)
      collect_health_stats(sync, errors: nil)
      return
    end

    sync.update!(status_text: "Importing accounts from Wealth Reader...") if sync.respond_to?(:status_text)
    import_result = wealth_reader_item.import_latest_wealth_reader_data

    unless import_result[:success]
      if wealth_reader_item.requires_update?
        sync.update!(status_text: "Re-authorization required") if sync.respond_to?(:status_text)
        collect_health_stats(sync, errors: nil)
        return
      end
      raise StandardError, import_result[:error].presence || "Import failed"
    end

    collect_setup_stats(sync, provider_accounts: wealth_reader_item.wealth_reader_accounts.includes(:account_provider, :account))
    unlinked = wealth_reader_item.wealth_reader_accounts.left_joins(:account_provider).where(account_providers: { id: nil })
    wealth_reader_item.update!(pending_account_setup: unlinked.any?)

    linked_ids = wealth_reader_item.wealth_reader_accounts.joins(:account_provider).joins(:account).merge(Account.visible).pluck("accounts.id")
    if linked_ids.any?
      sync.update!(status_text: "Processing transactions...") if sync.respond_to?(:status_text)
      wealth_reader_item.process_accounts
      collect_transaction_stats(sync, account_ids: linked_ids, source: "wealth_reader")
      wealth_reader_item.schedule_account_syncs(
        parent_sync: sync,
        window_start_date: sync.window_start_date,
        window_end_date: sync.window_end_date
      )
    end

    collect_health_stats(sync, errors: nil)
  end
end
