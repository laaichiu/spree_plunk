module SpreePlunk
  class UpsertContactJob < BaseJob
    def perform(plunk_integration_id, resource_type, resource_id, address_id = nil, subscribed = nil)
      plunk_integration = find_active_plunk_integration(plunk_integration_id)
      return unless plunk_integration

      result =
        case resource_type
        when ::Spree::NewsletterSubscriber.name
          subscriber = ::Spree::NewsletterSubscriber.find_by(id: resource_id)
          return unless subscriber

          SpreePlunk::UpsertContact.call(
            plunk_integration: plunk_integration,
            subscriber: subscriber,
            subscribed: subscribed
          )
        when ::Spree.customer_class.name
          customer = ::Spree.customer_class.find_by(id: resource_id)
          return unless customer

          address = ::Spree::Address.find_by(id: address_id) if address_id.present?

          SpreePlunk::UpsertContact.call(
            plunk_integration: plunk_integration,
            customer: customer,
            address: address,
            subscribed: subscribed
          )
        end

      ensure_sync_success!(
        result,
        operation: 'upsert_contact',
        integration_id: plunk_integration.id,
        store_id: plunk_integration.store_id,
        resource_type: resource_type,
        resource_id: resource_id,
        address_id: address_id
      )
    end
  end
end
