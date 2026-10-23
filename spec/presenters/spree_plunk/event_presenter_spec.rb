require 'spec_helper'

RSpec.describe SpreePlunk::EventPresenter do
  describe '#call' do
    let(:store) { create(:store, code: 'default-store') }

    context 'with an order resource' do
      let(:user) { create(:customer, email: 'buyer@example.com') }
      let(:order) { create(:completed_order_with_totals, store: store, customer: user, email: user.email) }

      it 'builds a Plunk event payload with order data' do
        payload = described_class.new(
          event_name: SpreePlunk::EventNames::ORDER_PLACED,
          contact_id: 'cnt_123',
          resource: order,
          store: store,
          email: 'checkout@example.com'
        ).call

        expect(payload).to include(
          name: SpreePlunk::EventNames::ORDER_PLACED,
          contactId: 'cnt_123'
        )
        expect(payload[:data]).to include(
          order_id: order.prefixed_id,
          order_number: order.number,
          store_code: 'default-store',
          email: 'checkout@example.com',
          status: order.status
        )
      end
    end

    context 'with a line item resource' do
      let(:user) { create(:customer, email: 'buyer@example.com') }
      let(:order) { create(:order, store: store, customer: user, email: user.email) }
      let(:product) { create(:product, store: store) }
      let(:line_item) { create(:line_item, order: order, product: product, quantity: 2, price: 19.99, currency: 'USD') }

      it 'builds a Plunk event payload with line-item cart data' do
        payload = described_class.new(
          event_name: SpreePlunk::EventNames::CART_ADDED,
          contact_id: 'cnt_789',
          resource: line_item,
          store: store
        ).call

        expect(payload).to include(
          name: SpreePlunk::EventNames::CART_ADDED,
          contactId: 'cnt_789'
        )
        expect(payload[:data]).to include(
          line_item_id: line_item.prefixed_id,
          order_id: order.prefixed_id,
          order_number: order.number,
          store_code: 'default-store',
          email: 'buyer@example.com',
          quantity: 2
        )
      end
    end

    context 'with a current cart resource' do
      let(:customer) { create(:customer, email: 'buyer@example.com') }
      let(:cart) { create(:cart_with_line_items, store: store, customer: customer, email: customer.email) }

      it 'uses the cart checkout step and current purchase totals' do
        payload = described_class.new(
          event_name: SpreePlunk::EventNames::CHECKOUT_STEP_VIEWED,
          contact_id: 'cnt_cart',
          resource: cart,
          store: store
        ).call

        expect(payload[:data]).to include(
          order_id: cart.prefixed_id,
          order_number: cart.prefixed_id,
          checkout_step: cart.current_checkout_step,
          current_checkout_step: cart.current_checkout_step,
          item_count: cart.total_quantity,
          line_items_count: cart.line_items.size
        )
      end
    end

    context 'with newsletter payload data' do
      let(:resource) do
        {
          'email' => 'newsletter@example.com',
          'verified' => true,
          'verified_at' => '2026-05-18T10:00:00Z',
          'customer_id' => 'cus_123'
        }
      end

      it 'builds a Plunk event payload from a hash snapshot' do
        payload = described_class.new(
          event_name: SpreePlunk::EventNames::NEWSLETTER_UNSUBSCRIBED,
          contact_id: 'cnt_456',
          resource: resource,
          store: store
        ).call

        expect(payload).to include(
          name: SpreePlunk::EventNames::NEWSLETTER_UNSUBSCRIBED,
          contactId: 'cnt_456'
        )
        expect(payload[:data]).to include(
          email: 'newsletter@example.com',
          verified: true,
          verified_at: '2026-05-18T10:00:00Z',
          customer_id: 'cus_123',
          store_code: 'default-store'
        )
      end
    end

    context 'with storefront order payload data' do
      let(:resource) do
        {
          'order_id' => 'or_123',
          'order_number' => 'R123456',
          'store_code' => 'default-store',
          'email' => 'checkout@example.com',
          'checkout_step' => 'payment',
          'previous_checkout_step' => 'delivery',
          'current_checkout_step' => 'payment',
          'coupon_code' => 'save10',
          'coupon_status_code' => 'coupon_code_applied'
        }
      end

      it 'builds a Plunk event payload from a checkout or coupon snapshot hash' do
        payload = described_class.new(
          event_name: SpreePlunk::EventNames::COUPON_APPLIED,
          contact_id: 'cnt_999',
          resource: resource,
          store: store
        ).call

        expect(payload).to include(
          name: SpreePlunk::EventNames::COUPON_APPLIED,
          contactId: 'cnt_999'
        )
        expect(payload[:data]).to include(
          order_id: 'or_123',
          order_number: 'R123456',
          store_code: 'default-store',
          email: 'checkout@example.com',
          checkout_step: 'payment',
          previous_checkout_step: 'delivery',
          current_checkout_step: 'payment',
          coupon_code: 'save10',
          coupon_status_code: 'coupon_code_applied'
        )
      end
    end
  end
end
