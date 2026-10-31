module SpreePlunk
  class DataRequestConfirmationEmailPresenter < TransactionalEmailPresenter
    def call
      confirmation_url = append_token(
        event_value(:redirect_url).presence || storefront_url,
        event_value(:confirmation_token)
      )
      expires_at = resource.requested_at + ::Spree::DataRequest::CONFIRMATION_WINDOW

      base_payload(
        to: email.presence || resource.email,
        subject: "Confirm your #{store_name} data request",
        body: body(confirmation_url),
        template_id: plunk_integration.preferred_data_request_confirmation_template_id,
        data: non_persistent_data_hash(
          email_type: TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION,
          store_name: store_name,
          kind: resource.kind,
          confirmation_url: confirmation_url,
          expires_at: expires_at.iso8601
        ),
        headers: headers(
          email_type: TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION,
          resource_type: ::Spree::DataRequest.name,
          resource_id: resource.id
        )
      )
    end

    private

    def body(confirmation_url)
      request_name = resource.kind.to_s == 'erasure' ? 'account deletion' : 'data access'
      html_document(
        "Confirm your #{store_name} data request",
        paragraphs: ["Please confirm your #{request_name} request.", 'If you did not make this request, you can ignore this email.'],
        action_url: confirmation_url,
        action_label: 'Confirm request'
      )
    end
  end
end
