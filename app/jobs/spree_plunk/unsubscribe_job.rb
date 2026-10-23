module SpreePlunk
  class UnsubscribeJob < BaseJob
    def perform(plunk_integration_id, email)
      plunk_integration = find_active_plunk_integration(plunk_integration_id)
      return unless plunk_integration
      return if email.blank?

      result = SpreePlunk::Unsubscribe.call(
        plunk_integration: plunk_integration,
        email: email
      )

      ensure_sync_success!(
        result,
        operation: 'unsubscribe_contact',
        integration_id: plunk_integration.id,
        store_id: plunk_integration.store_id,
        email_present: email.present?
      )
    end
  end
end
