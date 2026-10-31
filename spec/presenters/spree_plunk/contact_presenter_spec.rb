require 'spec_helper'

RSpec.describe SpreePlunk::ContactPresenter do
  subject(:payload) do
    described_class.new(
      customer: user,
      subscriber: subscriber,
      store: store
    ).call(subscribed: subscribed)
  end

  let(:store) { create(:store, code: 'default-store') }
  let(:subscribed) { false }
  let(:subscriber) { nil }
  let(:user) do
    create(
      :customer_with_addresses,
      email: 'ada@example.com',
      first_name: 'Ada',
      last_name: 'Lovelace',
      phone: '555-0101',
      accepts_email_marketing: true
    )
  end

  before do
    user.bill_address.update!(
      firstname: 'Ada',
      lastname: 'Lovelace',
      city: 'New York',
      zipcode: '10001'
    )
  end

  it 'builds a Plunk-compatible contact payload' do
    expect(payload).to include(
      email: 'ada@example.com',
      subscribed: false
    )
    expect(payload[:data]).to include(
      external_user_id: user.id,
      store_code: 'default-store',
      first_name: 'Ada',
      last_name: 'Lovelace',
      phone: '555-0101',
      accepts_email_marketing: true,
      city: 'New York',
      zip: '10001'
    )
  end

  it 'limits order metrics to the integration store' do
    create(:completed_order_with_totals, store: store, customer: user, email: user.email)
    other_store = create(:store)
    create(:completed_order_with_totals, store: other_store, customer: user, email: user.email)

    expect(payload.dig(:data, :order_count)).to eq(1)
    expect(payload.dig(:data, :last_order_number)).to eq(user.completed_orders_for_store(store).first.number)
  end

  context 'with a newsletter subscriber' do
    let(:subscriber) do
      instance_double(
        Spree::NewsletterSubscriber,
        customer: user,
        email: 'ada@example.com',
        accepts_email_marketing: true
      )
    end
    let(:subscribed) { true }

    it 'prefers subscriber-backed marketing state' do
      expect(payload[:subscribed]).to eq(true)
      expect(payload[:data][:accepts_email_marketing]).to eq(true)
    end
  end
end
