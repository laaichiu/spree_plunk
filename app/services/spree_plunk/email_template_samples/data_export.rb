module SpreePlunk
  module EmailTemplateSamples
    class DataExport < Base
      def variables
        {
          download_url: 'https://shop.example.com/api/downloads/preview',
          expires_at: '2026-11-30T12:00:00Z'
        }
      end
    end
  end
end
