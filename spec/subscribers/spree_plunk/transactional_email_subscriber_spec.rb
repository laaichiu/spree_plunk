require 'spec_helper'

RSpec.describe SpreePlunk::TransactionalEmailSubscriber do
  include ActiveJob::TestHelper

  let(:store) { create(:store) }
  let(:integration) do
    create(
      :plunk_integration,
      store: store,
      preferred_transactional_email_enabled: transactional_enabled,
      preferred_password_reset_email_enabled: password_reset_enabled,
      preferred_newsletter_confirmation_email_enabled: newsletter_confirmation_enabled,
      preferred_order_confirmation_email_enabled: order_confirmation_enabled,
      preferred_order_confirmation_resend_email_enabled: order_confirmation_resend_enabled,
      preferred_order_cancellation_email_enabled: order_cancellation_enabled,
      preferred_fulfillment_fulfilled_email_enabled: fulfillment_fulfilled_enabled,
      preferred_return_refunded_email_enabled: return_enabled,
      preferred_store_owner_notification_email_enabled: store_owner_notification_enabled
    )
  end
  let(:transactional_enabled) { true }
  let(:password_reset_enabled) { false }
  let(:newsletter_confirmation_enabled) { false }
  let(:order_confirmation_enabled) { false }
  let(:order_confirmation_resend_enabled) { false }
  let(:order_cancellation_enabled) { false }
  let(:fulfillment_fulfilled_enabled) { false }
  let(:return_enabled) { false }
  let(:store_owner_notification_enabled) { false }
  let(:subscriber) { described_class.new }

  before do
    integration
    allow(Spree::Store).to receive(:default).and_return(store)
    clear_enqueued_jobs
  end

  it 'runs synchronously so transactional sends only need the Plunk job queue' do
    expect(described_class.subscription_options).to eq(async: false)
  end

  it 'does not enqueue when the selected email type is disabled' do
    event = Spree::Event.new(
      name: 'customer.password_reset_requested',
      store_id: store.id,
      payload: { 'email' => 'buyer@example.com', 'reset_token' => 'reset-token' }
    )

    expect {
      subscriber.send(:handle_password_reset_requested, event)
    }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)
  end

  context 'when password reset handoff is enabled' do
    let(:password_reset_enabled) { true }

    it 'enqueues a password reset transactional send from the event payload' do
      payload = {
        'email' => 'buyer@example.com',
        'reset_token' => 'reset-token',
        'redirect_url' => 'https://storefront.example.com/reset'
      }
      event = Spree::Event.new(
        name: 'customer.password_reset_requested',
        store_id: store.id,
        payload: payload
      )

      expect {
        subscriber.send(:handle_password_reset_requested, event)
      }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
        integration.id,
        SpreePlunk::TransactionalEmailTypes::PASSWORD_RESET,
        nil,
        nil,
        'buyer@example.com',
        payload
      )
    end
  end

  context 'when newsletter confirmation handoff is enabled' do
    let(:newsletter_confirmation_enabled) { true }

    it 'enqueues a newsletter confirmation send for unverified subscribers' do
      newsletter_subscriber = instance_double(
        Spree::NewsletterSubscriber,
        id: 123,
        email: 'newsletter@example.com',
        verification_token: 'verify-token',
        verified?: false,
        to_param: 'sub_123'
      )
      allow(subscriber).to receive(:find_newsletter_subscriber).and_return(newsletter_subscriber)

      payload = {
        'id' => newsletter_subscriber.to_param,
        'email' => newsletter_subscriber.email,
        'verification_token' => newsletter_subscriber.verification_token,
        'store_id' => store.to_param,
        'redirect_url' => 'https://storefront.example.com/newsletter/confirm'
      }
      event = Spree::Event.new(
        name: 'newsletter_subscriber.subscription_requested',
        store_id: store.id,
        payload: payload
      )

      expect {
        subscriber.send(:handle_newsletter_subscription_requested, event)
      }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
        integration.id,
        SpreePlunk::TransactionalEmailTypes::NEWSLETTER_CONFIRMATION,
        Spree::NewsletterSubscriber.name,
        newsletter_subscriber.id,
        'newsletter@example.com',
        payload
      )
    end

    it 'does not send a newsletter confirmation to another store integration' do
      other_store = create(:store)
      newsletter_subscriber = create(:newsletter_subscriber, :unverified, store: other_store)
      event = Spree::Event.new(
        name: 'newsletter_subscriber.subscription_requested',
        store_id: other_store.id,
        payload: { 'id' => newsletter_subscriber.to_param, 'store_id' => other_store.to_param }
      )

      expect {
        subscriber.send(:handle_newsletter_subscription_requested, event)
      }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)
    end
  end

  context 'when order confirmation resend handoff is enabled' do
    let(:order_confirmation_resend_enabled) { true }

    it 'enqueues a resend for the order confirmation event' do
      user = create(:customer, email: 'buyer@example.com')
      order = create(:completed_order_with_totals, store: store, customer: user, email: user.email)
      event = Spree::Event.new(
        name: 'order.resend_confirmation_email',
        store_id: store.id,
        payload: { 'id' => order.to_param }
      )

      expect {
        subscriber.send(:handle_order_confirmation_resend, event)
      }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
        integration.id,
        SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND,
        Spree::Order.name,
        order.id,
        order.email,
        { 'id' => order.to_param }
      )
    end
  end

  context 'when grouped order confirmation resend handoff is enabled' do
    let(:order_confirmation_resend_enabled) { true }

    it 'enqueues a resend for the order group event' do
      user = create(:customer, email: 'buyer@example.com')
      order_group = create(:order_group, store: store, customer: user, email: user.email)
      event = Spree::Event.new(
        name: 'order_group.resend_confirmation_email',
        store_id: store.id,
        payload: { 'id' => order_group.to_param }
      )

      expect {
        subscriber.send(:handle_order_group_confirmation_resend, event)
      }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
        integration.id,
        SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND,
        Spree::OrderGroup.name,
        order_group.id,
        order_group.email,
        { 'id' => order_group.to_param }
      )
    end
  end

  context 'when order confirmation handoff is enabled' do
    let(:order_confirmation_enabled) { true }

    it 'enqueues a checkout completion confirmation send' do
      user = create(:customer, email: 'buyer@example.com')
      order = create(:completed_order_with_totals, store: store, customer: user, email: user.email, confirmation_delivered: false)
      payload = { 'id' => order.to_param, 'notify_customer' => true }
      event = Spree::Event.new(
        name: 'order.completed',
        store_id: store.id,
        payload: payload
      )

      expect {
        subscriber.send(:handle_order_completed, event)
      }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
        integration.id,
        SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION,
        Spree::Order.name,
        order.id,
        order.email,
        payload
      )
    end

    it 'does not enqueue when the confirmation was already delivered' do
      order = create(:completed_order_with_totals, store: store, confirmation_delivered: true)
      event = Spree::Event.new(
        name: 'order.completed',
        store_id: store.id,
        payload: { 'id' => order.to_param, 'notify_customer' => true }
      )

      expect {
        subscriber.send(:handle_order_completed, event)
      }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)
    end

    it 'does not enqueue when Spree disabled customer notification' do
      order = create(:completed_order_with_totals, store: store, confirmation_delivered: false)
      event = Spree::Event.new(
        name: 'order.completed',
        store_id: store.id,
        payload: { 'id' => order.to_param },
        metadata: { 'notify_customer' => false }
      )

      expect {
        subscriber.send(:handle_order_completed, event)
      }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)
    end
  end

  context 'when store owner notification handoff is enabled' do
    let(:store_owner_notification_enabled) { true }

    before do
      store.update!(new_order_notifications_email: 'owner@example.com')
    end

    it 'enqueues a store owner notification from order completion' do
      user = create(:customer, email: 'buyer@example.com')
      order = create(
        :completed_order_with_totals,
        store: store,
        customer: user,
        email: user.email,
        confirmation_delivered: false,
        store_owner_notification_delivered: false
      )
      payload = { 'id' => order.to_param, 'notify_customer' => true }
      event = Spree::Event.new(
        name: 'order.completed',
        store_id: store.id,
        payload: payload
      )

      expect {
        subscriber.send(:handle_order_completed, event)
      }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
        integration.id,
        SpreePlunk::TransactionalEmailTypes::STORE_OWNER_NOTIFICATION,
        Spree::Order.name,
        order.id,
        'owner@example.com',
        payload
      )
    end

    it 'does not enqueue when the store owner notification was already delivered' do
      order = create(
        :completed_order_with_totals,
        store: store,
        confirmation_delivered: false,
        store_owner_notification_delivered: true
      )
      event = Spree::Event.new(
        name: 'order.completed',
        store_id: store.id,
        payload: { 'id' => order.to_param, 'notify_customer' => true }
      )

      expect {
        subscriber.send(:handle_order_completed, event)
      }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)
    end
  end

  context 'when order cancellation handoff is enabled' do
    let(:order_cancellation_enabled) { true }

    it 'enqueues an order cancellation send' do
      user = create(:customer, email: 'buyer@example.com')
      order = create(:completed_order_with_totals, store: store, customer: user, email: user.email)
      payload = { 'id' => order.to_param, 'notify_customer' => true }
      event = Spree::Event.new(
        name: 'order.canceled',
        store_id: store.id,
        payload: payload
      )

      expect {
        subscriber.send(:handle_order_canceled, event)
      }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
        integration.id,
        SpreePlunk::TransactionalEmailTypes::ORDER_CANCELLATION,
        Spree::Order.name,
        order.id,
        order.email,
        payload
      )
    end

    it 'does not enqueue when Spree disabled customer notification' do
      order = create(:completed_order_with_totals, store: store)
      event = Spree::Event.new(
        name: 'order.canceled',
        store_id: store.id,
        payload: { 'id' => order.to_param },
        metadata: { 'notify_customer' => false }
      )

      expect {
        subscriber.send(:handle_order_canceled, event)
      }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)
    end
  end

  context 'when fulfillment shipped handoff is enabled' do
    let(:fulfillment_fulfilled_enabled) { true }

    it 'enqueues a fulfillment shipped send' do
      user = create(:customer, email: 'buyer@example.com')
      fulfillment = create_fulfilled_order(store: store, customer: user).fulfillments.first
      payload = { 'id' => fulfillment.to_param }
      event = Spree::Event.new(
        name: 'fulfillment.fulfilled',
        store_id: store.id,
        payload: payload
      )

      expect {
        subscriber.send(:handle_fulfillment_fulfilled, event)
      }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
        integration.id,
        SpreePlunk::TransactionalEmailTypes::FULFILLMENT_FULFILLED,
        Spree::Fulfillment.name,
        fulfillment.id,
        fulfillment.owner.email,
        payload
      )
    end
  end

  context 'when return refund handoff is enabled' do
    let(:return_enabled) { true }

    it 'enqueues a return refund send' do
      order = instance_double(Spree::Order, store: store, email: 'buyer@example.com')
      payload = { 'id' => 'ret_test' }
      event = Spree::Event.new(
        name: 'return.refunded',
        store_id: store.id,
        payload: payload
      )
      return_record = instance_double(Spree::Return, id: 42, order: order, refunded_total: BigDecimal('10'))
      allow(subscriber).to receive(:find_return).and_return(return_record)

      expect {
        subscriber.send(:handle_return_refunded, event)
      }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
        integration.id,
        SpreePlunk::TransactionalEmailTypes::RETURN_REFUNDED,
        Spree::Return.name,
        return_record.id,
        order.email,
        payload
      )
    end
  end
end
