module SpreePlunk
  class CompanyInvitationEmailPresenter < TransactionalEmailPresenter
    def call
      company = resource.company
      accept_url = append_token("#{storefront_url.to_s.chomp('/')}/account/company-invitation", resource.token)

      base_payload(
        to: email.presence || resource.email,
        subject: "You're invited to join #{company.name}",
        body: body(company.name, accept_url),
        template_id: plunk_integration.preferred_company_invitation_template_id,
        data: non_persistent_data_hash(
          email_type: TransactionalEmailTypes::COMPANY_INVITATION,
          store_name: store_name,
          company: { name: company.name },
          accept_url: accept_url,
          invitation_expires_at: resource.expires_at&.iso8601
        ),
        headers: headers(
          email_type: TransactionalEmailTypes::COMPANY_INVITATION,
          resource_type: ::Spree::CompanyInvitation.name,
          resource_id: resource.id
        )
      )
    end

    private

    def body(company_name, accept_url)
      html_document(
        "You're invited to join #{company_name}",
        paragraphs: ["You've been invited to join #{company_name} at #{store_name}.", 'This invitation expires. If you were not expecting it, you can ignore this email.'],
        action_url: accept_url,
        action_label: 'Accept invitation'
      )
    end
  end
end
