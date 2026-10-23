module SpreePlunk
  class SubscribeJob < BaseJob
    def perform(plunk_integration_id, subscriber_id)
      plunk_integration = find_active_plunk_integration(plunk_integration_id)
      return unless plunk_integration

      subscriber = ::Spree::NewsletterSubscriber.find_by(id: subscriber_id)
      return unless subscriber

      result = SpreePlunk::Subscribe.call(
        plunk_integration: plunk_integration,
        subscriber: subscriber
      )

      ensure_sync_success!(
        result,
        operation: 'subscribe_contact',
        integration_id: plunk_integration.id,
        store_id: plunk_integration.store_id,
        subscriber_id: subscriber_id
      )
    end
  end
end
