module SpreePlunk
  module EmailTemplateSamples
    class Fulfillment < OrderConfirmation
      def variables
        super.merge(
          fulfillment: {
            number: 'H123456789',
            tracking: '1Z999AA10123456784',
            tracking_url: 'https://tracking.example.com/1Z999AA10123456784',
            delivery_method_name: 'Standard delivery',
            manifest_items: order[:items]
          }
        )
      end
    end
  end
end
