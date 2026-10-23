require 'spec_helper'

RSpec.describe SpreePlunk::SendTransactionalEmail do
  subject(:result) do
    described_class.call(
      plunk_integration: integration,
      email_type: email_type,
      resource: resource,
      email: email,
      event_payload: event_payload
    )
  end

  let(:store) { create(:store, name: 'Example Store', mail_from_address: 'orders@example.com') }
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
      preferred_store_owner_notification_email_enabled: store_owner_notification_enabled,
      preferred_default_from_email: 'plunk@example.com',
      preferred_default_from_name: 'Example Store'
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
  let(:email_type) { SpreePlunk::TransactionalEmailTypes::PASSWORD_RESET }
  let(:resource) { nil }
  let(:email) { 'buyer@example.com' }
  let(:event_payload) { {} }

  before do
    stub_request(:post, 'https://next-api.useplunk.com/v1/send')
      .to_return(status: 200, body: '{"id":"email_123"}', headers: { 'Content-Type' => 'application/json' })
  end

  context 'when the handoff is disabled' do
    let(:transactional_enabled) { false }

    it 'does not call Plunk' do
      expect(result).to be_success
      expect(result.value).to include(skipped: true, reason: 'transactional_email_disabled')
      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send')).not_to have_been_made
    end
  end

  context 'when sending a password reset' do
    let(:password_reset_enabled) { true }
    let(:event_payload) do
      {
        'email' => 'buyer@example.com',
        'reset_token' => 'reset-token',
        'redirect_url' => 'https://storefront.example.com/reset?source=account#form'
      }
    end

    it 'sends a direct Plunk email without changing marketing consent' do
      expect(result).to be_success

      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send').with { |request|
        body = JSON.parse(request.body)

        aggregate_failures do
          expect(body['to']).to eq('buyer@example.com')
          expect(body['from']).to eq('name' => 'Example Store', 'email' => 'plunk@example.com')
          expect(body['subject']).to eq('Reset your Example Store password')
          expect(body['subscribed']).to be_nil
          expect(body.dig('data', 'reset_token')).to eq('value' => 'reset-token', 'persistent' => false)
          expect(body.dig('data', 'reset_url')).to eq(
            'value' => 'https://storefront.example.com/reset?source=account&token=reset-token#form',
            'persistent' => false
          )
          expect(body.dig('headers', 'X-Spree-Plunk-Email-Type')).to eq(SpreePlunk::TransactionalEmailTypes::PASSWORD_RESET)
        end

        true
      }).to have_been_made
    end
  end

  context 'when sending from a template' do
    let(:password_reset_enabled) { true }
    let(:event_payload) do
      {
        'email' => 'buyer@example.com',
        'reset_token' => 'reset-token',
        'redirect_url' => 'https://storefront.example.com/reset'
      }
    end

    before do
      integration.update!(preferred_password_reset_template_id: 'tpl_password')
    end

    it 'uses the template id and leaves content ownership to Plunk' do
      expect(result).to be_success

      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send').with { |request|
        body = JSON.parse(request.body)

        expect(body).to include('template' => 'tpl_password')
        expect(body).not_to include('subject')
        expect(body).not_to include('body')
        true
      }).to have_been_made
    end
  end

  context 'when sending an order confirmation from checkout completion' do
    let(:email_type) { SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION }
    let(:order_confirmation_enabled) { true }
    let(:user) { create(:customer, email: 'buyer@example.com') }
    let(:resource) { create(:completed_order_with_totals, store: store, customer: user, email: 'buyer@example.com', confirmation_delivered: false) }
    let(:email) { resource.email }
    let(:event_payload) { { 'id' => resource.to_param, 'notify_customer' => true } }

    it 'sends the confirmation and marks the order as delivered after Plunk accepts it' do
      expect { result }.to change { resource.reload.confirmation_delivered? }.from(false).to(true)

      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send').with { |request|
        body = JSON.parse(request.body)

        expect(plunk_data_value(body['data'], 'email_type')).to eq(SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION)
        expect(plunk_data_value(body['data'], 'order_number')).to eq(resource.number)
        expect(plunk_data_value(body['data'], 'line_items_html')).to include('<table')
        expect(plunk_data_value(body['data'], 'totals_text')).to include('Total:')
        true
      }).to have_been_made
    end
  end

  context 'when the order confirmation was already delivered' do
    let(:email_type) { SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION }
    let(:order_confirmation_enabled) { true }
    let(:resource) { create(:completed_order_with_totals, store: store, email: 'buyer@example.com', confirmation_delivered: true) }
    let(:email) { resource.email }

    it 'skips the send to preserve Spree confirmation idempotency' do
      expect(result).to be_success
      expect(result.value).to include(skipped: true, reason: 'order_confirmation_already_delivered')
      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send')).not_to have_been_made
    end
  end

  context 'when a published dashboard email template exists' do
    let(:email_type) { SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION }
    let(:order_confirmation_enabled) { true }
    let(:user) { create(:customer, email: 'buyer@example.com') }
    let(:resource) { create(:completed_order_with_totals, store: store, customer: user, email: 'buyer@example.com', confirmation_delivered: false) }
    let(:email) { resource.email }
    let(:event_payload) { { 'id' => resource.to_param, 'notify_customer' => true, 'locale' => 'fr' } }

    before do
      Spree::EmailTemplate.create!(
        store: store,
        key: 'spree/order_mailer/confirm_email',
        locale: Spree::EmailTemplate::ANY_LOCALE,
        status: 'published',
        subject: '{{ store.name }} / {{ order.number }}',
        body: '<p>Dashboard edit: {{ store.name }} — {{ order.number }} — {{ order.customer_name }} — {{ order.total_minus_store_credits | money }} {% for item in order.items %}{{ item.name }}{% endfor %}</p>',
        base_subject: 'Original subject',
        base_body: '<p>Original body</p>',
        published_at: Time.current
      )
    end

    it 'renders with Spree 6 assignments under the requested locale and store fallback' do
      previous_fallbacks = Mobility.store_based_fallbacks

      expect(result).to be_success
      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send').with { |request|
        body = JSON.parse(request.body)

        expect(body['subject']).to include(resource.number)
        expect(body['body']).to include('Dashboard edit:', store.name, resource.number, resource.ship_address.full_name)
        expect(body['body']).to include(resource.line_items.first.name)
        expect(body).not_to have_key('template')
        true
      }).to have_been_made
      expect(Mobility.store_based_fallbacks).to equal(previous_fallbacks)
    end

    it 'does not send the Plunk fallback when a published dashboard template fails to render' do
      allow(Spree::Emails::Renderer).to receive(:new).and_raise(StandardError, 'invalid published template')

      expect(result).to be_failure
      expect(result.value).to include(error_code: 'email_template_render_failed', retryable: false)
      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send')).not_to have_been_made
    end
  end

  context 'when sending an order confirmation resend' do
    let(:email_type) { SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND }
    let(:order_confirmation_resend_enabled) { true }
    let(:resource) { create(:completed_order_with_totals, store: store, email: 'buyer@example.com', confirmation_delivered: false) }
    let(:email) { resource.email }

    it 'marks the order confirmation as delivered after Plunk accepts the send' do
      expect { result }.to change { resource.reload.confirmation_delivered? }.from(false).to(true)
    end
  end

  context 'when sending an order cancellation' do
    let(:email_type) { SpreePlunk::TransactionalEmailTypes::ORDER_CANCELLATION }
    let(:order_cancellation_enabled) { true }
    let(:resource) { create(:completed_order_with_totals, store: store, email: 'buyer@example.com') }
    let(:email) { resource.email }
    let(:event_payload) { { 'id' => resource.to_param, 'notify_customer' => false } }

    it 'skips when Spree disabled customer notification for the cancellation' do
      expect(result).to be_success
      expect(result.value).to include(skipped: true, reason: 'notify_customer_disabled')
      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send')).not_to have_been_made
    end
  end

  context 'when sending a fulfillment shipped notification' do
    let(:email_type) { SpreePlunk::TransactionalEmailTypes::FULFILLMENT_FULFILLED }
    let(:fulfillment_fulfilled_enabled) { true }
    let(:user) { create(:customer, email: 'buyer@example.com') }
    let(:resource) { create_fulfilled_order(store: store, customer: user).fulfillments.first }
    let(:email) { resource.owner.email }

    it 'sends fulfillment data to Plunk' do
      expect(result).to be_success

      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send').with { |request|
        body = JSON.parse(request.body)

        expect(plunk_data_value(body['data'], 'email_type')).to eq(SpreePlunk::TransactionalEmailTypes::FULFILLMENT_FULFILLED)
        expect(plunk_data_value(body['data'], 'fulfillment_number')).to eq(resource.number)
        expect(plunk_data_value(body['data'], 'recipient_email')).to eq('buyer@example.com')
        expect(plunk_data_value(body['data'], 'fulfillment_items_html')).to include('<table')
        expect(plunk_data_value(body['data'], 'fulfillment_items')).not_to be_empty
        true
      }).to have_been_made
    end
  end

  context 'when sending a return notification' do
    let(:email_type) { SpreePlunk::TransactionalEmailTypes::RETURN_REFUNDED }
    let(:return_enabled) { true }
    let(:user) { create(:customer, email: 'buyer@example.com') }
    let(:resource) do
      order = create_fulfilled_order(store: store, customer: user)
      create(:return, order: order, stock_location: order.fulfillments.first.stock_location, status: 'refunded').tap do |return_record|
        allow(return_record).to receive(:refunded_total).and_return(BigDecimal('19.99'))
      end
    end
    let(:email) { resource.order.email }

    it 'sends return refund data to Plunk' do
      expect(result).to be_success

      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send').with { |request|
        body = JSON.parse(request.body)

        expect(plunk_data_value(body['data'], 'email_type')).to eq(SpreePlunk::TransactionalEmailTypes::RETURN_REFUNDED)
        expect(plunk_data_value(body['data'], 'return_number')).to eq(resource.number)
        expect(plunk_data_value(body['data'], 'recipient_email')).to eq('buyer@example.com')
        expect(plunk_data_value(body['data'], 'return_items_html')).to include('<table')
        expect(plunk_data_value(body['data'], 'return_items')).not_to be_empty
        true
      }).to have_been_made
    end
  end

  context 'when sending a store owner notification' do
    let(:email_type) { SpreePlunk::TransactionalEmailTypes::STORE_OWNER_NOTIFICATION }
    let(:store_owner_notification_enabled) { true }
    let(:store) { create(:store, name: 'Example Store', mail_from_address: 'orders@example.com', new_order_notifications_email: 'owner@example.com') }
    let(:user) { create(:customer, email: 'buyer@example.com') }
    let(:resource) { create(:completed_order_with_totals, store: store, customer: user, email: user.email, store_owner_notification_delivered: false) }
    let(:email) { store.new_order_notifications_email }

    it 'sends the notification and marks it as delivered after Plunk accepts it' do
      expect { result }.to change { resource.reload.store_owner_notification_delivered? }.from(false).to(true)

      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send').with { |request|
        body = JSON.parse(request.body)

        expect(body['to']).to eq('owner@example.com')
        expect(plunk_data_value(body['data'], 'email_type')).to eq(SpreePlunk::TransactionalEmailTypes::STORE_OWNER_NOTIFICATION)
        expect(plunk_data_value(body['data'], 'customer_email')).to eq('buyer@example.com')
        true
      }).to have_been_made
    end
  end

  context 'when the store owner notification was already delivered' do
    let(:email_type) { SpreePlunk::TransactionalEmailTypes::STORE_OWNER_NOTIFICATION }
    let(:store_owner_notification_enabled) { true }
    let(:store) { create(:store, name: 'Example Store', mail_from_address: 'orders@example.com', new_order_notifications_email: 'owner@example.com') }
    let(:resource) { create(:completed_order_with_totals, store: store, store_owner_notification_delivered: true) }
    let(:email) { store.new_order_notifications_email }

    it 'skips the send to preserve Spree store owner notification idempotency' do
      expect(result).to be_success
      expect(result.value).to include(skipped: true, reason: 'store_owner_notification_already_delivered')
      expect(a_request(:post, 'https://next-api.useplunk.com/v1/send')).not_to have_been_made
    end
  end

end
