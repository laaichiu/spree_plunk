module SpreePlunk
  class ContactSubscriber < Spree::Subscriber
    subscribes_to 'user.created', SpreePlunk::InternalEventNames::CUSTOMER_CONTACT_CHANGED,
                  SpreePlunk::InternalEventNames::CUSTOMER_ADDRESS_CHANGED,
                  SpreePlunk::InternalEventNames::CUSTOMER_EMAIL_CHANGED,
                  SpreePlunk::InternalEventNames::CUSTOMER_MARKETING_CONSENT_CHANGED, async: false

    on 'user.created', :handle_customer_event
    on SpreePlunk::InternalEventNames::CUSTOMER_CONTACT_CHANGED, :handle_customer_profile_changed
    on SpreePlunk::InternalEventNames::CUSTOMER_ADDRESS_CHANGED, :handle_customer_address_changed
    on SpreePlunk::InternalEventNames::CUSTOMER_EMAIL_CHANGED, :handle_customer_email_changed
    on SpreePlunk::InternalEventNames::CUSTOMER_MARKETING_CONSENT_CHANGED, :handle_customer_marketing_consent_changed

    private

    def handle_customer_event(event)
      customer = find_record(::Spree.customer_class, event.payload['id'])
      return unless customer

      plunk_integrations_for_customer(event, customer).each do |integration|
        SpreePlunk::UpsertContactJob.perform_later(integration.id, ::Spree.customer_class.name, customer.id)
      end
    end

    def handle_customer_profile_changed(event)
      customer = find_record(::Spree.customer_class, event.payload['customer_id'])
      return unless customer

      plunk_integrations_for_customer(event, customer).each do |integration|
        SpreePlunk::UpsertContactJob.perform_later(integration.id, ::Spree.customer_class.name, customer.id)
      end
    end

    def handle_customer_address_changed(event)
      customer = find_record(::Spree.customer_class, event.payload['customer_id'])
      return unless customer

      plunk_integrations_for_customer(event, customer).each do |integration|
        SpreePlunk::UpsertContactJob.perform_later(integration.id, ::Spree.customer_class.name, customer.id)
      end
    end

    def handle_customer_email_changed(event)
      customer = find_record(::Spree.customer_class, event.payload['customer_id'])
      return unless customer
      return unless SpreePlunk::EventContext.claim_customer_email_change_sync(customer.id)

      integrations = plunk_integrations_for_customer(event, customer).to_a
      previous_email = SpreePlunk::EventContext.previous_customer_email(customer.id)
      subscriber_scope = ::Spree::NewsletterSubscriber.where(customer_id: customer.id)
      previous_email ||= subscriber_scope.pick(:email)
      subscribed_store_ids = SpreePlunk::EventContext.customer_email_change_subscriber_store_ids(customer.id)
      subscribed_store_ids ||= subscriber_scope.distinct.pluck(:store_id)

      subscriber_scope.includes(:store).find_each do |newsletter_subscriber|
        store = newsletter_subscriber.store
        next unless store

        ::Spree::Current.with_store(store) do
          newsletter_subscriber.destroy!
        end
      end

      integrations.each do |integration|
        if previous_email.present? && !subscribed_store_ids.include?(integration.store_id)
          SpreePlunk::UnsubscribeJob.perform_later(integration.id, previous_email)
        end
        SpreePlunk::UpsertContactJob.perform_later(integration.id, ::Spree.customer_class.name, customer.id, nil, false)
      end
    end

    def handle_customer_marketing_consent_changed(event)
      return if SpreePlunk::EventContext.local_unsubscribe?
      return if event.payload['email_changed']

      customer = find_record(::Spree.customer_class, event.payload['customer_id'])
      return unless customer

      subscribed = event.payload['accepts_email_marketing']
      subscribed = customer.accepts_email_marketing? if subscribed.nil?

      plunk_integrations_for_customer(event, customer).each do |integration|
        SpreePlunk::UpsertContactJob.perform_later(
          integration.id,
          ::Spree.customer_class.name,
          customer.id,
          nil,
          subscribed
        )
      end
    end

    def find_record(klass, value)
      return if value.blank?

      klass.find_by_param(value)
    end

    def plunk_integration(event)
      store_id = event_store_id(event)
      return if store_id.blank?

      ::Spree::Integrations::Plunk.active.find_by(store_id: store_id)
    end

    def plunk_integrations_for_customer(event, customer)
      store_ids = [event_store_id(event)]
      store_ids.concat(::Spree::NewsletterSubscriber.where(customer_id: customer.id).distinct.pluck(:store_id))

      ::Spree::Integrations::Plunk.active.where(store_id: store_ids.compact.uniq)
    end

    def event_store_id(event)
      ::Spree::Store.find_by_param(event.payload['store_id'])&.id ||
        event.store_id.presence ||
        ::Spree::Store.default&.id
    end
  end
end
