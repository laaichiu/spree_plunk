module SpreePlunk
  class TrackEvent < Base
    prepend ::Spree::ServiceModule::Base

    def call(plunk_integration:, event_name:, resource: nil, email: nil)
      if newsletter_subscribe_event?(event_name) && !verified_newsletter_subscriber?(resource, plunk_integration)
        return noop_result('newsletter_subscriber_not_verified')
      end

      resolved_email = email.presence || resolve_email(resource)
      return noop_result('missing_email') if resolved_email.blank?

      contact_result = ensure_contact(
        plunk_integration: plunk_integration,
        event_name: event_name,
        resource: resource,
        email: resolved_email
      )
      return contact_result if contact_result.failure?

      contact_id = contact_result.value['id']
      return failure_result(
        'missing_contact_id',
        error_message: 'Plunk contact upsert succeeded but did not return a contact id.',
        retryable: true
      ) if contact_id.blank?

      payload = EventPresenter.new(
        event_name: event_name,
        contact_id: contact_id,
        resource: resource,
        store: plunk_integration.store,
        email: resolved_email
      ).call

      plunk_integration.track_event(payload)
    end

    private

    def ensure_contact(plunk_integration:, event_name:, resource:, email:)
      SpreePlunk::UpsertContact.call(
        plunk_integration: plunk_integration,
        customer: resolve_customer(resource),
        subscriber: resolve_subscriber(resource),
        address: resolve_address(resource),
        email: email,
        subscribed: subscription_state_for(event_name)
      )
    end

    def resolve_customer(resource)
      case resource
      when ::Spree::NewsletterSubscriber
        resource.customer
      when ::Spree::Order, ::Spree::Cart
        resource.customer
      when ::Spree::LineItem
        resource.owner&.customer
      when ::Spree::Fulfillment
        resource.owner&.customer
      when ::Spree::Return
        resource.order&.customer
      when Hash
        resolve_snapshot_customer(resource)
      end
    end

    def resolve_subscriber(resource)
      resource if resource.is_a?(::Spree::NewsletterSubscriber)
    end

    def resolve_address(resource)
      case resource
      when ::Spree::Order, ::Spree::Cart
        resource.bill_address || resource.ship_address
      when ::Spree::LineItem
        purchase = resource.owner
        purchase&.bill_address || purchase&.ship_address
      when ::Spree::Fulfillment
        purchase = resource.owner
        resource.address || purchase&.bill_address || purchase&.ship_address
      when ::Spree::Return
        resource.order&.bill_address || resource.order&.ship_address
      when Hash
        resolve_snapshot_order(resource)&.bill_address || resolve_snapshot_order(resource)&.ship_address
      end
    end

    def resolve_email(resource)
      case resource
      when ::Spree::NewsletterSubscriber
        resource.email
      when ::Spree::Order, ::Spree::Cart
        resource.email
      when ::Spree::LineItem
        purchase = resource.owner
        purchase&.email.presence || purchase&.customer&.email
      when ::Spree::Fulfillment
        resource.owner&.email
      when ::Spree::Return
        resource.order&.email
      when Hash
        resource['email']
      end
    end

    def resolve_snapshot_customer(resource)
      customer_id = resource['customer_id'] || resource[:customer_id]
      return if customer_id.blank?

      ::Spree.customer_class.find_by(id: customer_id)
    end

    def resolve_snapshot_order(resource)
      cart_id = resource['cart_record_id'] || resource[:cart_record_id]
      return ::Spree::Cart.find_by(id: cart_id) if cart_id.present?

      order_id = resource['order_record_id'] || resource[:order_record_id]
      return if order_id.blank?

      ::Spree::Order.find_by(id: order_id)
    end

    def subscription_state_for(event_name)
      case event_name
      when SpreePlunk::EventNames::NEWSLETTER_SUBSCRIBED
        true
      when SpreePlunk::EventNames::NEWSLETTER_UNSUBSCRIBED
        false
      end
    end

    def newsletter_subscribe_event?(event_name)
      event_name == SpreePlunk::EventNames::NEWSLETTER_SUBSCRIBED
    end

    def verified_newsletter_subscriber?(resource, plunk_integration)
      resource.is_a?(::Spree::NewsletterSubscriber) &&
        resource.verified? &&
        resource.accepts_email_marketing &&
        resource.store_id == plunk_integration.store_id
    end

    def failure_result(reason, error_message:, retryable:)
      ::Spree::ServiceModule::Result.new(false, {
        error: reason,
        error_code: reason,
        error_message: error_message,
        retryable: retryable
      })
    end
  end
end
