module SpreePlunk
  class StorefrontOrderEventPresenter
    def initialize(payload:, store: nil, email: nil)
      @payload = payload
      @store = store
      @email = email
    end

    def call
      payment_status = value('payment_status')
      fulfillment_status = value('fulfillment_status')
      delivery_total = numeric_value('delivery_total')
      status = value('status')

      {
        order_id: value('order_id'),
        order_number: value('order_number'),
        store_code: value('store_code') || store&.code,
        email: resolved_email,
        status: status,
        checkout_step: value('checkout_step'),
        previous_checkout_step: value('previous_checkout_step'),
        current_checkout_step: value('current_checkout_step'),
        payment_status: payment_status,
        fulfillment_status: fulfillment_status,
        currency: value('currency'),
        total: numeric_value('total'),
        item_total: numeric_value('item_total'),
        delivery_total: delivery_total,
        tax_total: numeric_value('tax_total'),
        discount_total: numeric_value('discount_total'),
        item_count: value('item_count'),
        line_items_count: value('line_items_count'),
        coupon_code: value('coupon_code'),
        coupon_status_code: value('coupon_status_code'),
        coupon_error: value('coupon_error')
      }.reject { |_key, value| value.nil? || value == '' }
    end

    private

    attr_reader :payload, :store, :email

    def value(key)
      payload[key] || payload[key.to_sym]
    end

    def numeric_value(key)
      value = value(key)
      return if value.nil?

      value.to_f
    end

    def resolved_email
      email.presence || value('email')
    end
  end
end
