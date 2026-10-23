module SpreePlunk
  module EventNames
    CART_ADDED = 'spree.cart.added'.freeze
    CART_REMOVED = 'spree.cart.removed'.freeze
    CHECKOUT_EMAIL_ENTERED = 'spree.checkout.email_entered'.freeze
    CHECKOUT_STEP_VIEWED = 'spree.checkout.step_viewed'.freeze
    CHECKOUT_STEP_COMPLETED = 'spree.checkout.step_completed'.freeze
    COUPON_ENTERED = 'spree.coupon.entered'.freeze
    COUPON_REMOVED = 'spree.coupon.removed'.freeze
    COUPON_APPLIED = 'spree.coupon.applied'.freeze
    COUPON_DENIED = 'spree.coupon.denied'.freeze
    NEWSLETTER_SUBSCRIBED = 'spree.newsletter.subscribed'.freeze
    NEWSLETTER_UNSUBSCRIBED = 'spree.newsletter.unsubscribed'.freeze
    ORDER_PLACED = 'spree.order.placed'.freeze
    ORDER_CANCELED = 'spree.order.canceled'.freeze
    FULFILLMENT_FULFILLED = 'spree.fulfillment.fulfilled'.freeze
    RETURN_REFUNDED = 'spree.return.refunded'.freeze

    STOREFRONT_ANALYTICS_EVENT_MAP = {}.freeze

    def self.storefront_analytics_event_name(event_name)
      STOREFRONT_ANALYTICS_EVENT_MAP[event_name.to_s]
    end
  end
end
