module SpreePlunk
  class SendTransactionalEmailJob < BaseJob
    def perform(plunk_integration_id, email_type, resource_type = nil, resource_id = nil, email = nil, event_payload = nil)
      plunk_integration = find_active_plunk_integration(plunk_integration_id)
      return unless plunk_integration

      resource = load_resource(resource_type, resource_id)
      return if resource_type.present? && resource_id.present? && resource.nil?

      result = SpreePlunk::SendTransactionalEmail.call(
        plunk_integration: plunk_integration,
        email_type: email_type,
        resource: resource,
        email: email,
        event_payload: event_payload,
        idempotency_key: job_id
      )

      ensure_sync_success!(
        result,
        operation: 'send_transactional_email',
        integration_id: plunk_integration.id,
        store_id: plunk_integration.store_id,
        email_type: email_type,
        resource_type: resource_type,
        resource_id: resource_id,
        email_present: email.present?,
        event_payload_present: event_payload.present?
      )
    end

    private

    def load_resource(resource_type, resource_id)
      return nil if resource_type.blank? || resource_id.blank?

      resource_type.constantize.find_by(id: resource_id)
    rescue NameError
      nil
    end
  end
end
