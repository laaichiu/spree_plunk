require 'json'

class RemoveUnsupportedPlunkPaymentLinkPreferences < ActiveRecord::Migration[7.2]
  PREFERENCE_KEYS = %w[payment_link_email_enabled payment_link_template_id].freeze

  def up
    return unless table_exists?(:spree_integrations) && column_exists?(:spree_integrations, :preferences)

    integration_preferences.each do |row|
      preferences = decode_preferences(row['preferences'])
      next unless (preferences.keys & PREFERENCE_KEYS).any?

      PREFERENCE_KEYS.each { |key| preferences.delete(key) }
      update_preferences(row['id'], preferences)
    end
  end

  # Removed settings have no Spree 6 trigger or supported sender to restore.
  def down
    nil
  end

  private

  def integration_preferences
    select_all(<<~SQL)
      SELECT id, preferences
      FROM #{quote_table_name(:spree_integrations)}
      WHERE type = #{quote('Spree::Integrations::Plunk')}
    SQL
  end

  def decode_preferences(value)
    preferences = value.is_a?(String) ? JSON.parse(value) : value
    return {} unless preferences.is_a?(Hash)

    preferences.each_with_object({}) { |(key, item), result| result[key.to_s] = item }
  rescue JSON::ParserError
    {}
  end

  def update_preferences(id, preferences)
    execute(<<~SQL)
      UPDATE #{quote_table_name(:spree_integrations)}
      SET #{quote_column_name(:preferences)} = #{quote(JSON.generate(preferences))}
      WHERE #{quote_column_name(:id)} = #{quote(id)}
    SQL
  end
end
