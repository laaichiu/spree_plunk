module SpreePlunk
  module EventContext
    LOCAL_UNSUBSCRIBE_KEY = :spree_plunk_local_unsubscribe
    CUSTOMER_EMAIL_CHANGE_KEY = :spree_plunk_customer_email_change

    def self.local_unsubscribe?
      RequestStore.store[LOCAL_UNSUBSCRIBE_KEY]
    end

    def self.with_local_unsubscribe
      previous = RequestStore.store[LOCAL_UNSUBSCRIBE_KEY]
      RequestStore.store[LOCAL_UNSUBSCRIBE_KEY] = true
      yield
    ensure
      RequestStore.store[LOCAL_UNSUBSCRIBE_KEY] = previous
    end

    def self.with_customer_email_change(customer_id:, previous_email:, subscriber_store_ids: nil)
      previous = RequestStore.store[CUSTOMER_EMAIL_CHANGE_KEY]
      RequestStore.store[CUSTOMER_EMAIL_CHANGE_KEY] = {
        customer_id: customer_id,
        previous_email: previous_email,
        subscriber_store_ids: subscriber_store_ids,
        sync_claimed: false
      }
      yield
    ensure
      RequestStore.store[CUSTOMER_EMAIL_CHANGE_KEY] = previous
    end

    def self.claim_customer_email_change_sync(customer_id)
      context = RequestStore.store[CUSTOMER_EMAIL_CHANGE_KEY]
      return true unless context && context[:customer_id].to_s == customer_id.to_s
      return false if context[:sync_claimed]

      context[:sync_claimed] = true
    end

    def self.previous_customer_email(customer_id)
      context = RequestStore.store[CUSTOMER_EMAIL_CHANGE_KEY]
      return unless context && context[:customer_id].to_s == customer_id.to_s

      context[:previous_email]
    end

    def self.customer_email_change_subscriber_store_ids(customer_id)
      context = RequestStore.store[CUSTOMER_EMAIL_CHANGE_KEY]
      return unless context && context[:customer_id].to_s == customer_id.to_s

      context[:subscriber_store_ids]
    end
  end
end
