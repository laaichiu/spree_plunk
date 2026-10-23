module SpreePlunk
  module AddressDecorator
    def self.prepended(base)
      base.publishes_event InternalEventNames::CUSTOMER_ADDRESS_CHANGED, webhook: false
      base.before_validation :capture_spree_plunk_event_store
      base.before_update :capture_spree_plunk_previous_customer_owner
      base.before_destroy :capture_spree_plunk_previous_customer_owner
      base.after_commit :publish_spree_plunk_customer_address_changed, on: %i[create update destroy]
    end

    private

    def capture_spree_plunk_event_store
      @spree_plunk_event_store_id = ::Spree::Current.store&.id
    end

    def capture_spree_plunk_previous_customer_owner
      capture_spree_plunk_event_store
      return unless owner_type_in_database == ::Spree.customer_class.name

      @spree_plunk_previous_customer_owner_id = owner_id_in_database
    end

    def publish_spree_plunk_customer_address_changed
      customer_ids = [@spree_plunk_previous_customer_owner_id]
      customer_ids << owner_id if customer_owned?

      customer_ids.compact.uniq.each do |customer_id|
        customer = ::Spree.customer_class.find_by(id: customer_id)
        next unless customer

        store = ::Spree::Store.find_by(id: @spree_plunk_event_store_id) || ::Spree::Store.default
        ::Spree::Current.with_store(store) do
          publish_event(
            InternalEventNames::CUSTOMER_ADDRESS_CHANGED,
            {
              'customer_id' => customer.prefixed_id,
              'store_id' => store&.to_param
            }
          )
        end
      end
    ensure
      @spree_plunk_previous_customer_owner_id = nil
      @spree_plunk_event_store_id = nil
    end
  end
end

::Spree::Address.prepend(SpreePlunk::AddressDecorator)
