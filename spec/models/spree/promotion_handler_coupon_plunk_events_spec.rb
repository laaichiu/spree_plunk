require 'spec_helper'

RSpec.describe Spree::PromotionHandler::Coupon, events: true do
  before do
    Spree::Events.reset!
  end

  after do
    Spree::Events.reset!
  end

  let(:store) { create(:store) }
  let(:customer) { create(:customer, email: 'buyer@example.com') }
  let(:cart) { create(:cart_with_line_items, store: store, customer: customer, email: customer.email) }

  it 'publishes coupon entered and applied events for a successful coupon apply' do
    create(:promotion_with_item_adjustment, code: 'SAVE10', store: store)
    received_events = []

    Spree::Events.subscribe('coupon.entered', async: false) { |event| received_events << event }
    Spree::Events.subscribe('coupon.applied', async: false) { |event| received_events << event }
    Spree::Events.activate!

    cart.coupon_code = 'SAVE10'
    described_class.new(cart, enable_gift_cards: false).apply

    aggregate_failures do
      expect(received_events.map(&:name)).to eq(%w[coupon.entered coupon.applied])
      expect(received_events.first.payload).to include(
        'email' => 'buyer@example.com',
        'order_id' => cart.prefixed_id,
        'coupon_code' => 'save10'
      )
      expect(received_events.second.payload).to include(
        'coupon_code' => 'save10',
        'coupon_status_code' => 'coupon_code_applied'
      )
    end
  end

  it 'publishes coupon entered and denied events for an invalid coupon apply' do
    received_events = []

    Spree::Events.subscribe('coupon.entered', async: false) { |event| received_events << event }
    Spree::Events.subscribe('coupon.denied', async: false) { |event| received_events << event }
    Spree::Events.activate!

    cart.coupon_code = 'INVALID'
    described_class.new(cart, enable_gift_cards: false).apply

    aggregate_failures do
      expect(received_events.map(&:name)).to eq(%w[coupon.entered coupon.denied])
      expect(received_events.second.payload).to include(
        'coupon_code' => 'invalid',
        'coupon_status_code' => 'coupon_code_not_found'
      )
    end
  end

  it 'publishes a coupon removed event for a successful coupon removal' do
    create(:promotion_with_item_adjustment, code: 'REMOVE10', store: store)
    received_event = nil

    cart.coupon_code = 'REMOVE10'
    described_class.new(cart, enable_gift_cards: false).apply

    Spree::Events.subscribe('coupon.removed', async: false) { |event| received_event = event }
    Spree::Events.activate!

    described_class.new(cart, enable_gift_cards: false).remove('REMOVE10')

    expect(received_event.payload).to include(
      'email' => 'buyer@example.com',
      'coupon_code' => 'remove10',
      'coupon_status_code' => 'adjustments_deleted'
    )
  end
end
