module SpreePlunk
  module EmailTemplateSamples
    class NewsletterConfirmation < Base
      def variables
        { confirmation_url: 'https://shop.example.com/newsletter/confirm?token=preview' }
      end
    end
  end
end
