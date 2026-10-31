module SpreePlunk
  class DataExportReadyEmailPresenter < TransactionalEmailPresenter
    def call
      download_url = ::Spree::Api::DataRequestUrls.download_url(resource, store.formatted_url)

      base_payload(
        to: email.presence || resource.email,
        subject: "Your #{store_name} data export is ready",
        body: body(download_url),
        template_id: plunk_integration.preferred_data_export_ready_template_id,
        data: non_persistent_data_hash(
          email_type: TransactionalEmailTypes::DATA_EXPORT_READY,
          store_name: store_name,
          download_url: download_url,
          expires_at: resource.expires_at&.iso8601
        ),
        headers: headers(
          email_type: TransactionalEmailTypes::DATA_EXPORT_READY,
          resource_type: ::Spree::DataRequest.name,
          resource_id: resource.id
        )
      )
    end

    private

    def body(download_url)
      html_document(
        "Your #{store_name} data export is ready",
        paragraphs: ['You can download a copy of the personal data associated with your account. The link expires.'],
        action_url: download_url,
        action_label: 'Download your data'
      )
    end
  end
end
