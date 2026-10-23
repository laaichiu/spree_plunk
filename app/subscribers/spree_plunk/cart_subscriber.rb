module SpreePlunk
  class CartSubscriber < Spree::Subscriber
    subscribes_to 'line_item.created', 'line_item.updated', 'line_item.deleted', async: false

    on 'line_item.created', :handle_line_item_event
    on 'line_item.updated', :handle_line_item_event
    on 'line_item.deleted', :handle_line_item_event

    private

    def handle_line_item_event(event)
      payload = event.payload
      event_name = plunk_event_name(payload['cart_activity_event'])
      return unless event_name

      email = payload['email']
      return if email.blank?

      integration = ::Spree::Integrations::Plunk.active.find_by(store_id: payload['store_id'])
      return unless integration

      SpreePlunk::TrackEventJob.perform_later(
        integration.id,
        event_name,
        nil,
        nil,
        email,
        payload
      )
    end

    def plunk_event_name(activity_type)
      case activity_type
      when 'added'
        SpreePlunk::EventNames::CART_ADDED
      when 'removed'
        SpreePlunk::EventNames::CART_REMOVED
      end
    end
  end
end
