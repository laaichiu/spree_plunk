module SpreePlunk
  class StoreOwnerNotificationEmailPresenter < OrderTransactionalEmailPresenter
    def call
      resource_type = if resource.is_a?(::Spree::OrderGroup)
        ::Spree::OrderGroup.name
      else
        ::Spree::Order.name
      end

      base_payload(
        to: resolved_email,
        subject: "New order for #{store_name}",
        body: body,
        template_id: plunk_integration.preferred_store_owner_notification_template_id,
        data: order_data(email_type: TransactionalEmailTypes::STORE_OWNER_NOTIFICATION),
        headers: headers(
          email_type: TransactionalEmailTypes::STORE_OWNER_NOTIFICATION,
          resource_type: resource_type,
          resource_id: resource&.id
        )
      )
    end

    private

    def resolved_email
      email.presence || store&.new_order_notifications_email
    end

    def customer_email
      resource&.email.presence || resource&.customer&.email
    end

    def body
      html_document(
        "New order for #{store_name}",
        paragraphs: [
          "A new order #{order_number} has been placed.",
          "Order total: #{display_total}",
          "Customer email: #{customer_email}"
        ],
        action_url: storefront_url,
        action_label: "Visit #{store_name}"
      )
    end
  end
end
