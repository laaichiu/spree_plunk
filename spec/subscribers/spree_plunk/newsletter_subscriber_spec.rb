require 'spec_helper'

RSpec.describe SpreePlunk::NewsletterSubscriber do
  include ActiveJob::TestHelper

  let(:store) { create(:store) }
  let(:integration) { create(:plunk_integration, store: store) }
  let(:subscriber) { described_class.new }

  before do
    integration
    allow(Spree::Store).to receive(:default).and_return(store)
    clear_enqueued_jobs
  end

  it 'runs synchronously so newsletter sync only needs the Plunk job queue' do
    expect(described_class.subscription_options).to eq(async: false)
  end

  it 'enqueues subscribe and event tracking when a subscriber is verified' do
    newsletter_subscriber = create(:newsletter_subscriber, :verified, email: 'newsletter@example.com')
    event = Spree::Event.new(
      name: 'newsletter_subscriber.verified',
      payload: { 'id' => newsletter_subscriber.to_param }
    )

    expect {
      subscriber.send(:handle_subscriber_verified, event)
    }.to have_enqueued_job(SpreePlunk::SubscribeJob).with(integration.id, newsletter_subscriber.id)

    expect(SpreePlunk::TrackEventJob).to have_been_enqueued.with(
      integration.id,
      SpreePlunk::EventNames::NEWSLETTER_SUBSCRIBED,
      Spree::NewsletterSubscriber.name,
      newsletter_subscriber.id,
      'newsletter@example.com'
    )
  end

  it 'does not queue a verified event for a subscriber that is no longer verified' do
    newsletter_subscriber = create(:newsletter_subscriber, email: 'newsletter@example.com')
    event = Spree::Event.new(
      name: 'newsletter_subscriber.verified',
      payload: { 'id' => newsletter_subscriber.to_param }
    )

    expect {
      subscriber.send(:handle_subscriber_verified, event)
    }.not_to have_enqueued_job(SpreePlunk::SubscribeJob)
  end

  it 'enqueues unsubscribe and event tracking when a subscriber is deleted' do
    payload = {
      'email' => 'newsletter@example.com',
      'verified' => true,
      'verified_at' => '2026-05-18T10:00:00Z'
    }
    event = Spree::Event.new(
      name: 'newsletter_subscriber.deleted',
      payload: payload
    )

    expect {
      subscriber.send(:handle_subscriber_deletion, event)
    }.to have_enqueued_job(SpreePlunk::UnsubscribeJob).with(integration.id, 'newsletter@example.com')

    expect(SpreePlunk::TrackEventJob).to have_been_enqueued.with(
      integration.id,
      SpreePlunk::EventNames::NEWSLETTER_UNSUBSCRIBED,
      nil,
      nil,
      'newsletter@example.com',
      payload
    )
  end

  it 'does not send another store subscription to the default store integration' do
    other_store = create(:store)
    newsletter_subscriber = create(:newsletter_subscriber, :verified, store: other_store)
    event = Spree::Event.new(
      name: 'newsletter_subscriber.verified',
      store_id: other_store.id,
      payload: { 'id' => newsletter_subscriber.to_param }
    )

    expect {
      subscriber.send(:handle_subscriber_verified, event)
    }.not_to have_enqueued_job(SpreePlunk::SubscribeJob)
  end
end
