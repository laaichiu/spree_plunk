require 'spec_helper'
load File.expand_path('../../db/migrate/20261023000000_remove_unsupported_plunk_payment_link_preferences.rb', __dir__)

RSpec.describe RemoveUnsupportedPlunkPaymentLinkPreferences do
  it 'removes unsupported payment-link preferences while keeping supported settings' do
    integration = create(:plunk_integration, active: false)
    write_raw_preferences(
      integration,
      integration.preferences.to_h.stringify_keys.merge(
        'payment_link_email_enabled' => true,
        'payment_link_template_id' => 'tpl_old',
        'order_confirmation_email_enabled' => true
      )
    )

    described_class.new.up

    expect(integration.reload.preferences).to include('order_confirmation_email_enabled' => true)
    expect(integration.preferences.keys).not_to include('payment_link_email_enabled', 'payment_link_template_id')
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
