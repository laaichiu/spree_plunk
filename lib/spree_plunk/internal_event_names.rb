module SpreePlunk
  # Private Spree events used by contact synchronization. Keep these constants
  # outside app/ so decorator reloads do not redefine them.
  module InternalEventNames
    CUSTOMER_EMAIL_CHANGED = 'spree_plunk.customer_email_changed'.freeze
    CUSTOMER_MARKETING_CONSENT_CHANGED = 'spree_plunk.customer_marketing_consent_changed'.freeze
    CUSTOMER_CONTACT_CHANGED = 'spree_plunk.customer_contact_changed'.freeze
    CUSTOMER_ADDRESS_CHANGED = 'spree_plunk.customer_address_changed'.freeze
  end
end
