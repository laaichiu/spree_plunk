require 'spec_helper'

RSpec.describe SpreePlunk::ReturnSubscriber do
  include ActiveJob::TestHelper

  let(:store) { create(:store) }
  let(:integration) { create(:plunk_integration, store: store) }
  let(:subscriber) { described_class.new }
  let(:order) { instance_double(Spree::Order, store_id: store.id, email: 'buyer@example.com') }
  let(:return_record) { instance_double(Spree::Return, id: 42, order: order) }

  before do
    integration
    allow(Spree::Return).to receive(:find_by_param).and_return(return_record)
    clear_enqueued_jobs
  end

  it 'runs synchronously so return tracking only needs the Plunk job queue' do
    expect(described_class.subscription_options).to eq(async: false)
  end

  it 'enqueues tracking for refunded returns' do
    event = Spree::Event.new(
      name: 'return.refunded',
      payload: { 'id' => 'ret_test' }
    )

    expect {
      subscriber.send(:handle_return_refunded, event)
    }.to have_enqueued_job(SpreePlunk::TrackEventJob).with(
      integration.id,
      SpreePlunk::EventNames::RETURN_REFUNDED,
      Spree::Return.name,
      return_record.id,
      return_record.order.email
    )
  end

  it 'skips tracking when the return no longer has an order' do
    orderless_return = instance_double(Spree::Return, id: 42, order: nil)
    event = Spree::Event.new(
      name: 'return.refunded',
      payload: { 'id' => 'ret_test' }
    )

    allow(Spree::Return).to receive(:find_by_param).and_return(orderless_return)

    expect {
      subscriber.send(:handle_return_refunded, event)
    }.not_to have_enqueued_job(SpreePlunk::TrackEventJob)
  end
end
