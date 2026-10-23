require 'spec_helper'

RSpec.describe SpreePlunk::FulfillmentPresenter do
  it 'builds fulfillment payload details for fulfilled orders' do
    store = create(:store, code: 'default-store')
    fulfillment = create_fulfilled_order(store: store, email: 'buyer@example.com').fulfillments.first
    fulfillment.update_column(:fulfilled_at, Time.utc(2026, 5, 18, 10, 0, 0))

    payload = described_class.new(fulfillment: fulfillment, store: store).call

    expect(payload).to include(
      fulfillment_number: fulfillment.number,
      fulfillment_status: fulfillment.status,
      tracking: fulfillment.tracking,
      delivery_total: fulfillment.cost.to_f,
      order_number: fulfillment.owner.number,
      store_code: 'default-store',
      fulfilled_at: fulfillment.fulfilled_at.iso8601
    )
    expect(payload.keys).not_to include(:shipment_id, :shipment_number, :shipment_state, :shipped_at)
  end
end
