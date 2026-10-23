module SpreePlunk
  class OrderSubscriber < Spree::Subscriber
    subscribes_to 'order.placed', 'order.canceled', async: false

    on 'order.placed', :handle_order_placed
    on 'order.canceled', :handle_order_canceled

    private

    def handle_order_placed(event)
      enqueue_order_event(event, SpreePlunk::EventNames::ORDER_PLACED)
    end

    def handle_order_canceled(event)
      enqueue_order_event(event, SpreePlunk::EventNames::ORDER_CANCELED)
    end

    def enqueue_order_event(event, event_name)
      order = ::Spree::Order.find_by_param(event.payload['id'])
      return unless order

      integration = ::Spree::Integrations::Plunk.active.find_by(store_id: order.store_id)
      return unless integration

      SpreePlunk::TrackEventJob.perform_later(
        integration.id,
        event_name,
        ::Spree::Order.name,
        order.id,
        order.email
      )
    end
  end
end
