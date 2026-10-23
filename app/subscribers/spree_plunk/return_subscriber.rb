module SpreePlunk
  class ReturnSubscriber < Spree::Subscriber
    subscribes_to 'return.refunded', async: false

    on 'return.refunded', :handle_return_refunded

    private

    def handle_return_refunded(event)
      return_record = ::Spree::Return.find_by_param(event.payload['id'])
      order = return_record&.order
      email = order&.email
      return unless return_record

      integration = ::Spree::Integrations::Plunk.active.find_by(store_id: order&.store_id)
      return unless integration

      SpreePlunk::TrackEventJob.perform_later(
        integration.id,
        SpreePlunk::EventNames::RETURN_REFUNDED,
        ::Spree::Return.name,
        return_record.id,
        email
      )
    end
  end
end
