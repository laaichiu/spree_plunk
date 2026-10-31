module SpreePlunk
  class SendTransactionalEmail < Base
    prepend ::Spree::ServiceModule::Base

    TYPE_CONFIG = {
      TransactionalEmailTypes::PASSWORD_RESET => {
        enabled_preference: :preferred_password_reset_email_enabled,
        presenter: SpreePlunk::PasswordResetEmailPresenter,
        template_key: 'spree/customer_mailer/password_reset_email'
      },
      TransactionalEmailTypes::NEWSLETTER_CONFIRMATION => {
        enabled_preference: :preferred_newsletter_confirmation_email_enabled,
        presenter: SpreePlunk::NewsletterConfirmationEmailPresenter,
        template_key: 'spree/newsletter_mailer/email_confirmation'
      },
      TransactionalEmailTypes::ORDER_CONFIRMATION => {
        enabled_preference: :preferred_order_confirmation_email_enabled,
        presenter: SpreePlunk::OrderConfirmationEmailPresenter,
        template_key: 'spree/order_mailer/confirm_email'
      },
      TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND => {
        enabled_preference: :preferred_order_confirmation_resend_email_enabled,
        presenter: SpreePlunk::OrderConfirmationResendEmailPresenter,
        template_key: 'spree/order_mailer/confirm_email'
      },
      TransactionalEmailTypes::ORDER_CANCELLATION => {
        enabled_preference: :preferred_order_cancellation_email_enabled,
        presenter: SpreePlunk::OrderCancellationEmailPresenter,
        template_key: 'spree/order_mailer/cancel_email'
      },
      TransactionalEmailTypes::FULFILLMENT_FULFILLED => {
        enabled_preference: :preferred_fulfillment_fulfilled_email_enabled,
        presenter: SpreePlunk::FulfillmentFulfilledEmailPresenter,
        template_key: 'spree/fulfillment_mailer/fulfilled_email'
      },
      TransactionalEmailTypes::RETURN_REFUNDED => {
        enabled_preference: :preferred_return_refunded_email_enabled,
        presenter: SpreePlunk::ReturnRefundedEmailPresenter,
        template_key: 'spree/return_mailer/refunded_email'
      },
      TransactionalEmailTypes::DIGITAL_ASSET_READY => {
        enabled_preference: :preferred_digital_asset_ready_email_enabled,
        presenter: SpreePlunk::DigitalAssetReadyEmailPresenter,
        template_key: 'spree/digital_asset_mailer/files_ready_email'
      },
      TransactionalEmailTypes::COMPANY_INVITATION => {
        enabled_preference: :preferred_company_invitation_email_enabled,
        presenter: SpreePlunk::CompanyInvitationEmailPresenter,
        template_key: 'spree/company_mailer/invitation_email'
      },
      TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION => {
        enabled_preference: :preferred_data_request_confirmation_email_enabled,
        presenter: SpreePlunk::DataRequestConfirmationEmailPresenter,
        template_key: 'spree/customer_mailer/data_request_confirmation_email'
      },
      TransactionalEmailTypes::DATA_EXPORT_READY => {
        enabled_preference: :preferred_data_export_ready_email_enabled,
        presenter: SpreePlunk::DataExportReadyEmailPresenter,
        template_key: 'spree/customer_mailer/data_export_email'
      },
      TransactionalEmailTypes::PAYMENT_LINK => {
        enabled_preference: :preferred_payment_link_email_enabled,
        presenter: SpreePlunk::PaymentLinkEmailPresenter,
        template_key: 'spree/order_mailer/payment_link_email'
      },
      TransactionalEmailTypes::SELLER_APPROVED => {
        enabled_preference: :preferred_seller_approved_email_enabled,
        presenter: SpreePlunk::SellerLifecycleEmailPresenter
      },
      TransactionalEmailTypes::SELLER_SUSPENDED => {
        enabled_preference: :preferred_seller_suspended_email_enabled,
        presenter: SpreePlunk::SellerLifecycleEmailPresenter
      },
      TransactionalEmailTypes::SELLER_REJECTED => {
        enabled_preference: :preferred_seller_rejected_email_enabled,
        presenter: SpreePlunk::SellerLifecycleEmailPresenter
      },
      TransactionalEmailTypes::STORE_OWNER_NOTIFICATION => {
        enabled_preference: :preferred_store_owner_notification_email_enabled,
        presenter: SpreePlunk::StoreOwnerNotificationEmailPresenter
      }
    }.freeze

    def call(plunk_integration:, email_type:, resource: nil, email: nil, event_payload: nil, idempotency_key: nil)
      event_payload = normalized_event_payload(event_payload)
      store = plunk_integration.store || resource_store(resource) || ::Spree::Store.default
      locale = event_value(event_payload, :locale).presence || resource_locale(resource) || store&.default_locale

      with_store_locale(store, locale) do
        perform_send(
          plunk_integration: plunk_integration,
          email_type: email_type,
          resource: resource,
          email: email,
          event_payload: event_payload,
          idempotency_key: idempotency_key
        )
      end
    end

    private

    def perform_send(plunk_integration:, email_type:, resource:, email:, event_payload:, idempotency_key:)
      return noop_result('integration_inactive') unless plunk_integration.active?

      config = TYPE_CONFIG[email_type.to_s]
      return failure_result('unknown_email_type', "Unknown Plunk transactional email type: #{email_type.inspect}") unless config
      return noop_result('transactional_email_disabled') unless plunk_integration.preferred_transactional_email_enabled
      return noop_result("#{email_type}_disabled") unless plunk_integration.public_send(config[:enabled_preference])
      unless transactional_emails_enabled?(plunk_integration, resource, email_type)
        reason = seller_email_type?(email_type) ? 'seller_transactional_emails_disabled' : 'consumer_transactional_emails_disabled'
        return noop_result(reason)
      end

      context_result = validate_context(email_type.to_s, resource, event_payload)
      return context_result if context_result

      payload = presenter_for(config, email_type.to_s, resource).new(
        **presenter_arguments(config, email_type.to_s, plunk_integration, resource, email, event_payload)
      ).call

      payload = apply_dashboard_template(
        payload,
        template_key: dashboard_template_key(email_type.to_s, resource, config),
        email_type: email_type,
        plunk_integration: plunk_integration,
        resource: resource,
        event_payload: event_payload
      )
      return payload if payload.is_a?(::Spree::ServiceModule::Result)

      validation_result = validate_payload(payload)
      return validation_result if validation_result.failure?

      result = plunk_integration.send_transactional_email(payload, idempotency_key: idempotency_key)
      mark_order_confirmation_delivered(resource, email_type) if result.success?
      mark_store_owner_notification_delivered(resource, email_type) if result.success?
      result
    end

    def seller_email_type?(email_type)
      [
        TransactionalEmailTypes::SELLER_APPROVED,
        TransactionalEmailTypes::SELLER_SUSPENDED,
        TransactionalEmailTypes::SELLER_REJECTED
      ].include?(email_type.to_s)
    end

    def transactional_emails_enabled?(plunk_integration, resource, email_type)
      return true if email_type.to_s == TransactionalEmailTypes::STORE_OWNER_NOTIFICATION

      store = plunk_integration.store || resource_store(resource) || ::Spree::Store.default
      return store&.prefers_send_seller_transactional_emails? if seller_email_type?(email_type)

      store&.prefers_send_consumer_transactional_emails?
    end

    def order_group_resource?(resource)
      resource.is_a?(::Spree::OrderGroup)
    end

    def presenter_for(config, email_type, resource)
      if order_group_resource?(resource) && [
        TransactionalEmailTypes::ORDER_CONFIRMATION,
        TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND
      ].include?(email_type)
        SpreePlunk::OrderGroupConfirmationEmailPresenter
      else
        config[:presenter]
      end
    end

    def presenter_arguments(config, email_type, plunk_integration, resource, email, event_payload)
      arguments = {
        plunk_integration: plunk_integration,
        resource: resource,
        email: email,
        event_payload: event_payload
      }
      if presenter_for(config, email_type, resource) == SpreePlunk::OrderGroupConfirmationEmailPresenter
        arguments[:email_type] = email_type
      end
      arguments
    end

    def dashboard_template_key(email_type, resource, config)
      if order_group_resource?(resource) && [
        TransactionalEmailTypes::ORDER_CONFIRMATION,
        TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND
      ].include?(email_type)
        'spree/order_group_mailer/confirm_email'
      else
        config[:template_key]
      end
    end

    def normalized_event_payload(event_payload)
      return {} if event_payload.blank?

      event_payload.respond_to?(:to_unsafe_h) ? event_payload.to_unsafe_h : event_payload
    end

    def validate_context(email_type, resource, event_payload)
      case email_type
      when TransactionalEmailTypes::PASSWORD_RESET
        return failure_result('missing_reset_token', 'Password reset emails require a reset token.') if event_value(event_payload, :reset_token).blank?
      when TransactionalEmailTypes::NEWSLETTER_CONFIRMATION
        return noop_result('missing_newsletter_subscriber') unless resource
        return noop_result('newsletter_already_verified') if resource.verified?

        token = event_value(event_payload, :verification_token).presence || resource&.verification_token
        return failure_result('missing_verification_token', 'Newsletter confirmation emails require a verification token.') if token.blank?
      when TransactionalEmailTypes::ORDER_CONFIRMATION
        return noop_result('missing_order') unless resource
        return noop_result('order_confirmation_already_delivered') if resource.confirmation_delivered?
        return noop_result('notify_customer_disabled') if event_value(event_payload, :notify_customer) == false
      when TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND
        return noop_result('missing_order') unless resource
      when TransactionalEmailTypes::ORDER_CANCELLATION
        return noop_result('missing_order') unless resource
        return noop_result('notify_customer_disabled') if event_value(event_payload, :notify_customer) == false
      when TransactionalEmailTypes::FULFILLMENT_FULFILLED
        return noop_result('missing_fulfillment') unless resource
      when TransactionalEmailTypes::RETURN_REFUNDED
        return noop_result('missing_return') unless resource
      when TransactionalEmailTypes::DIGITAL_ASSET_READY
        return noop_result('missing_order') unless resource.is_a?(::Spree::Order)
        return noop_result('digital_links_missing') if resource.digital_links.empty?
        return failure_result('missing_download_host', 'Digital download emails require the store formatted URL.') if resource.store&.formatted_url.blank?
      when TransactionalEmailTypes::COMPANY_INVITATION
        return noop_result('missing_company_invitation') unless resource.is_a?(::Spree::CompanyInvitation)
        return noop_result('company_invitation_not_pending') unless resource.pending?
        return failure_result('missing_invitation_token', 'Company invitation emails require an invitation token.') if resource.token.blank?
        return failure_result('missing_storefront_url', 'Company invitation emails require a store storefront URL.') if resource.store&.storefront_url.blank?
      when TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION
        return noop_result('missing_data_request') unless resource.is_a?(::Spree::DataRequest)
        return noop_result('data_request_not_confirmable') unless resource.confirmable?
        return failure_result('missing_confirmation_token', 'Data-request confirmation emails require a confirmation token.') if event_value(event_payload, :confirmation_token).blank?
        return failure_result('missing_confirmation_url', 'Data-request confirmation emails require a store storefront URL or approved redirect URL.') if event_value(event_payload, :redirect_url).blank? && resource.store&.storefront_url.blank?
      when TransactionalEmailTypes::DATA_EXPORT_READY
        return noop_result('missing_data_request') unless resource.is_a?(::Spree::DataRequest)
        return noop_result('data_export_not_available') unless resource.access? && resource.downloadable?
        return failure_result('missing_download_host', 'Data export emails require the store formatted URL.') if resource.store&.formatted_url.blank?
      when TransactionalEmailTypes::PAYMENT_LINK
        return noop_result('missing_order') unless resource.is_a?(::Spree::Order)
        return noop_result('order_not_payable') unless resource.completed_at.nil? && !resource.canceled?
        return failure_result('missing_order_token', 'Payment-link emails require the order token.') if resource.token.blank?
        return failure_result('missing_storefront_url', 'Payment-link emails require a store storefront URL.') if resource.store&.storefront_url.blank?
      when TransactionalEmailTypes::SELLER_APPROVED,
           TransactionalEmailTypes::SELLER_SUSPENDED,
           TransactionalEmailTypes::SELLER_REJECTED
        return noop_result('missing_seller') unless resource.is_a?(::Spree::Seller)
      when TransactionalEmailTypes::STORE_OWNER_NOTIFICATION
        return noop_result('missing_order') unless resource
        return noop_result('store_owner_notification_already_delivered') if resource.store_owner_notification_delivered?
        return noop_result('missing_store_owner_notification_email') if resource.store&.new_order_notifications_email.blank?
      end

      nil
    end

    def event_value(event_payload, key)
      return event_payload[key.to_s] if event_payload.key?(key.to_s)
      return event_payload[key.to_sym] if event_payload.key?(key.to_sym)

      nil
    end

    # Published Spree overrides take precedence for this store and locale. The
    # original Plunk template remains the fallback until a merchant publishes
    # a dashboard edit, so merely installing the integration changes no sends.
    def apply_dashboard_template(payload, template_key:, email_type:, plunk_integration:, resource:, event_payload:)
      return payload if template_key.blank?

      store = plunk_integration.store || resource_store(resource) || ::Spree::Store.default
      return payload unless store

      locale = event_value(event_payload, :locale).presence || resource_locale(resource) || store.default_locale
      locale = locale.to_s.presence || store.default_locale.to_s
      any_locale = ::Spree::EmailTemplate::ANY_LOCALE
      published = store.email_templates.published.where(key: template_key, locale: [locale, any_locale]).exists?
      return payload unless published

      resolver = ::Spree::Emails::TemplateResolver.for_mailers(store: store, locale: locale)
      template = resolver.find(template_key)
      return payload unless template

      currency = resource_currency(resource).presence || store.default_currency
      assignments = SpreePlunk::EmailTemplateAssignments.call(email_type: email_type, payload: payload, resource: resource)
      rendered = ::Spree::Emails::Renderer.new(resolver: resolver, store: store, currency: currency).render(template, assignments)

      payload.except(:template, :data).merge(
        subject: rendered.subject.presence || payload[:subject],
        body: rendered.html.to_s
      )
    rescue StandardError => error
      Rails.error.report(error, context: { email_template: template_key, store_id: store&.id })
      failure_result('email_template_render_failed', "Published Spree email template #{template_key.inspect} could not be rendered: #{error.message}")
    end

    def resource_locale(resource)
      case resource
      when ::Spree::Order, ::Spree::OrderGroup
        resource.locale
      when ::Spree::Fulfillment
        resource.owner&.locale
      when ::Spree::Return
        resource.order.locale
      when ::Spree::CompanyInvitation, ::Spree::DataRequest, ::Spree::Seller
        resource.store&.default_locale
      end
    end

    def resource_store(resource)
      resource.store if resource&.respond_to?(:store)
    rescue ActiveModel::MissingAttributeError
      nil
    end

    def with_store_locale(store, locale)
      locale = locale.presence || store&.default_locale
      return yield if locale.blank?

      previous_fallbacks = Mobility.store_based_fallbacks
      begin
        ::Spree::Locales::SetFallbackLocaleForStore.new.call(store: store) if store
        I18n.with_locale(locale) { yield }
      ensure
        Mobility.store_based_fallbacks = previous_fallbacks
      end
    end

    def resource_currency(resource)
      case resource
      when ::Spree::Order, ::Spree::OrderGroup, ::Spree::Fulfillment, ::Spree::Return
        resource.currency
      end
    end

    def validate_payload(payload)
      return failure_result('missing_payload', 'No Plunk transactional email payload was built.') unless payload.is_a?(Hash)
      return noop_result('missing_recipient') if payload[:to].blank?

      if payload[:template].blank?
        return failure_result('missing_sender', 'A sender is required when sending a Plunk transactional email without a template.') if payload[:from].blank?
        return failure_result('missing_subject', 'A subject is required when sending a Plunk transactional email without a template.') if payload[:subject].blank?
        return failure_result('missing_body', 'A body is required when sending a Plunk transactional email without a template.') if payload[:body].blank?
      end

      ::Spree::ServiceModule::Result.new(true, {})
    end

    def failure_result(reason, error_message, retryable: false)
      ::Spree::ServiceModule::Result.new(false, {
        error: reason,
        error_code: reason,
        error_message: error_message,
        retryable: retryable
      })
    end

    def mark_order_confirmation_delivered(resource, email_type)
      return unless [
        TransactionalEmailTypes::ORDER_CONFIRMATION,
        TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND
      ].include?(email_type.to_s)
      return if resource.confirmation_delivered?

      resource.update_column(:confirmation_delivered, true)
    end

    def mark_store_owner_notification_delivered(resource, email_type)
      return unless email_type.to_s == TransactionalEmailTypes::STORE_OWNER_NOTIFICATION
      return if resource.store_owner_notification_delivered?

      resource.update_column(:store_owner_notification_delivered, true)
    end
  end
end
