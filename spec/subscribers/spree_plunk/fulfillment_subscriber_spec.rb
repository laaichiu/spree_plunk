require 'spec_helper'

RSpec.describe SpreePlunk::FulfillmentSubscriber do
  include ActiveJob::TestHelper

  let(:store) { create(:store) }
  let(:integration) { create(:plunk_integration, store: store) }
  let(:subscriber) { described_class.new }
  let(:fulfillment) { create_fulfilled_order(store: store).fulfillments.first }

  before do
    integration
    clear_enqueued_jobs
  end

  it 'runs synchronously so fulfillment tracking only needs the Plunk job queue' do
    expect(described_class.subscription_options).to eq(async: false)
  end

  it 'enqueues tracking for fulfilled fulfillments' do
    event = Spree::Event.new(
      name: 'fulfillment.fulfilled',
      payload: { 'id' => fulfillment.to_param }
    )

    expect {
      subscriber.send(:handle_fulfillment_fulfilled, event)
    }.to have_enqueued_job(SpreePlunk::TrackEventJob).with(
      integration.id,
      SpreePlunk::EventNames::FULFILLMENT_FULFILLED,
      Spree::Fulfillment.name,
      fulfillment.id,
      fulfillment.owner.email
    )
  end

  it 'skips tracking when the fulfillment no longer has an owner' do
    ownerless_fulfillment = instance_double(Spree::Fulfillment, id: 42, owner: nil)
    event = Spree::Event.new(
      name: 'fulfillment.fulfilled',
      payload: { 'id' => 'ful_test' }
    )

    allow(Spree::Fulfillment).to receive(:find_by_param).and_return(ownerless_fulfillment)

    expect {
      subscriber.send(:handle_fulfillment_fulfilled, event)
    }.not_to have_enqueued_job(SpreePlunk::TrackEventJob)
  end
end
