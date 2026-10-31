module SpreePlunk
  module EmailTemplateSamples
    class CompanyInvitation < Base
      def variables
        {
          company: { name: 'Example Company' },
          accept_url: 'https://shop.example.com/account/company-invitation?token=preview'
        }
      end
    end
  end
end
