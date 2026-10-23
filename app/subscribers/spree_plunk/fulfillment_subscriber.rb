module SpreePlunk
  class FulfillmentSubscriber < Spree::Subscriber
    subscribes_to 'fulfillment.fulfilled', async: false

    on 'fulfillment.fulfilled', :handle_fulfillment_fulfilled

    private

    def handle_fulfillment_fulfilled(event)
      fulfillment = ::Spree::Fulfillment.find_by_param(event.payload['id'])
      return unless fulfillment

      purchase = fulfillment.owner
      email = purchase&.email

      integration = ::Spree::Integrations::Plunk.active.find_by(store_id: purchase&.store_id)
      return unless integration

      SpreePlunk::TrackEventJob.perform_later(
        integration.id,
        SpreePlunk::EventNames::FULFILLMENT_FULFILLED,
        ::Spree::Fulfillment.name,
        fulfillment.id,
        email
      )
    end
  end
end
