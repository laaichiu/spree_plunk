module SpreePlunk
  class UpsertContact < Base
    prepend ::Spree::ServiceModule::Base

    def call(plunk_integration:, customer: nil, subscriber: nil, address: nil, email: nil, subscribed: nil)
      payload = ContactPresenter.new(
        customer: customer,
        subscriber: subscriber,
        address: address,
        email: email,
        store: plunk_integration.store
      ).call(subscribed: subscribed)

      return noop_result('missing_email') if payload[:email].blank?

      if subscribed.nil?
        lookup = plunk_integration.lookup_contact(email: payload[:email])
        return lookup if lookup.failure?
        return lookup if lookup.value.is_a?(Hash) && (lookup.value[:skipped] || lookup.value['skipped'])

        found = lookup.value.is_a?(Hash) ? lookup.value[:found] || lookup.value['found'] : nil
        unless found.is_a?(Array)
          return failure_result(
            'invalid_contact_lookup_response',
            error_message: 'Plunk contact lookup did not return a found array.',
            retryable: false
          )
        end

        payload[:subscribed] = false unless found.include?(payload[:email])
      end

      plunk_integration.upsert_contact(payload)
    end

    private

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
