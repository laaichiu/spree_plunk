module SpreePlunk
  class ReturnPresenter
    def initialize(return_record:, store: nil)
      @return_record = return_record
      @store = store
    end

    def call
      returned_items = return_record.return_line_items

      {
        return_id: return_record.prefixed_id,
        return_number: return_record.number,
        return_status: return_record.status,
        store_code: store_code,
        order_id: order&.prefixed_id,
        order_number: order&.number,
        currency: return_record.currency,
        refund_total: return_record.refund_total.to_f,
        refunded_total: return_record.refunded_total.to_f,
        refundable_total: return_record.refundable_total.to_f,
        return_items_count: returned_items.size,
        performed_by_id: return_record.created_by&.id
      }.reject { |_key, value| value.nil? || value == '' }
    end

    private

    attr_reader :return_record, :store

    def order
      return_record.order
    end

    def store_code
      store&.code || return_record.store&.code
    end

  end
end
