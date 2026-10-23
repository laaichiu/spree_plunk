module SpreePlunk
  module EmailTemplateSamples
    # Static, non-customer sample data for the dashboard's preview and publish
    # checks. These previews work before a store has any orders or customers.
    class Base
      attr_reader :store

      def initialize(store:, record_id: nil)
        @store = store
      end

      def self.record_type
        nil
      end

      def self.required_permissions
        []
      end

      def recent_records(limit: 5)
        []
      end

      def currency
        store.default_currency
      end
    end
  end
end
