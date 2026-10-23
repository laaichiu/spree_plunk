module SpreePlunk
  module LineItemDecorator
    def event_payload_for(event_name, **params)
      payload = super.stringify_keys
      @_current_event_name = event_name
      cart_activity_event = cart_activity_event_name

      payload.merge(snapshot_payload).tap do |merged_payload|
        merged_payload['cart_activity_event'] = cart_activity_event if cart_activity_event.present?
      end
    ensure
      @_current_event_name = nil
    end

    def event_payload
      payload = super.stringify_keys
      cart_activity_event = cart_activity_event_name

      payload.merge(snapshot_payload).tap do |merged_payload|
        merged_payload['cart_activity_event'] = cart_activity_event if cart_activity_event.present?
      end
    end

    private

    def capture_pre_destroy_payload
      @_current_event_name = "#{event_prefix}.deleted"
      super
    ensure
      @_current_event_name = nil
    end

    def cart_activity_event_name
      case @_current_event_name
      when "#{event_prefix}.created"
        quantity.to_i.positive? ? 'added' : nil
      when "#{event_prefix}.updated"
        return unless saved_change_to_quantity?

        previous_quantity, current_quantity = saved_change_to_quantity
        return 'added' if current_quantity.to_i > previous_quantity.to_i
        return 'removed' if current_quantity.to_i < previous_quantity.to_i
      when "#{event_prefix}.deleted"
        quantity.to_i.positive? ? 'removed' : nil
      end
    end

    def snapshot_payload
      purchase = owner
      is_cart = purchase.is_a?(::Spree::Cart)

      payload = {
        'customer_id' => purchase&.customer_id,
        'store_id' => purchase&.store_id,
        'store_code' => purchase&.store&.code,
        'email' => resolved_event_email,
        'line_item_id' => prefixed_id,
        'line_item_record_id' => id,
        'order_id' => purchase&.prefixed_id,
        'order_number' => is_cart ? purchase&.prefixed_id : purchase&.number,
        'quantity' => quantity,
        'previous_quantity' => previous_quantity,
        'unit_price' => price.to_f,
        'line_item_total' => amount.to_f,
        'currency' => purchase&.currency,
        'variant_id' => variant&.prefixed_id,
        'product_id' => product&.prefixed_id,
        'product_name' => name,
        'sku' => sku
      }
      payload[is_cart ? 'cart_record_id' : 'order_record_id'] = purchase.id if purchase
      payload.compact
    end

    def previous_quantity
      if @_current_event_name == "#{event_prefix}.updated" && saved_change_to_quantity?
        saved_change_to_quantity.first
      elsif @_current_event_name == "#{event_prefix}.deleted"
        quantity
      end
    end

    def resolved_event_email
      purchase = owner
      purchase&.email.presence || purchase&.customer&.email.presence
    end
  end
end

::Spree::LineItem.prepend(SpreePlunk::LineItemDecorator)
