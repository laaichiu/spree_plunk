require 'spec_helper'

RSpec.describe Spree::Carts::Update, events: true do
  before do
    Spree::Events.reset!
  end

  after do
    Spree::Events.reset!
  end

  let(:store) { create(:store) }
  let(:customer) { create(:customer, email: 'buyer@example.com') }
  let(:cart) { create(:cart_with_line_items, customer: customer, store: store, email: nil) }
  let(:country) { Spree::Country.by_iso('US') || create(:country, iso: 'US') }
  let!(:state) { country.states.find { |candidate| candidate.abbr == 'NY' } || create(:state, country: country, abbr: 'NY', name: 'New York') }

  it 'publishes checkout email entered and current step viewed when the checkout email becomes known' do
    received_events = []

    Spree::Events.subscribe('checkout.email_entered', async: false) { |event| received_events << event }
    Spree::Events.subscribe('checkout.step_viewed', async: false) { |event| received_events << event }
    Spree::Events.activate!

    result = described_class.call(cart: cart, params: { email: 'checkout@example.com' })

    aggregate_failures do
      expect(result).to be_success
      expect(received_events.map(&:name)).to eq(%w[checkout.email_entered checkout.step_viewed])
      expect(received_events.first.payload).to include(
        'email' => 'checkout@example.com',
        'order_id' => cart.prefixed_id
      )
      expect(received_events.second.payload).to include(
        'checkout_step' => cart.reload.current_checkout_step,
        'current_checkout_step' => cart.current_checkout_step,
        'email' => 'checkout@example.com'
      )
    end
  end

  it 'publishes checkout step completed and viewed events when cart update advances checkout state' do
    received_events = []

    Spree::Events.subscribe('checkout.step_completed', async: false) { |event| received_events << event }
    Spree::Events.subscribe('checkout.step_viewed', async: false) { |event| received_events << event }
    Spree::Events.activate!

    result = described_class.call(
      cart: cart,
      params: {
        email: 'checkout@example.com',
        shipping_address: {
          first_name: 'John',
          last_name: 'Doe',
          address1: '123 Main St',
          city: 'New York',
          postal_code: '10001',
          country_code: 'US',
          state_code: 'NY',
          phone: '555-1234'
        },
        billing_address: {
          first_name: 'John',
          last_name: 'Doe',
          address1: '123 Main St',
          city: 'New York',
          postal_code: '10001',
          country_code: 'US',
          state_code: 'NY',
          phone: '555-1234'
        }
      }
    )

    completed_steps = received_events.select { |event| event.name == 'checkout.step_completed' }.map { |event| event.payload['checkout_step'] }
    viewed_event = received_events.detect { |event| event.name == 'checkout.step_viewed' }

    aggregate_failures do
      expect(result).to be_success
      expect(completed_steps).to include('address')
      expect(viewed_event).to be_present
      expect(viewed_event.payload).to include(
        'checkout_step' => cart.reload.current_checkout_step,
        'email' => 'checkout@example.com'
      )
    end
  end
end
