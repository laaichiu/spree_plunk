module SpreePlunk
  class TransactionalEmailSubscriber < Spree::Subscriber
    subscribes_to 'customer.password_reset_requested',
                  'newsletter_subscriber.subscription_requested',
                  'order.placed',
                  'order.canceled',
                  'order.resend_confirmation_email',
                  'order_group.completed',
                  'order_group.resend_confirmation_email',
                  'fulfillment.fulfilled',
                  'return.refunded',
                  'order.resend_digital_links_email',
                  'company_invitation.created',
                  'data_request.confirmation_requested',
                  'data_request.completed',
                  'seller.approved',
                  'seller.suspended',
                  'seller.rejected',
                  async: false

    on 'customer.password_reset_requested', :handle_password_reset_requested
    on 'newsletter_subscriber.subscription_requested', :handle_newsletter_subscription_requested
    on 'order.placed', :handle_order_completed
    on 'order.canceled', :handle_order_canceled
    on 'order.resend_confirmation_email', :handle_order_confirmation_resend
    on 'order_group.completed', :handle_order_group_completed
    on 'order_group.resend_confirmation_email', :handle_order_group_confirmation_resend
    on 'fulfillment.fulfilled', :handle_fulfillment_fulfilled
    on 'return.refunded', :handle_return_refunded
    on 'order.resend_digital_links_email', :handle_digital_links_resend
    on 'company_invitation.created', :handle_company_invitation_created
    on 'data_request.confirmation_requested', :handle_data_request_confirmation
    on 'data_request.completed', :handle_data_request_completed
    on 'seller.approved', :handle_seller_approved
    on 'seller.suspended', :handle_seller_suspended
    on 'seller.rejected', :handle_seller_rejected

    private

    def handle_password_reset_requested(event)
      email = event.payload['email']
      return if email.blank? || event.payload['reset_token'].blank?

      integration = plunk_integration(event)
      return unless enabled_for?(integration, TransactionalEmailTypes::PASSWORD_RESET)

      SpreePlunk::SendTransactionalEmailJob.perform_later(
        integration.id,
        TransactionalEmailTypes::PASSWORD_RESET,
        nil,
        nil,
        email,
        event.payload
      )
    end

    def handle_newsletter_subscription_requested(event)
      subscriber = find_newsletter_subscriber(event.payload['id'], event)
      return unless subscriber
      return if subscriber.verified?

      integration = plunk_integration(event, store: resource_store(subscriber), store_id: event.payload['store_id'])
      return unless enabled_for?(integration, TransactionalEmailTypes::NEWSLETTER_CONFIRMATION)

      SpreePlunk::SendTransactionalEmailJob.perform_later(
        integration.id,
        TransactionalEmailTypes::NEWSLETTER_CONFIRMATION,
        ::Spree::NewsletterSubscriber.name,
        subscriber.id,
        subscriber.email,
        event.payload
      )
    end

    def handle_order_completed(event)
      order = find_order(event.payload['id'])
      return unless order

      if event_value(event.metadata, :notify_customer) != false &&
          !order.confirmation_delivered?
        enqueue_order_completed_confirmation(event, order)
      end
      enqueue_store_owner_notification(event, order)
      enqueue_digital_asset_email(event, order, resend: false)
    end

    def handle_digital_links_resend(event)
      order = find_order(event.payload['id'])
      return unless order

      enqueue_digital_asset_email(event, order, resend: true)
    end

    def enqueue_digital_asset_email(event, order, resend:)
      return if order.digital_links.empty?

      enqueue_email(
        event,
        TransactionalEmailTypes::DIGITAL_ASSET_READY,
        ::Spree::Order.name,
        order.id,
        order.email,
        event.payload.merge('resend' => resend),
        store: order.store
      )
    end

    def handle_company_invitation_created(event)
      invitation = find_by_prefix_id(::Spree::CompanyInvitation, event.payload['id'])
      return unless invitation&.pending?

      enqueue_email(
        event,
        TransactionalEmailTypes::COMPANY_INVITATION,
        ::Spree::CompanyInvitation.name,
        invitation.id,
        invitation.email,
        event.payload,
        store: invitation.store
      )
    end

    def handle_data_request_confirmation(event)
      request = find_by_prefix_id(::Spree::DataRequest, event.payload['id'])
      return unless request&.confirmable?
      return if event_value(event.payload, :confirmation_token).blank?

      enqueue_email(
        event,
        TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION,
        ::Spree::DataRequest.name,
        request.id,
        request.email,
        event.payload,
        store: request.store
      )
    end

    def handle_data_request_completed(event)
      request = find_by_prefix_id(::Spree::DataRequest, event.payload['id'])
      return unless request&.access? && request.downloadable?

      enqueue_email(
        event,
        TransactionalEmailTypes::DATA_EXPORT_READY,
        ::Spree::DataRequest.name,
        request.id,
        request.email,
        event.payload,
        store: request.store
      )
    end

    def handle_seller_approved(event)
      enqueue_seller_email(event, TransactionalEmailTypes::SELLER_APPROVED)
    end

    def handle_seller_suspended(event)
      enqueue_seller_email(event, TransactionalEmailTypes::SELLER_SUSPENDED)
    end

    def handle_seller_rejected(event)
      enqueue_seller_email(event, TransactionalEmailTypes::SELLER_REJECTED)
    end

    def enqueue_seller_email(event, email_type)
      seller = find_by_prefix_id(::Spree::Seller, event.payload['id'])
      return unless seller

      recipients = seller.users.pluck(:email) << seller.contact_email
      return if recipients.compact_blank.empty?

      enqueue_email(
        event,
        email_type,
        ::Spree::Seller.name,
        seller.id,
        nil,
        event.payload.merge('email_type' => email_type),
        store: seller.store
      )
    end

    def enqueue_email(event, email_type, resource_type, resource_id, email, event_payload, store: nil)
      integration = plunk_integration(event, store: store)
      return unless enabled_for?(integration, email_type)

      SpreePlunk::SendTransactionalEmailJob.perform_later(
        integration.id,
        email_type,
        resource_type,
        resource_id,
        email,
        event_payload
      )
    end

    def enqueue_order_completed_confirmation(event, order)
      return if order.grouped?

      integration = plunk_integration(event, store: order.store)
      return unless enabled_for?(integration, TransactionalEmailTypes::ORDER_CONFIRMATION)

      SpreePlunk::SendTransactionalEmailJob.perform_later(
        integration.id,
        TransactionalEmailTypes::ORDER_CONFIRMATION,
        ::Spree::Order.name,
        order.id,
        order.email,
        event.payload
      )
    end

    def enqueue_store_owner_notification(event, resource)
      return if resource.is_a?(::Spree::Order) && resource.grouped?
      return if resource.store_owner_notification_delivered?
      return if resource.store&.new_order_notifications_email.blank?

      integration = plunk_integration(event, store: resource.store)
      return unless enabled_for?(integration, TransactionalEmailTypes::STORE_OWNER_NOTIFICATION)

      SpreePlunk::SendTransactionalEmailJob.perform_later(
        integration.id,
        TransactionalEmailTypes::STORE_OWNER_NOTIFICATION,
        resource.class.name,
        resource.id,
        resource.store.new_order_notifications_email,
        event.payload
      )
    end

    def handle_order_canceled(event)
      order = find_order(event.payload['id'])
      return unless order
      return if event_value(event.metadata, :notify_customer) == false

      integration = plunk_integration(event, store: order.store)
      return unless enabled_for?(integration, TransactionalEmailTypes::ORDER_CANCELLATION)

      SpreePlunk::SendTransactionalEmailJob.perform_later(
        integration.id,
        TransactionalEmailTypes::ORDER_CANCELLATION,
        ::Spree::Order.name,
        order.id,
        order.email,
        event.payload
      )
    end

    def handle_order_confirmation_resend(event)
      order = find_order(event.payload['id'])
      return unless order

      if order.grouped?
        return unless order.order_group

        enqueue_order_group_confirmation(event, order.order_group, TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND)
        return
      end

      integration = plunk_integration(event, store: order.store)
      return unless enabled_for?(integration, TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND)

      SpreePlunk::SendTransactionalEmailJob.perform_later(
        integration.id,
        TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND,
        ::Spree::Order.name,
        order.id,
        order.email,
        event.payload
      )
    end

    def handle_order_group_completed(event)
      order_group = find_order_group(event.payload['id'])
      return unless order_group

      if event_value(event.metadata, :notify_customer) != false &&
          !order_group.confirmation_delivered?
        enqueue_order_group_confirmation(event, order_group, TransactionalEmailTypes::ORDER_CONFIRMATION)
      end
      enqueue_store_owner_notification(event, order_group)
    end

    def handle_order_group_confirmation_resend(event)
      order_group = find_order_group(event.payload['id'])
      return unless order_group

      enqueue_order_group_confirmation(event, order_group, TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND)
    end

    def enqueue_order_group_confirmation(event, order_group, email_type)
      integration = plunk_integration(event, store: order_group.store)
      return unless enabled_for?(integration, email_type)

      SpreePlunk::SendTransactionalEmailJob.perform_later(
        integration.id,
        email_type,
        ::Spree::OrderGroup.name,
        order_group.id,
        order_group.email,
        event.payload
      )
    end

    def handle_fulfillment_fulfilled(event)
      return if event_value(event.metadata, :notify_customer) == false

      fulfillment = find_fulfillment(event.payload['id'])
      order = fulfillment&.owner
      return unless fulfillment && order

      integration = plunk_integration(event, store: order.store)
      return unless enabled_for?(integration, TransactionalEmailTypes::FULFILLMENT_FULFILLED)

      SpreePlunk::SendTransactionalEmailJob.perform_later(
        integration.id,
        TransactionalEmailTypes::FULFILLMENT_FULFILLED,
        ::Spree::Fulfillment.name,
        fulfillment.id,
        order.email,
        event.payload
      )
    end

    def handle_return_refunded(event)
      return_record = find_return(event.payload['id'])
      order = return_record&.order
      return unless return_record && order
      return if return_record.refunded_total.zero?

      integration = plunk_integration(event, store: order.store)
      return unless enabled_for?(integration, TransactionalEmailTypes::RETURN_REFUNDED)

      SpreePlunk::SendTransactionalEmailJob.perform_later(
        integration.id,
        TransactionalEmailTypes::RETURN_REFUNDED,
        ::Spree::Return.name,
        return_record.id,
        order.email,
        event.payload
      )
    end

    def find_newsletter_subscriber(value, event)
      return if value.blank?

      scope = ::Spree::NewsletterSubscriber.all
      store = event_store(event)
      scope = scope.for_store(store) if store
      scope.find_by_param(value)
    end

    def find_order(value)
      return if value.blank?

      ::Spree::Order.find_by_param(value)
    end

    def find_order_group(value)
      return if value.blank?

      ::Spree::OrderGroup.find_by_param(value)
    end

    def find_fulfillment(value)
      return if value.blank?

      ::Spree::Fulfillment.find_by_param(value)
    end

    def find_return(value)
      return if value.blank?

      ::Spree::Return.find_by_param(value)
    end

    def find_by_prefix_id(klass, value)
      return if value.blank?

      klass.find_by_prefix_id(value)
    end

    def plunk_integration(event, store: nil, store_id: nil)
      candidate_store_id = store&.id || resolve_store_id(store_id) || event_store(event)&.id
      return ::Spree::Integrations::Plunk.active.find_by(store_id: candidate_store_id) if candidate_store_id.present?

      default_store = ::Spree::Store.default
      ::Spree::Integrations::Plunk.active.find_by(store_id: default_store.id) if default_store
    end

    def event_store(event)
      ::Spree::Store.find_by_param(event.payload['store_id']) ||
        ::Spree::Store.find_by(id: event.store_id)
    end

    def resolve_store_id(value)
      return if value.blank?

      store = ::Spree::Store.find_by_param(value)

      store&.id
    end

    def resource_store(resource)
      resource.store if resource.respond_to?(:store)
    rescue ActiveModel::MissingAttributeError
      nil
    end

    def enabled_for?(integration, email_type)
      return false unless integration&.preferred_transactional_email_enabled

      case email_type
      when TransactionalEmailTypes::PASSWORD_RESET
        integration.preferred_password_reset_email_enabled
      when TransactionalEmailTypes::NEWSLETTER_CONFIRMATION
        integration.preferred_newsletter_confirmation_email_enabled
      when TransactionalEmailTypes::ORDER_CONFIRMATION
        integration.preferred_order_confirmation_email_enabled
      when TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND
        integration.preferred_order_confirmation_resend_email_enabled
      when TransactionalEmailTypes::ORDER_CANCELLATION
        integration.preferred_order_cancellation_email_enabled
      when TransactionalEmailTypes::FULFILLMENT_FULFILLED
        integration.preferred_fulfillment_fulfilled_email_enabled
      when TransactionalEmailTypes::RETURN_REFUNDED
        integration.preferred_return_refunded_email_enabled
      when TransactionalEmailTypes::DIGITAL_ASSET_READY
        integration.preferred_digital_asset_ready_email_enabled
      when TransactionalEmailTypes::COMPANY_INVITATION
        integration.preferred_company_invitation_email_enabled
      when TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION
        integration.preferred_data_request_confirmation_email_enabled
      when TransactionalEmailTypes::DATA_EXPORT_READY
        integration.preferred_data_export_ready_email_enabled
      when TransactionalEmailTypes::PAYMENT_LINK
        integration.preferred_payment_link_email_enabled
      when TransactionalEmailTypes::SELLER_APPROVED
        integration.preferred_seller_approved_email_enabled
      when TransactionalEmailTypes::SELLER_SUSPENDED
        integration.preferred_seller_suspended_email_enabled
      when TransactionalEmailTypes::SELLER_REJECTED
        integration.preferred_seller_rejected_email_enabled
      when TransactionalEmailTypes::STORE_OWNER_NOTIFICATION
        integration.preferred_store_owner_notification_email_enabled
      else
        false
      end
    end

    def event_value(payload, key)
      return if payload.blank?

      return payload[key.to_s] if payload.key?(key.to_s)
      return payload[key.to_sym] if payload.key?(key.to_sym)

      nil
    end
  end
end
