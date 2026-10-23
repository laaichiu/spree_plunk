require 'spec_helper'
load File.expand_path('../../db/migrate/20261022000000_rename_legacy_plunk_email_preferences.rb', __dir__)

RSpec.describe RenameLegacyPlunkEmailPreferences do
  it 'renames the saved fulfillment and return email preferences' do
    integration = create(:plunk_integration, active: false)
    write_raw_preferences(
      integration,
      integration.preferences.to_h.stringify_keys.except(
        'fulfillment_fulfilled_email_enabled',
        'fulfillment_fulfilled_template_id',
        'return_refunded_email_enabled',
        'return_refunded_template_id'
      ).merge(
        'shipment_shipped_email_enabled' => true,
        'shipment_shipped_template_id' => 'tpl_fulfillment_old',
        'reimbursement_email_enabled' => true,
        'reimbursement_template_id' => 'tpl_return_old'
      )
    )

    described_class.new.up
    integration.reload

    expect(integration.preferences).to include(
      'fulfillment_fulfilled_email_enabled' => true,
      'fulfillment_fulfilled_template_id' => 'tpl_fulfillment_old',
      'return_refunded_email_enabled' => true,
      'return_refunded_template_id' => 'tpl_return_old'
    )
    expect(integration.preferences.keys).not_to include(
      'shipment_shipped_email_enabled',
      'shipment_shipped_template_id',
      'reimbursement_email_enabled',
      'reimbursement_template_id'
    )
  end

  it 'keeps the new preference if both old and new names are present' do
    integration = create(:plunk_integration, active: false)
    write_raw_preferences(
      integration,
      integration.preferences.to_h.stringify_keys.merge(
        'shipment_shipped_email_enabled' => false,
        'fulfillment_fulfilled_email_enabled' => true
      )
    )

    described_class.new.up
    integration.reload

    expect(integration.preferred_fulfillment_fulfilled_email_enabled).to be(true)
    expect(integration.preferences).not_to have_key('shipment_shipped_email_enabled')
  end

  private

  def write_raw_preferences(integration, preferences)
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      UPDATE #{connection.quote_table_name(:spree_integrations)}
      SET #{connection.quote_column_name(:preferences)} = #{connection.quote(JSON.generate(preferences))}
      WHERE #{connection.quote_column_name(:id)} = #{connection.quote(integration.id)}
    SQL
  end
end
