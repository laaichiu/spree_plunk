module SpreePlunk
  class NewsletterSubscriberPresenter
    def initialize(subscriber:, store: nil)
      @subscriber = subscriber
      @store = store
    end

    def call
      {
        email: email,
        verified: verified?,
        verified_at: verified_at,
        customer_id: customer_id,
        store_code: store&.code
      }.reject { |_key, value| value.nil? || value == '' }
    end

    private

    attr_reader :subscriber, :store

    def email
      return subscriber['email'] if subscriber.is_a?(Hash)

      subscriber.email
    end

    def verified?
      if subscriber.is_a?(Hash)
        subscriber['verified']
      else
        subscriber.verified?
      end
    end

    def verified_at
      value =
        if subscriber.is_a?(Hash)
          subscriber['verified_at']
        else
          subscriber.verified_at
        end

      value.respond_to?(:iso8601) ? value.iso8601 : value
    end

    def customer_id
      if subscriber.is_a?(Hash)
        subscriber['customer_id']
      else
        subscriber.customer&.prefixed_id
      end
    end
  end
end
