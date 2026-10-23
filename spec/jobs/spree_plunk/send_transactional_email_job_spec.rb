require 'spec_helper'

RSpec.describe SpreePlunk::SendTransactionalEmailJob, type: :job do
  let(:store) { create(:store) }
  let(:integration) { create(:plunk_integration, store: store) }

  it 'passes event payloads through for password reset sends' do
    payload = {
      'email' => 'buyer@example.com',
      'reset_token' => 'reset-token'
    }

    job = described_class.new(
      integration.id,
      SpreePlunk::TransactionalEmailTypes::PASSWORD_RESET,
      nil,
      nil,
      'buyer@example.com',
      payload
    )

    expect(SpreePlunk::SendTransactionalEmail).to receive(:call).with(
      plunk_integration: integration,
      email_type: SpreePlunk::TransactionalEmailTypes::PASSWORD_RESET,
      resource: nil,
      email: 'buyer@example.com',
      event_payload: payload,
      idempotency_key: job.job_id
    ).and_return(Spree::ServiceModule::Result.new(true, { 'id' => 'email_123' }))

    job.perform_now
  end

  it 'reloads order resources before delegating to the send service' do
    order = create(:completed_order_with_totals, store: store, email: 'buyer@example.com')

    job = described_class.new(
      integration.id,
      SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND,
      Spree::Order.name,
      order.id,
      'buyer@example.com',
      { 'id' => order.to_param }
    )

    expect(SpreePlunk::SendTransactionalEmail).to receive(:call).with(
      plunk_integration: integration,
      email_type: SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND,
      resource: order,
      email: 'buyer@example.com',
      event_payload: { 'id' => order.to_param },
      idempotency_key: job.job_id
    ).and_return(Spree::ServiceModule::Result.new(true, { 'id' => 'email_123' }))

    job.perform_now
  end

  it 'does not send a queued email after the integration is deactivated' do
    integration.update!(active: false)
    job = described_class.new(
      integration.id,
      SpreePlunk::TransactionalEmailTypes::PASSWORD_RESET,
      nil,
      nil,
      'buyer@example.com',
      { 'email' => 'buyer@example.com', 'reset_token' => 'reset-token' }
    )

    expect(SpreePlunk::SendTransactionalEmail).not_to receive(:call)

    expect { job.perform_now }.not_to raise_error
  end
end
