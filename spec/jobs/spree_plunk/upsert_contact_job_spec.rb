require 'spec_helper'

RSpec.describe SpreePlunk::UpsertContactJob, type: :job do
  let(:store) { create(:store) }
  let(:integration) { create(:plunk_integration, store: store) }

  it 'reloads newsletter subscribers before delegating to contact upsert' do
    subscriber = create(:newsletter_subscriber, :verified, email: 'newsletter@example.com')

    expect(SpreePlunk::UpsertContact).to receive(:call).with(
      plunk_integration: integration,
      subscriber: subscriber,
      subscribed: nil
    )

    described_class.perform_now(integration.id, Spree::NewsletterSubscriber.name, subscriber.id)
  end

  it 'sends the store-scoped Spree subscription state for customer upserts' do
    user = create(:customer_with_addresses, email: 'user@example.com')
    address = user.bill_address || user.ship_address
    create(:newsletter_subscriber, :verified, email: user.email, customer: user, store: store)
    user.update!(accepts_email_marketing: true)

    expect(SpreePlunk::UpsertContact).to receive(:call).with(
      plunk_integration: integration,
      customer: user,
      address: address,
      subscribed: true
    )

    described_class.perform_now(integration.id, Spree.customer_class.name, user.id, address.id)
  end

  it 'never subscribes a customer without a verified subscriber for the integration store' do
    user = create(:customer, email: 'user@example.com', accepts_email_marketing: true)

    expect(SpreePlunk::UpsertContact).to receive(:call).with(
      plunk_integration: integration,
      customer: user,
      address: nil,
      subscribed: false
    )

    described_class.perform_now(integration.id, Spree.customer_class.name, user.id)
  end

  it 'does not use a verified subscription from a different store' do
    other_store = create(:store)
    user = create(:customer, email: 'user@example.com', accepts_email_marketing: true)
    create(:newsletter_subscriber, :verified, email: user.email, customer: user, store: other_store)

    expect(SpreePlunk::UpsertContact).to receive(:call).with(
      plunk_integration: integration,
      customer: user,
      address: nil,
      subscribed: false
    )

    described_class.perform_now(integration.id, Spree.customer_class.name, user.id)
  end

  it 'skips work when the integration has been removed' do
    user = create(:customer, email: 'user@example.com')

    expect(SpreePlunk::UpsertContact).not_to receive(:call)

    described_class.perform_now(-1, Spree.customer_class.name, user.id)
  end
end
