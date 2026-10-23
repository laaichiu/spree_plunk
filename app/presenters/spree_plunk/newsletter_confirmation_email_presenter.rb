module SpreePlunk
  class NewsletterConfirmationEmailPresenter < TransactionalEmailPresenter
    def call
      token = event_value(:verification_token).presence || resource&.verification_token
      confirmation_url = append_token(event_value(:redirect_url).presence || storefront_url, token)

      base_payload(
        to: resolved_email,
        subject: "Confirm your #{store_name} newsletter subscription",
        body: body(confirmation_url),
        template_id: plunk_integration.preferred_newsletter_confirmation_template_id,
        data: {
          email_type: TransactionalEmailTypes::NEWSLETTER_CONFIRMATION,
          store_name: store_name,
          recipient_email: resolved_email,
          subscriber_id: subscriber_id,
          verification_token: token,
          verification_url: confirmation_url,
          confirmation_url: confirmation_url
        },
        headers: headers(
          email_type: TransactionalEmailTypes::NEWSLETTER_CONFIRMATION,
          resource_type: ::Spree::NewsletterSubscriber.name,
          resource_id: resource&.id
        )
      )
    end

    private

    def resolved_email
      email.presence || event_value(:email) || resource&.email
    end

    def subscriber_id
      resource&.prefixed_id || event_value(:id)
    end

    def body(confirmation_url)
      html_document(
        "Confirm your #{store_name} newsletter subscription",
        paragraphs: [
          "Please confirm that you want to receive emails from #{store_name}.",
          'You will not be subscribed until this confirmation is complete.'
        ],
        action_url: confirmation_url,
        action_label: 'Confirm subscription'
      )
    end
  end
end
