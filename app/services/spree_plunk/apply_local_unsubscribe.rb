module SpreePlunk
  class ApplyLocalUnsubscribe < Base
    def call(email:, store: ::Spree::Current.store || ::Spree::Store.default)
      normalized_email = normalize_email(email)
      return noop_result('missing_email') if normalized_email.blank?
      return noop_result('missing_store') if store.blank?

      subscriber = ::Spree::NewsletterSubscriber.for_store(store).find_by(email: normalized_email)
      return noop_result('local_email_not_found') if subscriber.blank?

      customer = subscriber.customer
      subscriber_id = subscriber&.id
      customer_updated = false

      ::Spree::Events.disable do
        ::Spree::Current.with_store(store) do
          ActiveRecord::Base.transaction do
            subscriber.destroy!
            customer_updated = unsubscribe_customer!(customer)
          end
        end
      end

      success(
        email: normalized_email,
        unsubscribed: true,
        subscriber_removed: subscriber.present?,
        subscriber_id: subscriber_id,
        customer_updated: customer_updated
      )
    rescue ActiveRecord::ActiveRecordError => e
      failure(
        {
          error_class: e.class.name,
          error_message: e.message,
          email: normalized_email,
          reason: 'persistence_error'
        },
        e.message
      )
    end

    private

    def normalize_email(value)
      value.to_s.strip.downcase.presence
    end

    def unsubscribe_customer!(customer)
      return false unless customer
      return false unless customer.accepts_email_marketing?
      return false if ::Spree::NewsletterSubscriber.where(customer_id: customer.id).exists?

      customer.consent_source = ::Spree::ConsentRecord::NEWSLETTER
      customer.update!(accepts_email_marketing: false)
      true
    end
  end
end
