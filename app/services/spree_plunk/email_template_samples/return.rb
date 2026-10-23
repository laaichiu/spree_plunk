module SpreePlunk
  module EmailTemplateSamples
    class Return < OrderConfirmation
      def variables
        super.merge(
          return: {
            number: 'R123456789',
            status: 'refunded',
            refunded_total: 24.0,
            refund_total: 24.0,
            returned_items: [order[:items].first]
          }
        )
      end
    end
  end
end
