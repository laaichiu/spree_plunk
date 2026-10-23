module SpreePlunk
  class FulfillmentPresenter
    def initialize(fulfillment:, store: nil)
      @fulfillment = fulfillment
      @store = store
    end

    def call
      delivery_method = fulfillment.delivery_method
      {
        fulfillment_id: fulfillment.prefixed_id,
        fulfillment_number: fulfillment.number,
        fulfillment_status: fulfillment.status,
        tracking: fulfillment.tracking,
        delivery_method_name: delivery_method&.name,
        stock_location_name: fulfillment.stock_location&.name,
        store_code: store_code,
        order_id: purchase&.prefixed_id,
        order_number: purchase_number,
        currency: fulfillment.currency,
        delivery_total: fulfillment.cost.to_f,
        discount_total: fulfillment.discount_total.to_f,
        fulfilled_at: iso8601(fulfillment.fulfilled_at)
      }.reject { |_key, value| value.nil? || value == '' }
    end

    private

    attr_reader :fulfillment, :store

    def purchase
      fulfillment.owner
    end

    def purchase_number
      return unless purchase
      return purchase.prefixed_id if purchase.is_a?(::Spree::Cart)

      purchase.number
    end

    def store_code
      store&.code || fulfillment.store&.code
    end

    def iso8601(value)
      value&.iso8601
    end
  end
end
