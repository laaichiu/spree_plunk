module SpreePlunk
  module EmailTemplateSamples
    class PaymentLink < OrderConfirmation
      def variables
        super.merge(payment_url: 'https://shop.example.com/checkout/preview-token/payment')
      end
    end
  end
end
