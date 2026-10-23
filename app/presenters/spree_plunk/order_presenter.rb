module SpreePlunk
  class OrderPresenter
    def initialize(order:, store: nil, email: nil)
      @order = order
      @store = store
      @email = email
    end

    def call
      status = order.status
      payment_status = order.payment_status
      fulfillment_status = order.fulfillment_status
      delivery_total = order.delivery_total
      discount_total = order.discount_total

      {
        order_id: order.prefixed_id,
        order_number: order.number,
        store_code: store_code,
        email: resolved_email,
        status: status,
        payment_status: payment_status,
        fulfillment_status: fulfillment_status,
        currency: order.currency,
        total: order.total.to_f,
        item_total: order.item_total.to_f,
        delivery_total: delivery_total&.to_f,
        tax_total: order.tax_total.to_f,
        discount_total: discount_total&.to_f,
        coupon_code: order.coupon_code,
        item_count: order.total_quantity,
        line_items_count: order.line_items.size,
        completed_at: iso8601(order.completed_at),
        canceled_at: iso8601(order.canceled_at)
      }.reject { |_key, value| value.nil? || value == '' }
    end

    private

    attr_reader :order, :store, :email

    def store_code
      store&.code || order.store&.code
    end

    def resolved_email
      email.presence || order.email.presence || order.customer&.email
    end

    def iso8601(value)
      value&.iso8601
    end

  end
end
