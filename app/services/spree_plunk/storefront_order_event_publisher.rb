module SpreePlunk
  module StorefrontOrderEventPublisher
    module_function

    def publish_checkout_email_entered(order:, email:)
      normalized_email = normalize_email(email)
      return if order.blank? || normalized_email.blank?

      publish_order_event(
        order: order,
        event_name: 'checkout.email_entered',
        email: normalized_email
      )
    end

    def publish_checkout_step_events(order:, previous_state:, current_state:)
      return if order.blank?

      previous_step = customer_facing_step(previous_state)
      current_step = customer_facing_step(current_state)
      return if previous_step.blank? || current_step.blank? || previous_step == current_step

      previous_index = checkout_step_index(order, previous_step)
      current_index = checkout_step_index(order, current_step)

      if previous_index.present? && current_index.present? && current_index > previous_index
        order.checkout_steps[previous_index...current_index].each do |completed_step|
          next if completed_step == 'complete'

          publish_order_event(
            order: order,
            event_name: 'checkout.step_completed',
            extra_payload: {
              'checkout_step' => completed_step,
              'previous_checkout_step' => previous_step,
              'current_checkout_step' => current_step
            }
          )
        end
      end

      publish_checkout_step_viewed(
        order: order,
        checkout_step: current_step,
        previous_checkout_step: previous_step
      )
    end

    def publish_checkout_step_viewed(order:, checkout_step:, previous_checkout_step: nil)
      return if order.blank? || checkout_step.blank? || checkout_step == 'complete'

      publish_order_event(
        order: order,
        event_name: 'checkout.step_viewed',
        extra_payload: {
          'checkout_step' => checkout_step,
          'previous_checkout_step' => previous_checkout_step,
          'current_checkout_step' => checkout_step
        }
      )
    end

    def publish_coupon_event(order:, event_name:, coupon_code:, status_code: nil, error_message: nil)
      normalized_code = normalize_coupon_code(coupon_code)
      return if order.blank? || normalized_code.blank? || gift_card_code?(order, normalized_code)

      publish_order_event(
        order: order,
        event_name: event_name,
        extra_payload: {
          'coupon_code' => normalized_code,
          'coupon_status_code' => status_code&.to_s,
          'coupon_error' => error_message
        }
      )
    end

    def publish_order_event(order:, event_name:, email: nil, extra_payload: {})
      return if order.blank?

      resolved_email = normalize_email(email) || normalize_email(order.email) || normalize_email(customer_email(order))
      payload = base_payload(order: order, email: resolved_email).merge(compact_payload(extra_payload))

      ::Spree::Current.set(store: order.store) do
        order.publish_event(event_name, payload)
      end
    end

    def base_payload(order:, email:)
      is_cart = order.is_a?(::Spree::Cart)
      status = order.status if order.is_a?(::Spree::Order)
      checkout_step = order.current_checkout_step if is_cart
      payment_status = order.payment_status if order.is_a?(::Spree::Order)
      fulfillment_status = order.fulfillment_status if order.is_a?(::Spree::Order)
      delivery_total = order.delivery_total
      discount_total = order.discount_total
      number = is_cart ? order.prefixed_id : order.number

      payload = {
        'customer_id' => order.customer_id || order.customer&.id,
        'store_id' => order.store_id,
        'store_code' => order.store&.code,
        'email' => email,
        'order_id' => order.prefixed_id,
        'order_number' => number,
        'status' => status,
        'checkout_step' => checkout_step,
        'current_checkout_step' => checkout_step,
        'payment_status' => payment_status,
        'fulfillment_status' => fulfillment_status,
        'currency' => order.currency,
        'total' => order.total.to_f,
        'item_total' => order.item_total.to_f,
        'delivery_total' => delivery_total&.to_f,
        'tax_total' => order.tax_total.to_f,
        'discount_total' => discount_total&.to_f,
        'item_count' => order.total_quantity,
        'line_items_count' => order.line_items.size,
        'coupon_code' => normalize_coupon_code(order.coupon_code)
      }.compact
      payload[is_cart ? 'cart_record_id' : 'order_record_id'] = order.id
      payload
    end

    def compact_payload(payload)
      payload.each_with_object({}) do |(key, value), compacted|
        next if value.nil? || value == ''

        compacted[key.to_s] = value
      end
    end

    def customer_facing_step(state)
      value = state.to_s
      return if value.blank?

      value
    end

    def checkout_step_index(order, step)
      order.checkout_steps.index(step)
    end

    def customer_email(order)
      order.customer&.email
    end

    def gift_card_code?(order, coupon_code)
      order.store&.gift_cards&.find_by(code: coupon_code).present?
    end

    def normalize_coupon_code(value)
      value.to_s.strip.downcase.presence
    end

    def normalize_email(value)
      value.to_s.strip.downcase.presence
    end
  end
end
