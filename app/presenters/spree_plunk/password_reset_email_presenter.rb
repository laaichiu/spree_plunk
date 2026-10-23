module SpreePlunk
  class PasswordResetEmailPresenter < TransactionalEmailPresenter
    def call
      reset_token = event_value(:reset_token)
      reset_url = append_token(event_value(:redirect_url).presence || storefront_url, reset_token)

      base_payload(
        to: resolved_email,
        subject: "Reset your #{store_name} password",
        body: body(reset_url),
        template_id: plunk_integration.preferred_password_reset_template_id,
        data: {
          email_type: TransactionalEmailTypes::PASSWORD_RESET,
          store_name: store_name,
          recipient_email: resolved_email,
          reset_token: reset_token,
          reset_url: reset_url
        },
        headers: headers(
          email_type: TransactionalEmailTypes::PASSWORD_RESET,
          resource_type: ::Spree.customer_class.name,
          resource_id: nil
        )
      )
    end

    private

    def resolved_email
      email.presence || event_value(:email)
    end

    def body(reset_url)
      html_document(
        "Reset your #{store_name} password",
        paragraphs: [
          "We received a request to reset the password for your #{store_name} account.",
          'You can ignore this email if you did not request a password reset.'
        ],
        action_url: reset_url,
        action_label: 'Reset password'
      )
    end
  end
end
