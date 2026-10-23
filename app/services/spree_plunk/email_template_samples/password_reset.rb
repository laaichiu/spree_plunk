module SpreePlunk
  module EmailTemplateSamples
    class PasswordReset < Base
      def variables
        {
          customer: { first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com' },
          reset_url: 'https://shop.example.com/account/reset-password?token=preview'
        }
      end
    end
  end
end
