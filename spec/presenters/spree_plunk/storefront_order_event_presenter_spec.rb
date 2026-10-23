require 'spec_helper'

RSpec.describe SpreePlunk::StorefrontOrderEventPresenter do
  let(:store) { create(:store, code: 'default-store') }

  it 'builds checkout and coupon event data from an order payload snapshot' do
    payload = {
      'order_id' => 'or_123',
      'order_number' => 'R123456',
      'store_code' => 'default-store',
      'email' => 'buyer@example.com',
      'status' => 'placed',
      'checkout_step' => 'payment',
      'previous_checkout_step' => 'delivery',
      'current_checkout_step' => 'payment',
      'payment_status' => 'partially_paid',
      'fulfillment_status' => 'unfulfilled',
      'currency' => 'USD',
      'total' => 49.99,
      'item_total' => 39.99,
      'delivery_total' => 10.0,
      'tax_total' => 2.5,
      'discount_total' => -5.0,
      'item_count' => 2,
      'line_items_count' => 2,
      'coupon_code' => 'save10',
      'coupon_status_code' => 'coupon_code_applied',
      'coupon_error' => nil
    }

    result = described_class.new(payload: payload, store: store).call

    expect(result).to include(
      order_id: 'or_123',
      order_number: 'R123456',
      store_code: 'default-store',
      email: 'buyer@example.com',
      status: 'placed',
      checkout_step: 'payment',
      previous_checkout_step: 'delivery',
      current_checkout_step: 'payment',
      payment_status: 'partially_paid',
      fulfillment_status: 'unfulfilled',
      currency: 'USD',
      total: 49.99,
      item_total: 39.99,
      delivery_total: 10.0,
      tax_total: 2.5,
      discount_total: -5.0,
      item_count: 2,
      line_items_count: 2,
      coupon_code: 'save10',
      coupon_status_code: 'coupon_code_applied'
    )

    expect(result).not_to have_key(:state)
    expect(result).not_to have_key(:payment_state)
  end
end
