require 'spec_helper'

RSpec.describe SpreePlunk::UpsertContact do
  subject(:result) { described_class.call(plunk_integration: plunk_integration, customer: user) }

  let(:store) { create(:store, code: 'default-store') }
  let(:service_result) { Spree::ServiceModule::Result.new(true, { 'id' => 'cnt_123' }) }
  let(:lookup_result) do
    Spree::ServiceModule::Result.new(true, { 'found' => ['user@example.com'], 'notFound' => [] })
  end
  let(:plunk_integration) do
    instance_double(
      Spree::Integrations::Plunk,
      store: store,
      lookup_contact: lookup_result,
      upsert_contact: service_result
    )
  end
  let(:user) do
    create(
      :customer_with_addresses,
      email: 'user@example.com',
      accepts_email_marketing: true
    )
  end

  it 'preserves Plunk subscription state during ordinary customer profile sync' do
    allow(plunk_integration).to receive(:upsert_contact).and_return(service_result)

    expect(result).to be_success
    expect(plunk_integration).to have_received(:upsert_contact).with(hash_including(email: 'user@example.com'))
    expect(plunk_integration).to have_received(:upsert_contact).with(hash_not_including(:subscribed))
  end

  context 'when the contact does not yet exist in Plunk' do
    let(:lookup_result) do
      Spree::ServiceModule::Result.new(true, { 'found' => [], 'notFound' => ['user@example.com'] })
    end

    let(:user) do
      create(
        :customer_with_addresses,
        email: 'user@example.com',
        accepts_email_marketing: false
      )
    end

    it 'creates the contact as unsubscribed when no explicit consent state was provided' do
      expect(plunk_integration).to receive(:upsert_contact).with(
        hash_including(email: 'user@example.com', subscribed: false)
      ).and_return(service_result)

      expect(result).to be_success
    end
  end

  context 'when no email can be resolved' do
    let(:user) do
      build(:customer).tap do |record|
        record.email = nil
      end
    end

    it 'returns a noop result' do
      expect(plunk_integration).not_to receive(:upsert_contact)
      expect(result).to be_success
      expect(result.value).to include(skipped: true, reason: 'missing_email')
    end
  end
end
