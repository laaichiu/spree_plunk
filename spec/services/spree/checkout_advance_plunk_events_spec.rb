require 'spec_helper'

RSpec.describe Spree::Checkout::Advance do
  it 'publishes checkout step events when recalculation changes the cart requirements' do
    cart = instance_double(Spree::Cart, fulfillments: [], delivery_step_required?: false)
    allow(cart).to receive(:current_checkout_step).and_return('address', 'delivery')
    allow(cart).to receive(:can_propose_deliveries?).and_return(false)
    allow(cart).to receive(:recalculate_totals!)

    expect(SpreePlunk::StorefrontOrderEventPublisher).to receive(:publish_checkout_step_events).with(
      order: cart,
      previous_state: 'address',
      current_state: 'delivery'
    )

    result = described_class.call(order: cart)

    expect(result).to be_success
  end
end
