module SpreePlunk
  module EmailTemplateSamples
    class DigitalAsset < Base
      def variables
        {
          order: { number: 'R123456789', customer_name: 'Jane Doe' },
          downloads: [
            { filename: 'Digital guide.pdf', url: 'https://shop.example.com/download/preview', expires_at: '2026-11-30T12:00:00Z' }
          ],
          resend: false
        }
      end
    end
  end
end
