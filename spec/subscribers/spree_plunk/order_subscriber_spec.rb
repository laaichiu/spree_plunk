require 'spec_helper'

RSpec.describe SpreePlunk::OrderSubscriber do
  include ActiveJob::TestHelper

  let(:store) { create(:store) }
  let(:integration) { create(:plunk_integration, store: store) }
  let(:subscriber) { described_class.new }
  let(:user) { create(:customer, email: 'buyer@example.com') }
  let(:order) { create(:completed_order_with_totals, store: store, customer: user, email: user.email) }

  before do
    integration
    clear_enqueued_jobs
  end

  it 'runs synchronously so order tracking only needs the Plunk job queue' do
    expect(described_class.subscription_options).to eq(async: false)
  end

  it 'enqueues tracking for an order placed event' do
    event = Spree::Event.new(
      name: 'order.placed',
      payload: { 'id' => order.to_param }
    )

    expect {
      subscriber.send(:handle_order_placed, event)
    }.to have_enqueued_job(SpreePlunk::TrackEventJob).with(
      integration.id,
      SpreePlunk::EventNames::ORDER_PLACED,
      Spree::Order.name,
      order.id,
      order.email
    )
  end
end
