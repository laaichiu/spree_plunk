module SpreePlunk
  class NewsletterSubscriber < Spree::Subscriber
    subscribes_to 'newsletter_subscriber.created', 'newsletter_subscriber.verified', 'newsletter_subscriber.deleted', async: false

    on 'newsletter_subscriber.created', :handle_subscriber_created
    on 'newsletter_subscriber.verified', :handle_subscriber_verified
    on 'newsletter_subscriber.deleted', :handle_subscriber_deletion

    private

    def handle_subscriber_created(event)
      subscriber = find_subscriber(event.payload['id'], event)
      return unless subscriber

      integration = plunk_integration(event, store: subscriber.store)
      return unless integration

      # A newly-created subscriber may still be waiting for double opt-in. Sync
      # its profile without changing Plunk's subscription state; the verified
      # event below is the only path that explicitly subscribes it.
      SpreePlunk::UpsertContactJob.perform_later(integration.id, ::Spree::NewsletterSubscriber.name, subscriber.id)
    end

    def handle_subscriber_verified(event)
      subscriber = find_subscriber(event.payload['id'], event)
      return unless subscriber
      return unless subscriber.verified? && subscriber.accepts_email_marketing

      integration = plunk_integration(event, store: subscriber.store)
      return unless integration

      SpreePlunk::SubscribeJob.perform_later(integration.id, subscriber.id)
      SpreePlunk::TrackEventJob.perform_later(
        integration.id,
        SpreePlunk::EventNames::NEWSLETTER_SUBSCRIBED,
        ::Spree::NewsletterSubscriber.name,
        subscriber.id,
        subscriber.email
      )
    end

    def handle_subscriber_deletion(event)
      return if SpreePlunk::EventContext.local_unsubscribe?

      email = event.payload['email']
      return if email.blank?

      integration = plunk_integration(event)
      return unless integration

      SpreePlunk::UnsubscribeJob.perform_later(integration.id, email)
      SpreePlunk::TrackEventJob.perform_later(
        integration.id,
        SpreePlunk::EventNames::NEWSLETTER_UNSUBSCRIBED,
        nil,
        nil,
        email,
        event.payload
      )
    end

    def find_subscriber(value, event)
      return if value.blank?

      scope = ::Spree::NewsletterSubscriber.all
      store = event_store(event)
      scope = scope.for_store(store) if store
      scope.find_by_param(value)
    end

    def plunk_integration(event, store: nil)
      store_id = store&.id || event_store(event)&.id
      return ::Spree::Integrations::Plunk.active.find_by(store_id: store_id) if store_id.present?

      default_store = ::Spree::Store.default
      ::Spree::Integrations::Plunk.active.find_by(store_id: default_store.id) if default_store
    end

    def event_store(event)
      ::Spree::Store.find_by_param(event.payload['store_id']) ||
        ::Spree::Store.find_by(id: event.store_id)
    end
  end
end
