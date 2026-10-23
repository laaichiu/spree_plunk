module SpreePlunk
  # Kept as a small adapter for storefront analytics callers. Spree 6 no longer
  # has the global analytics_event_handlers registry, so this is not registered
  # during Spree 6 boot; lifecycle events are handled by Spree::Subscriber.
  class AnalyticsEventHandler
    attr_reader :customer, :store

    def initialize(options = {})
      @customer = options[:customer]
      @store = options[:store]
    end

    def client
      @client ||= store&.integrations&.active&.find_by(type: Spree::Integrations::Plunk.name)
    end

    def handle_event(event_name, properties = {})
      integration = client
      return if integration.blank?

      plunk_event_name = EventNames.storefront_analytics_event_name(event_name)
      return if plunk_event_name.blank?

      resource = resource_for(properties)
      return if resource.blank?

      email = email_for(properties)
      return if email.blank?

      TrackEventJob.perform_later(
        integration.id,
        plunk_event_name,
        resource&.class&.name,
        resource&.id,
        email
      )
    end

    private

    def resource_for(properties)
      property(properties, :product) || property(properties, :taxon) || property(properties, :order)
    end

    def email_for(properties)
      property(properties, :email).presence || order_email(properties) || customer&.email.presence
    end

    def order_email(properties)
      property(properties, :order)&.email.presence
    end

    def property(properties, key)
      properties[key] || properties[key.to_s]
    end
  end
end
