require 'spec_helper'

RSpec.describe SpreePlunk::Unsubscribe do
  let(:store) { create(:store) }
  let(:service_result) { Spree::ServiceModule::Result.new(true, { accepted: true }) }
  let(:integration) do
    instance_double(Spree::Integrations::Plunk, store: store, unsubscribe_contact: service_result)
  end

  it 'includes customer data when the external email differs only by case' do
    customer = create(:customer, email: 'Ada@Example.com')

    expect(integration).to receive(:unsubscribe_contact).with(
      hash_including(
        email: 'ada@example.com',
        subscribed: false,
        data: hash_including(external_user_id: customer.id)
      )
    ).and_return(service_result)

    result = described_class.call(plunk_integration: integration, email: 'ada@example.com')

    expect(result).to be_success
  end
end
