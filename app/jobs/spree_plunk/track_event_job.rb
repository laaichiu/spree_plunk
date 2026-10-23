module SpreePlunk
  class TrackEventJob < BaseJob
    def perform(plunk_integration_id, event_name, resource_type = nil, resource_id = nil, email = nil, resource_payload = nil)
      plunk_integration = find_active_plunk_integration(plunk_integration_id)
      return unless plunk_integration

      resource = load_resource(resource_type, resource_id, resource_payload)

      result = SpreePlunk::TrackEvent.call(
        plunk_integration: plunk_integration,
        event_name: event_name,
        resource: resource,
        email: email
      )

      ensure_sync_success!(
        result,
        operation: 'track_event',
        integration_id: plunk_integration.id,
        store_id: plunk_integration.store_id,
        event_name: event_name,
        resource_type: resource_type,
        resource_id: resource_id,
        email_present: email.present?,
        resource_payload_present: resource_payload.present?
      )
    end

    private

    def load_resource(resource_type, resource_id, resource_payload)
      return resource_payload if resource_payload.present?
      return nil if resource_type.blank? || resource_id.blank?

      resource_type.constantize.find_by(id: resource_id)
    end
  end
end
