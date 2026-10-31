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
    DIGITAL_ASSET_READY = 'digital_asset_ready'.freeze
    COMPANY_INVITATION = 'company_invitation'.freeze
    DATA_REQUEST_CONFIRMATION = 'data_request_confirmation'.freeze
    DATA_EXPORT_READY = 'data_export_ready'.freeze
    PAYMENT_LINK = 'payment_link'.freeze
    SELLER_APPROVED = 'seller_approved'.freeze
    SELLER_SUSPENDED = 'seller_suspended'.freeze
    SELLER_REJECTED = 'seller_rejected'.freeze

    ALL = [
      PASSWORD_RESET,
      NEWSLETTER_CONFIRMATION,
      ORDER_CONFIRMATION,
      ORDER_CONFIRMATION_RESEND,
      ORDER_CANCELLATION,
      FULFILLMENT_FULFILLED,
      RETURN_REFUNDED,
      STORE_OWNER_NOTIFICATION,
      DIGITAL_ASSET_READY,
      COMPANY_INVITATION,
      DATA_REQUEST_CONFIRMATION,
      DATA_EXPORT_READY,
      PAYMENT_LINK,
      SELLER_APPROVED,
      SELLER_SUSPENDED,
      SELLER_REJECTED
    ].freeze
  end
end
