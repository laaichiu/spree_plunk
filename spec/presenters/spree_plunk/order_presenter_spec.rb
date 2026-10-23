require 'spec_helper'

RSpec.describe SpreePlunk::OrderPresenter do
  let(:store) { create(:store, code: 'default-store') }

  it 'uses the explicit email override and exposes current order and coupon fields' do
    order = create(:completed_order_with_totals, store: store, email: 'buyer@example.com')
    order.update!(coupon_code: 'WELCOME10')

    payload = described_class.new(order: order, store: store, email: 'checkout@example.com').call

    expect(payload).to include(
      order_id: order.prefixed_id,
      order_number: order.number,
      store_code: 'default-store',
      email: 'checkout@example.com',
      coupon_code: 'welcome10'
    )
    expect(payload).not_to have_key(:checkout_step)
  end
end
