require 'spec_helper'

RSpec.describe SpreePlunk::ContactSubscriber do
  include ActiveJob::TestHelper

  let(:store) { create(:store) }
  let(:integration) { create(:plunk_integration, store: store) }
  let(:subscriber) { described_class.new }
  let(:customer) { create(:customer_with_addresses, email: 'buyer@example.com') }

  before do
    integration
    allow(Spree::Store).to receive(:default).and_return(store)
    clear_enqueued_jobs
  end

  it 'runs synchronously so contact sync only needs the Plunk job queue' do
    expect(described_class.subscription_options).to eq(async: false)
  end

  it 'enqueues contact upsert for customer creation' do
    event = Spree::Event.new(
      name: 'user.created',
      store_id: store.id,
      payload: { 'id' => customer.to_param }
    )

    expect {
      subscriber.send(:handle_customer_event, event)
    }.to have_enqueued_job(SpreePlunk::UpsertContactJob).with(
      integration.id,
      Spree.customer_class.name,
      customer.id
    )
  end

  it 'refreshes contacts in the current and subscribed stores after an address change' do
    other_store = create(:store)
    other_integration = create(:plunk_integration, store: other_store)
    create(:newsletter_subscriber, :verified, email: customer.email, customer: customer, store: other_store)
    event = Spree::Event.new(
      name: 'spree_plunk.customer_address_changed',
      store_id: store.id,
      payload: { 'customer_id' => customer.to_param }
    )

    expect {
      subscriber.send(:handle_customer_address_changed, event)
    }.to have_enqueued_job(SpreePlunk::UpsertContactJob).with(
      integration.id,
      Spree.customer_class.name,
      customer.id
    ).and have_enqueued_job(SpreePlunk::UpsertContactJob).with(
      other_integration.id,
      Spree.customer_class.name,
      customer.id
    )
  end

  it 'removes every store newsletter subscription when the customer email changes' do
    other_store = create(:store)
    other_integration = create(:plunk_integration, store: other_store)
    other_subscriber = create(
      :newsletter_subscriber,
      :verified,
      email: 'old@example.com',
      customer: customer,
      store: other_store
    )
    local_subscriber = create(
      :newsletter_subscriber,
      :verified,
      email: 'old@example.com',
      customer: customer,
      store: store
    )
    event = Spree::Event.new(
      name: SpreePlunk::InternalEventNames::CUSTOMER_EMAIL_CHANGED,
      store_id: store.id,
      payload: { 'customer_id' => customer.to_param, 'store_id' => store.to_param }
    )
    clear_enqueued_jobs

    Spree::Events.reset!
    Spree::Events.activate!

    expect {
      SpreePlunk::EventContext.with_customer_email_change(
        customer_id: customer.id,
        previous_email: 'old@example.com'
      ) do
        subscriber.send(:handle_customer_email_changed, event)
      end
    }.to change { Spree::NewsletterSubscriber.where(customer_id: customer.id).count }.from(2).to(0)

    aggregate_failures do
      expect(Spree::NewsletterSubscriber.exists?(local_subscriber.id)).to be(false)
      expect(Spree::NewsletterSubscriber.exists?(other_subscriber.id)).to be(false)
      expect(Spree::Events.catalog.find(SpreePlunk::InternalEventNames::CUSTOMER_EMAIL_CHANGED).webhook?).to be(false)
      expect(enqueued_jobs.select { |job| job[:job] == SpreePlunk::UnsubscribeJob }.map { |job| job[:args] }).to contain_exactly(
        [integration.id, 'old@example.com'],
        [other_integration.id, 'old@example.com']
      )
      expect(enqueued_jobs.select { |job| job[:job] == SpreePlunk::UpsertContactJob }.map { |job| job[:args] }).to contain_exactly(
        [integration.id, Spree.customer_class.name, customer.id, nil, false],
        [other_integration.id, Spree.customer_class.name, customer.id, nil, false]
      )
    end
  ensure
    Spree::Events.reset!
  end

  it 'uses the store carried by the private address event payload' do
    other_store = create(:store)
    other_integration = create(:plunk_integration, store: other_store)
    event = Spree::Event.new(
      name: 'spree_plunk.customer_address_changed',
      store_id: store.id,
      payload: { 'customer_id' => customer.to_param, 'store_id' => other_store.to_param }
    )

    expect {
      subscriber.send(:handle_customer_address_changed, event)
    }.to have_enqueued_job(SpreePlunk::UpsertContactJob).with(
      other_integration.id,
      Spree.customer_class.name,
      customer.id
    )
  end

  it 'unsubscribes the previous address for the event store when there is no Spree subscriber row' do
    event = Spree::Event.new(
      name: SpreePlunk::InternalEventNames::CUSTOMER_EMAIL_CHANGED,
      store_id: store.id,
      payload: { 'customer_id' => customer.to_param, 'store_id' => store.to_param }
    )
    clear_enqueued_jobs

    SpreePlunk::EventContext.with_customer_email_change(
      customer_id: customer.id,
      previous_email: 'old@example.com'
    ) do
      subscriber.send(:handle_customer_email_changed, event)
    end

    expect(enqueued_jobs.select { |job| job[:job] == SpreePlunk::UnsubscribeJob }.map { |job| job[:args] }).to eq(
      [[integration.id, 'old@example.com']]
    )
  end

  it 'syncs global marketing consent changes to every store with a newsletter subscription' do
    other_store = create(:store)
    other_integration = create(:plunk_integration, store: other_store)
    create(:newsletter_subscriber, :verified, email: customer.email, customer: customer, store: other_store)
    event = Spree::Event.new(
      name: SpreePlunk::InternalEventNames::CUSTOMER_MARKETING_CONSENT_CHANGED,
      store_id: store.id,
      payload: {
        'customer_id' => customer.to_param,
        'accepts_email_marketing' => false,
        'email_changed' => false
      }
    )

    expect {
      subscriber.send(:handle_customer_marketing_consent_changed, event)
    }.to have_enqueued_job(SpreePlunk::UpsertContactJob).with(
      other_integration.id,
      Spree.customer_class.name,
      customer.id,
      nil,
      false
    )
  end

  it 'does not enqueue when the Plunk integration is inactive' do
    integration.update!(active: false)
    event = Spree::Event.new(name: 'user.created', store_id: store.id, payload: { 'id' => customer.to_param })

    expect {
      subscriber.send(:handle_customer_event, event)
    }.not_to have_enqueued_job(SpreePlunk::UpsertContactJob)
  end
end
