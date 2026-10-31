module SpreePlunk
  class ContactPresenter
    def initialize(customer: nil, subscriber: nil, address: nil, email: nil, store: nil)
      @customer = customer || subscriber&.customer || address&.customer_owner
      @subscriber = subscriber
      @address = address
      @store = store
      @email = email
    end

    def call(subscribed:)
      payload = {
        email: resolved_email,
        data: contact_data
      }

      payload[:subscribed] = subscribed unless subscribed.nil?
      payload.delete(:data) if payload[:data].empty?
      payload
    end

    private

    attr_reader :customer, :subscriber, :address, :store, :email

    def resolved_email
      email.presence || subscriber&.email.presence || customer&.email.presence
    end

    def contact_data
      {
        external_user_id: customer&.id,
        store_code: store&.code,
        first_name: first_name,
        last_name: last_name,
        phone: phone,
        accepts_email_marketing: accepts_email_marketing,
        city: resolved_address&.city,
        region: resolved_address&.state_name_text,
        country: resolved_address&.country_name,
        zip: resolved_address&.postal_code,
        order_count: order_count,
        last_order_number: last_order&.number,
        last_order_total: last_order&.total&.to_f
      }.reject { |_key, value| value.nil? || value == '' }
    end

    def first_name
      customer&.first_name.presence || resolved_address&.first_name.presence
    end

    def last_name
      customer&.last_name.presence || resolved_address&.last_name.presence
    end

    def phone
      customer&.phone.presence || resolved_address&.phone.presence
    end

    def accepts_email_marketing
      return subscriber.accepts_email_marketing if subscriber

      customer&.accepts_email_marketing
    end

    def resolved_address
      @resolved_address ||= address || customer&.bill_address || customer&.ship_address
    end

    def order_count
      store_orders&.count
    end

    def last_order
      return unless customer

      @last_order ||= store_orders&.reorder(completed_at: :desc, id: :desc)&.first
    end

    def store_orders
      return unless customer && store

      @store_orders ||= customer.completed_orders_for_store(store)
    end
  end
end
