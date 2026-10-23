module SpreePlunk
  module CheckoutAdvanceDecorator
    def call(order:, state: nil, shipping_method_id: nil)
      previous_state = order.current_checkout_step
      result = super

      return result if result.failure?
      current_state = order.current_checkout_step
      return result if previous_state == current_state

      SpreePlunk::StorefrontOrderEventPublisher.publish_checkout_step_events(
        order: order,
        previous_state: previous_state,
        current_state: current_state
      )

      result
    end
  end
end

::Spree::Checkout::Advance.prepend(SpreePlunk::CheckoutAdvanceDecorator)
