require 'spec_helper'

RSpec.describe Spree::Address, events: true do
  before do
    Spree::Events.reset!
  end

  after do
    Spree::Events.reset!
  end

  it 'publishes a PII-free customer address change event that is not forwarded as a webhook' do
    store = create(:store)
    customer = create(:customer_with_addresses, email: 'buyer@example.com')
    address = customer.bill_address || customer.ship_address
    received_event = nil

    Spree::Events.subscribe(SpreePlunk::AddressDecorator::CUSTOMER_ADDRESS_CHANGED_EVENT, async: false) do |event|
      received_event = event
    end
    Spree::Events.activate!

    Spree::Current.with_store(store) { address.update!(address1: 'Updated street') }

    expect(received_event).to be_present
    expect(received_event.payload).to eq(
      'customer_id' => customer.prefixed_id,
      'store_id' => store.to_param
    )
    expect(Spree::Events.catalog.find(SpreePlunk::AddressDecorator::CUSTOMER_ADDRESS_CHANGED_EVENT).webhook?).to be(false)
  end
end
