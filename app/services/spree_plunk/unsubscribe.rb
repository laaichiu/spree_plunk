module SpreePlunk
  class Unsubscribe < Base
    prepend ::Spree::ServiceModule::Base

    def call(plunk_integration:, email:)
      return noop_result('missing_email') if email.blank?

      normalized_email = email.to_s.strip.downcase
      customer = ::Spree.customer_class.where(
        ::Spree.customer_class.arel_table[:email].lower.eq(normalized_email)
      ).first
      payload = ContactPresenter.new(
        customer: customer,
        email: email,
        store: plunk_integration.store
      ).call(subscribed: false)

      plunk_integration.unsubscribe_contact(payload)
    end
  end
end
