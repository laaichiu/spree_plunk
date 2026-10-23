module SpreePlunk
  module TransactionalEmailTypes
    PASSWORD_RESET = 'password_reset'.freeze
    NEWSLETTER_CONFIRMATION = 'newsletter_confirmation'.freeze
    ORDER_CONFIRMATION = 'order_confirmation'.freeze
    ORDER_CONFIRMATION_RESEND = 'order_confirmation_resend'.freeze
    ORDER_CANCELLATION = 'order_cancellation'.freeze
    FULFILLMENT_FULFILLED = 'fulfillment_fulfilled'.freeze
    RETURN_REFUNDED = 'return_refunded'.freeze
    STORE_OWNER_NOTIFICATION = 'store_owner_notification'.freeze

    ALL = [
      PASSWORD_RESET,
      NEWSLETTER_CONFIRMATION,
      ORDER_CONFIRMATION,
      ORDER_CONFIRMATION_RESEND,
      ORDER_CANCELLATION,
      FULFILLMENT_FULFILLED,
      RETURN_REFUNDED,
      STORE_OWNER_NOTIFICATION
    ].freeze
  end
end
