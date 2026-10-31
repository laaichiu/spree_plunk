require 'spec_helper'

RSpec.describe Spree::LineItem, events: true do
  before do
    Spree::Events.reset!
  end

  after do
    Spree::Events.reset!
  end

  let(:store) { create(:store) }
  let(:customer) { create(:customer, email: 'buyer@example.com') }
  let(:cart) { create(:cart, store: store, customer: customer, email: nil) }
  let(:product) { create(:product, store: store) }

  it 'publishes a cart-added snapshot on line-item create' do
    received_event = nil
    Spree::Events.subscribe('line_item.created', async: false) { |event| received_event = event }
    Spree::Events.activate!

    line_item = create(:line_item, cart: cart, order: nil, product: product, quantity: 2, price: 19.99, currency: 'USD')

    expect(received_event).to be_present
    expect(received_event.payload).to include(
      'cart_activity_event' => 'added',
      'email' => 'buyer@example.com',
      'line_item_id' => line_item.prefixed_id,
      'order_id' => cart.prefixed_id,
      'cart_record_id' => cart.id,
      'customer_id' => customer.id,
      'store_id' => store.id,
      'quantity' => 2
    )
  end

  it 'does not label a placed-order line item as a cart activity' do
    order = create(:order_with_line_items, store: store, customer: customer, email: customer.email)
    received_event = nil
    Spree::Events.subscribe('line_item.created', async: false) { |event| received_event = event }
    Spree::Events.activate!

    create(:line_item, order: order, cart: nil, product: product, quantity: 1, price: 19.99, currency: 'USD')

    expect(received_event).to be_present
    expect(received_event.payload).not_to have_key('cart_activity_event')
  end

  it 'publishes a cart-added snapshot when quantity increases' do
    line_item = create(:line_item, cart: cart, order: nil, product: product, quantity: 1, price: 19.99, currency: 'USD')
    received_event = nil
    Spree::Events.subscribe('line_item.updated', async: false) { |event| received_event = event }
    Spree::Events.activate!

    line_item.update!(quantity: 3)

    expect(received_event).to be_present
    expect(received_event.payload).to include(
      'cart_activity_event' => 'added',
      'email' => 'buyer@example.com',
      'quantity' => 3,
      'previous_quantity' => 1
    )
  end

  it 'publishes a cart-removed snapshot when quantity decreases' do
    line_item = create(:line_item, cart: cart, order: nil, product: product, quantity: 3, price: 19.99, currency: 'USD')
    received_event = nil
    Spree::Events.subscribe('line_item.updated', async: false) { |event| received_event = event }
    Spree::Events.activate!

    line_item.update!(quantity: 1)

    expect(received_event).to be_present
    expect(received_event.payload).to include(
      'cart_activity_event' => 'removed',
      'email' => 'buyer@example.com',
      'quantity' => 1,
      'previous_quantity' => 3
    )
  end
end
