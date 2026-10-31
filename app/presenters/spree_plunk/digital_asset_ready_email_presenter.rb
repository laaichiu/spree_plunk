module SpreePlunk
  class DigitalAssetReadyEmailPresenter < OrderTransactionalEmailPresenter
    def call
      resend = event_value(:resend) == true
      downloads = resource.digital_links.includes(digital_asset: { attachment_attachment: :blob }).map do |link|
        {
          filename: link.filename.to_s,
          url: ::Spree::Api::DigitalLinkUrls.download_url(link, store.formatted_url),
          expires_at: link.expires_at&.iso8601
        }
      end

      base_payload(
        to: resolved_email,
        subject: "Your #{store_name} order downloads are ready",
        body: body(downloads),
        template_id: plunk_integration.preferred_digital_asset_ready_template_id,
        data: order_data(email_type: TransactionalEmailTypes::DIGITAL_ASSET_READY).merge(
          non_persistent_data_hash(
            downloads: downloads,
            resend: resend,
            download_count: downloads.size
          )
        ),
        headers: headers(
          email_type: TransactionalEmailTypes::DIGITAL_ASSET_READY,
          resource_type: ::Spree::Order.name,
          resource_id: resource.id
        )
      )
    end

    private

    def body(downloads)
      rows = downloads.map do |download|
        expiry = download[:expires_at].present? ? " (available until #{download[:expires_at]})" : ''
        %(<li><a href="#{h(download[:url])}">#{h(download[:filename])}</a>#{h(expiry)}</li>)
      end.join

      html_document(
        "Your #{store_name} downloads are ready",
        paragraphs: ["Your downloads for order #{order_number} are ready."],
        action_url: nil,
        action_label: nil
      ).sub('</h1>', "</h1><ul>#{rows}</ul>")
    end
  end
end
