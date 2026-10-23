require 'json'

class RenameLegacyPlunkEmailPreferences < ActiveRecord::Migration[7.2]
  PREFERENCE_RENAMES = {
    'shipment_shipped_email_enabled' => 'fulfillment_fulfilled_email_enabled',
    'shipment_shipped_template_id' => 'fulfillment_fulfilled_template_id',
    'reimbursement_email_enabled' => 'return_refunded_email_enabled',
    'reimbursement_template_id' => 'return_refunded_template_id'
  }.freeze

  def up
    return unless table_exists?(:spree_integrations) && column_exists?(:spree_integrations, :preferences)

    integration_preferences.each do |row|
      preferences = decode_preferences(row['preferences'])
      next if preferences.blank?

      changed = false
      PREFERENCE_RENAMES.each do |old_key, new_key|
        next unless preferences.key?(old_key)

        preferences[new_key] = preferences[old_key] unless preferences.key?(new_key)
        preferences.delete(old_key)
        changed = true
      end

      update_preferences(row['id'], preferences) if changed
    end
  end

  def down
    return unless table_exists?(:spree_integrations) && column_exists?(:spree_integrations, :preferences)

    integration_preferences.each do |row|
      preferences = decode_preferences(row['preferences'])
      next if preferences.blank?

      changed = false
      PREFERENCE_RENAMES.each do |old_key, new_key|
        next unless preferences.key?(new_key)

        preferences[old_key] = preferences[new_key] unless preferences.key?(old_key)
        preferences.delete(new_key)
        changed = true
      end

      update_preferences(row['id'], preferences) if changed
    end
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
