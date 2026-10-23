module SpreePlunk
  module CartsUpdateDecorator
    def call(cart:, params:)
      previous_state = cart.current_checkout_step
      previous_email = normalize_email(cart.email)
      requested_email = extract_email(params)
      result = super

      return result if result.failure?

      current_email = normalize_email(cart.email)
      current_state = cart.current_checkout_step

      if requested_email.present? && current_email == requested_email && current_email != previous_email
        SpreePlunk::StorefrontOrderEventPublisher.publish_checkout_email_entered(
          order: cart,
          email: current_email
        )

        if previous_state == current_state
          SpreePlunk::StorefrontOrderEventPublisher.publish_checkout_step_viewed(
            order: cart,
            checkout_step: cart.current_checkout_step,
            previous_checkout_step: cart.current_checkout_step
          )
        end
      end

      if previous_state != current_state
        SpreePlunk::StorefrontOrderEventPublisher.publish_checkout_step_events(
          order: cart,
          previous_state: previous_state,
          current_state: current_state
        )
      end

      result
    end

    private

    def extract_email(params)
      source =
        if params.respond_to?(:to_h)
          params.to_h
        else
          params
        end

      normalize_email(source[:email] || source['email'])
    end

    def normalize_email(value)
      value.to_s.strip.downcase.presence
    end
  end
end

::Spree::Carts::Update.prepend(SpreePlunk::CartsUpdateDecorator)
