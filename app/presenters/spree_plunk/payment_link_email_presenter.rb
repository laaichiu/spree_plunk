require 'uri'

module SpreePlunk
  class PaymentLinkEmailPresenter < OrderTransactionalEmailPresenter
    def call
      payment_url = URI.join("#{storefront_url.to_s.chomp('/')}/", "/checkout/#{resource.token}/payment").to_s

      base_payload(
        to: resolved_email,
        subject: "Payment link for order ##{order_number}",
        body: body(payment_url),
        template_id: plunk_integration.preferred_payment_link_template_id,
        data: order_data(email_type: TransactionalEmailTypes::PAYMENT_LINK).merge(
          non_persistent_data_hash(payment_url: payment_url)
        ),
        headers: headers(
          email_type: TransactionalEmailTypes::PAYMENT_LINK,
          resource_type: ::Spree::Order.name,
          resource_id: resource.id
        )
      )
    end

    private

    def body(payment_url)
      html_document(
        "Payment link for order ##{order_number}",
        paragraphs: ["Complete payment for your #{store_name} order."],
        action_url: payment_url,
        action_label: 'Pay for order'
      )
    end
  end
end
