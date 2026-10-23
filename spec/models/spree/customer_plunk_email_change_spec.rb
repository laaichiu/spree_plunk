require 'spec_helper'

RSpec.describe Spree.customer_class, events: true do
  before do
    Spree::Events.reset!
  end

  after do
    Spree::Events.reset!
  end

  it 'resets marketing consent and publishes a private event when the email identity changes' do
    store = create(:store)
    customer = create(:customer, email: 'old@example.com', accepts_email_marketing: true)
    received_event = nil

    Spree::Events.subscribe(SpreePlunk::InternalEventNames::CUSTOMER_EMAIL_CHANGED, async: false) do |event|
      received_event = event
    end
    Spree::Events.activate!

    Spree::Current.with_store(store) { customer.update!(email: 'new@example.com') }

    aggregate_failures do
      expect(customer.reload.accepts_email_marketing).to be(false)
      expect(customer.email_marketing_consent_source).to eq(Spree::ConsentRecord::UNKNOWN)
      expect(received_event).to be_present
      expect(received_event.payload).to eq(
        'customer_id' => customer.prefixed_id,
        'store_id' => store.to_param
      )
      expect(received_event.payload.values).not_to include('old@example.com', 'new@example.com')
      expect(Spree::Events.catalog.find(SpreePlunk::InternalEventNames::CUSTOMER_EMAIL_CHANGED).webhook?).to be(false)
    end
  end

  it 'does not reset consent for a case-only email change' do
    customer = create(:customer, email: 'Ada@Example.com', accepts_email_marketing: true)

    customer.update!(email: 'ada@example.com')

    expect(customer.reload.accepts_email_marketing).to be(true)
  end

  it 'does not reset consent for surrounding whitespace changes' do
    customer = create(:customer, email: 'ada@example.com', accepts_email_marketing: true)

    customer.update!(email: ' ada@example.com ')

    expect(customer.reload.accepts_email_marketing).to be(true)
  end

  it 'treats Unicode case-fold lookalikes as different email identities' do
    customer = create(:customer, email: 'longs@example.com', accepts_email_marketing: true)

    customer.update!(email: "longſ@example.com")

    expect(customer.reload.accepts_email_marketing).to be(false)
  end

  it 'preserves the initial consent choice when creating a customer' do
    customer = create(:customer, email: 'new@example.com', accepts_email_marketing: true)

    expect(customer.accepts_email_marketing).to be(true)
  end
end
