module SpreePlunk
  class ContactSubscriber < Spree::Subscriber
    subscribes_to 'user.created', 'spree_plunk.customer_contact_changed', 'spree_plunk.customer_address_changed',
                  SpreePlunk::CustomerDecorator::EMAIL_CHANGED_EVENT,
                  SpreePlunk::CustomerDecorator::MARKETING_CONSENT_CHANGED_EVENT, async: false

    on 'user.created', :handle_customer_event
    on 'spree_plunk.customer_contact_changed', :handle_customer_profile_changed
    on 'spree_plunk.customer_address_changed', :handle_customer_address_changed
    on SpreePlunk::CustomerDecorator::EMAIL_CHANGED_EVENT, :handle_customer_email_changed
    on SpreePlunk::CustomerDecorator::MARKETING_CONSENT_CHANGED_EVENT, :handle_customer_marketing_consent_changed

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

      integration = plunk_integration(event)
      return unless integration

      SpreePlunk::UpsertContactJob.perform_later(integration.id, ::Spree.customer_class.name, customer.id)
    end

    def handle_customer_email_changed(event)
      customer = find_record(::Spree.customer_class, event.payload['customer_id'])
      return unless customer

      integrations = plunk_integrations_for_customer(event, customer).to_a

      ::Spree::NewsletterSubscriber.where(customer_id: customer.id).includes(:store).find_each do |newsletter_subscriber|
        store = newsletter_subscriber.store
        next unless store

        ::Spree::Current.with_store(store) do
          newsletter_subscriber.destroy!
        end
      end

      integrations.each do |integration|
        SpreePlunk::UpsertContactJob.perform_later(integration.id, ::Spree.customer_class.name, customer.id, nil, false)
      end
    end

    def handle_customer_marketing_consent_changed(event)
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
