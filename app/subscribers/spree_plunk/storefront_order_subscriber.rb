module SpreePlunk
  class StorefrontOrderSubscriber < Spree::Subscriber
    subscribes_to 'checkout.email_entered',
                  'checkout.step_viewed',
                  'checkout.step_completed',
                  'coupon.entered',
                  'coupon.removed',
                  'coupon.applied',
                  'coupon.denied',
                  async: false

    on 'checkout.email_entered', :handle_order_event
    on 'checkout.step_viewed', :handle_order_event
    on 'checkout.step_completed', :handle_order_event
    on 'coupon.entered', :handle_order_event
    on 'coupon.removed', :handle_order_event
    on 'coupon.applied', :handle_order_event
    on 'coupon.denied', :handle_order_event

    EVENT_NAME_MAP = {
      'checkout.email_entered' => SpreePlunk::EventNames::CHECKOUT_EMAIL_ENTERED,
      'checkout.step_viewed' => SpreePlunk::EventNames::CHECKOUT_STEP_VIEWED,
      'checkout.step_completed' => SpreePlunk::EventNames::CHECKOUT_STEP_COMPLETED,
      'coupon.entered' => SpreePlunk::EventNames::COUPON_ENTERED,
      'coupon.removed' => SpreePlunk::EventNames::COUPON_REMOVED,
      'coupon.applied' => SpreePlunk::EventNames::COUPON_APPLIED,
      'coupon.denied' => SpreePlunk::EventNames::COUPON_DENIED
    }.freeze

    private

    def handle_order_event(event)
      payload = event.payload
      event_name = EVENT_NAME_MAP[event.name]
      return unless event_name

      email = payload['email']
      return if email.blank?

      integration = ::Spree::Integrations::Plunk.active.find_by(store_id: event.store_id || payload['store_id'])
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
  end
end
