module SpreePlunk
  module CustomerDecorator
    def self.install!
      customer_class = ::Spree.customer_class
      return unless customer_class
      return if customer_class.ancestors.include?(self)

      customer_class.prepend(self)
    end

    def self.prepended(base)
      base.publishes_event InternalEventNames::CUSTOMER_EMAIL_CHANGED, webhook: false
      base.publishes_event InternalEventNames::CUSTOMER_MARKETING_CONSENT_CHANGED, webhook: false
      base.publishes_event InternalEventNames::CUSTOMER_CONTACT_CHANGED, webhook: false
      base.before_validation :capture_spree_plunk_event_store
      base.before_validation :reset_marketing_consent_for_new_email
      base.after_commit :publish_spree_plunk_email_changed, on: :update
      base.after_commit :publish_spree_plunk_marketing_consent_changed, on: :update
      base.after_commit :publish_spree_plunk_customer_contact_changed, on: :update
    end

    private

    def reset_marketing_consent_for_new_email
      return unless persisted? && will_save_change_to_email?
      return unless spree_plunk_email_identity_changed?

      @spree_plunk_email_event_store_id = ::Spree::Current.store&.id
      if accepts_email_marketing?
        @spree_plunk_consent_event_store_id ||= ::Spree::Current.store&.id
        self.consent_source = ::Spree::ConsentRecord::UNKNOWN unless will_save_change_to_accepts_email_marketing? && !accepts_email_marketing?
        self.accepts_email_marketing = false
      end
    end

    def capture_spree_plunk_event_store
      store_id = ::Spree::Current.store&.id
      @spree_plunk_consent_event_store_id = store_id if will_save_change_to_accepts_email_marketing?
      @spree_plunk_contact_event_store_id = store_id
      if persisted? && will_save_change_to_email? && spree_plunk_email_identity_changed?
        @spree_plunk_newsletter_store_ids = if ::Spree::Events.lifecycle_enabled?
          ::Spree::NewsletterSubscriber.where(customer_id: id).distinct.pluck(:store_id)
        else
          []
        end
      end
    end

    def publish_spree_plunk_email_changed
      change = saved_change_to_email
      return unless change.present? && spree_plunk_email_values_changed?(change)

      store = ::Spree::Store.find_by(id: @spree_plunk_email_event_store_id) || ::Spree::Store.default
      return unless store

      ::Spree::Current.with_store(store) do
        EventContext.with_customer_email_change(
          customer_id: id,
          previous_email: change.first,
          subscriber_store_ids: @spree_plunk_newsletter_store_ids
        ) do
          publish_event(
            InternalEventNames::CUSTOMER_EMAIL_CHANGED,
            {
              'customer_id' => prefixed_id,
              'store_id' => store.to_param
            }
          )
        end
      end
    ensure
      @spree_plunk_email_event_store_id = nil
      @spree_plunk_newsletter_store_ids = nil
    end

    def publish_spree_plunk_marketing_consent_changed
      change = saved_change_to_accepts_email_marketing
      return unless change.present? && change.first != change.last

      store = ::Spree::Store.find_by(id: @spree_plunk_consent_event_store_id) || ::Spree::Store.default
      return unless store

      ::Spree::Current.with_store(store) do
        publish_event(
          InternalEventNames::CUSTOMER_MARKETING_CONSENT_CHANGED,
          {
            'customer_id' => prefixed_id,
            'store_id' => store.to_param,
            'accepts_email_marketing' => accepts_email_marketing?,
            'email_changed' => saved_change_to_email.present? && spree_plunk_email_values_changed?(saved_change_to_email)
          }
        )
      end
    ensure
      @spree_plunk_consent_event_store_id = nil
    end

    def publish_spree_plunk_customer_contact_changed
      return if spree_plunk_email_values_changed?(saved_change_to_email || [nil, nil])

      consent_change = saved_change_to_accepts_email_marketing
      return if consent_change.present? && consent_change.first != consent_change.last

      store = ::Spree::Store.find_by(id: @spree_plunk_contact_event_store_id) || ::Spree::Store.default
      return unless store

      ::Spree::Current.with_store(store) do
        publish_event(
          InternalEventNames::CUSTOMER_CONTACT_CHANGED,
          {
            'customer_id' => prefixed_id,
            'store_id' => store.to_param
          }
        )
      end
    ensure
      @spree_plunk_contact_event_store_id = nil
    end

    def spree_plunk_email_identity_changed?
      spree_plunk_email_values_changed?([email_in_database, email])
    end

    def spree_plunk_email_values_changed?(values)
      previous_email, current_email = values
      previous_email = previous_email.to_s.strip
      current_email = current_email.to_s.strip

      return false unless previous_email.present? && current_email.present?

      previous_email.downcase(:ascii) != current_email.downcase(:ascii)
    end
  end
end
