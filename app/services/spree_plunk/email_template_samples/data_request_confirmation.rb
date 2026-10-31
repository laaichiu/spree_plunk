module SpreePlunk
  module EmailTemplateSamples
    class DataRequestConfirmation < Base
      def variables
        {
          kind: 'access',
          confirmation_url: 'https://shop.example.com/account/data-request?token=preview',
          expires_at: '2026-11-30T12:00:00Z'
        }
      end
    end
  end
end
