class CreateWealthReaderItemsAndAccounts < ActiveRecord::Migration[7.2]
  def change
    create_table :wealth_reader_items, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :name
      t.string :institution_name
      t.string :status, default: "good"
      t.boolean :scheduled_for_deletion, default: false
      t.boolean :pending_account_setup, default: false
      t.datetime :sync_start_date
      t.jsonb :raw_payload
      t.string :country_code
      t.string :entity_code
      t.text :api_key
      t.text :token
      t.string :pkce_nonce
      t.string :pkce_state
      t.text :pkce_code_verifier
      t.text :pkce_redirect_uri
      t.timestamps
    end

    add_index :wealth_reader_items, :status
    add_index :wealth_reader_items, :pkce_nonce
    add_index :wealth_reader_items, :pkce_state

    create_table :wealth_reader_accounts, id: :uuid do |t|
      t.references :wealth_reader_item, null: false, foreign_key: true, type: :uuid
      t.string :name
      t.string :account_id
      t.string :currency
      t.decimal :current_balance, precision: 19, scale: 4
      t.string :account_type
      t.string :iban
      t.string :uid
      t.jsonb :institution_metadata
      t.jsonb :raw_payload
      t.jsonb :raw_transactions_payload
      t.timestamps
    end

    add_index :wealth_reader_accounts, :account_id
    add_index :wealth_reader_accounts, [ :wealth_reader_item_id, :uid ], unique: true, name: "idx_wr_accounts_item_uid"
  end
end
