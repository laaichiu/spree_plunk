module SpreePlunk
  class SellerLifecycleEmailPresenter < TransactionalEmailPresenter
    EMAIL_CONFIG = {
      TransactionalEmailTypes::SELLER_APPROVED => {
        subject: 'Your seller account with %{store} is approved',
        message: 'You can now sign in and start selling.',
        action: true,
        template_preference: :preferred_seller_approved_template_id
      },
      TransactionalEmailTypes::SELLER_SUSPENDED => {
        subject: 'Your seller account with %{store} is suspended',
        message: 'Please contact the store team if you have questions.',
        action: false,
        template_preference: :preferred_seller_suspended_template_id
      },
      TransactionalEmailTypes::SELLER_REJECTED => {
        subject: 'Your seller application to %{store} was declined',
        message: 'Please contact the store team if you have questions.',
        action: false,
        template_preference: :preferred_seller_rejected_template_id
      }
    }.freeze

    def call
      email_type = event_value(:email_type).presence || infer_email_type
      config = EMAIL_CONFIG.fetch(email_type)
      dashboard_url = config[:action] ? ::Spree::Stores::DashboardUrl.call(store: store).presence : nil
      seller_data = { name: resource.name, id: resource.prefixed_id }

      base_payload(
        to: email.presence || recipients,
        subject: format(config[:subject], store: store_name),
        body: body(config[:message], dashboard_url),
        template_id: plunk_integration.public_send(config[:template_preference]),
        data: non_persistent_data_hash(
          email_type: email_type,
          seller: seller_data,
          store_name: store_name,
          dashboard_url: dashboard_url,
          store_email: store&.mail_from_address
        ),
        headers: headers(
          email_type: email_type,
          resource_type: ::Spree::Seller.name,
          resource_id: resource.id
        )
      )
    end

    private

    def infer_email_type
      return TransactionalEmailTypes::SELLER_APPROVED if resource.approved?
      return TransactionalEmailTypes::SELLER_SUSPENDED if resource.suspended?

      TransactionalEmailTypes::SELLER_REJECTED
    end

    def recipients
      (resource.users.pluck(:email) << resource.contact_email).compact_blank.uniq { |address| address.downcase }
    end

    def body(message, dashboard_url)
      html_document(
        "Seller update for #{store_name}",
        paragraphs: [message],
        action_url: dashboard_url,
        action_label: 'Open seller dashboard'
      )
    end
  end
end
