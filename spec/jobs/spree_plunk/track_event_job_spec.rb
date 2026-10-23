require 'spec_helper'

RSpec.describe SpreePlunk::TrackEventJob, type: :job do
  include ActiveJob::TestHelper

  let(:store) { create(:store) }
  let(:integration) { create(:plunk_integration, store: store) }

  before do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it 'reloads fulfilled fulfillments before delegating to event tracking' do
    fulfillment = create_fulfilled_order(store: store, email: 'buyer@example.com').fulfillments.first

    expect(SpreePlunk::TrackEvent).to receive(:call).with(
      plunk_integration: integration,
      event_name: SpreePlunk::EventNames::FULFILLMENT_FULFILLED,
      resource: fulfillment,
      email: fulfillment.owner.email
    ).and_return(Spree::ServiceModule::Result.new(true, { 'id' => 'evt_123' }))

    described_class.perform_now(
      integration.id,
      SpreePlunk::EventNames::FULFILLMENT_FULFILLED,
      Spree::Fulfillment.name,
      fulfillment.id,
      fulfillment.owner.email
    )
  end

  it 'reloads line items before delegating cart tracking' do
    order = create(:order, store: store, email: 'buyer@example.com')
    product = create(:product, store: store)
    line_item = create(:line_item, order: order, product: product, quantity: 2, price: 19.99, currency: 'USD')

    expect(SpreePlunk::TrackEvent).to receive(:call).with(
      plunk_integration: integration,
      event_name: SpreePlunk::EventNames::CART_ADDED,
      resource: line_item,
      email: order.email
    ).and_return(Spree::ServiceModule::Result.new(true, { 'id' => 'evt_123' }))

    described_class.perform_now(
      integration.id,
      SpreePlunk::EventNames::CART_ADDED,
      Spree::LineItem.name,
      line_item.id,
      order.email
    )
  end

  it 'reloads returns before delegating to event tracking' do
    return_record = create(:return)

    expect(SpreePlunk::TrackEvent).to receive(:call).with(
      plunk_integration: integration,
      event_name: SpreePlunk::EventNames::RETURN_REFUNDED,
      resource: return_record,
      email: return_record.order.email
    ).and_return(Spree::ServiceModule::Result.new(true, { 'id' => 'evt_123' }))

    described_class.perform_now(
      integration.id,
      SpreePlunk::EventNames::RETURN_REFUNDED,
      Spree::Return.name,
      return_record.id,
      return_record.order.email
    )
  end

  it 'passes payload snapshots through without reloading a record' do
    payload = {
      'email' => 'newsletter@example.com',
      'verified' => true
    }

    expect(SpreePlunk::TrackEvent).to receive(:call).with(
      plunk_integration: integration,
      event_name: SpreePlunk::EventNames::NEWSLETTER_UNSUBSCRIBED,
      resource: payload,
      email: 'newsletter@example.com'
    ).and_return(Spree::ServiceModule::Result.new(true, { 'id' => 'evt_123' }))

    described_class.perform_now(
      integration.id,
      SpreePlunk::EventNames::NEWSLETTER_UNSUBSCRIBED,
      nil,
      nil,
      'newsletter@example.com',
      payload
    )
  end

  it 're-enqueues retryable sync failures' do
    failure_result = Spree::ServiceModule::Result.new(false, {
      status: 503,
      error_message: 'temporarily unavailable',
      error_code: 'http_503',
      retryable: true
    })

    allow(SpreePlunk::TrackEvent).to receive(:call).and_return(failure_result)

    expect {
      described_class.perform_now(
        integration.id,
        SpreePlunk::EventNames::ORDER_PLACED,
        nil,
        nil,
        'buyer@example.com',
        { 'email' => 'buyer@example.com' }
      )
    }.to have_enqueued_job(described_class)
  end

  it 'discards non-retryable sync failures and reports enriched context' do
    error_reporter = instance_double(ActiveSupport::ErrorReporter, report: nil)
    failure_result = Spree::ServiceModule::Result.new(false, {
      status: 401,
      error_message: 'Invalid API key',
      error_code: 'http_401',
      retryable: false
    })

    allow(Rails).to receive(:error).and_return(error_reporter)
    allow(SpreePlunk::TrackEvent).to receive(:call).and_return(failure_result)

    expect {
      described_class.perform_now(
        integration.id,
        SpreePlunk::EventNames::ORDER_PLACED,
        Spree::Order.name,
        123,
        'buyer@example.com'
      )
    }.not_to have_enqueued_job(described_class)

    expect(error_reporter).to have_received(:report).with(
      instance_of(SpreePlunk::DiscardableSyncError),
      hash_including(
        handled: true,
        source: 'spree.plunk',
        context: hash_including(
          operation: 'track_event',
          integration_id: integration.id,
          store_id: integration.store_id,
          event_name: SpreePlunk::EventNames::ORDER_PLACED,
          resource_type: Spree::Order.name,
          resource_id: 123,
          email_present: true,
          status: 401,
          error_code: 'http_401',
          discarded: true
        )
      )
    )
  end

  it 'reports retry exhaustion after the final retryable attempt' do
    error_reporter = instance_double(ActiveSupport::ErrorReporter, report: nil)
    failure_result = Spree::ServiceModule::Result.new(false, {
      status: 503,
      error_message: 'temporarily unavailable',
      error_code: 'http_503',
      retryable: true
    })

    allow(Rails).to receive(:error).and_return(error_reporter)
    expect(SpreePlunk::TrackEvent).to receive(:call).exactly(5).times.and_return(failure_result)

    perform_enqueued_jobs do
      described_class.perform_later(
        integration.id,
        SpreePlunk::EventNames::ORDER_PLACED,
        nil,
        nil,
        'buyer@example.com',
        { 'email' => 'buyer@example.com' }
      )
    end

    expect(error_reporter).to have_received(:report).with(
      instance_of(SpreePlunk::RetryableSyncError),
      hash_including(
        handled: true,
        source: 'spree.plunk',
        context: hash_including(
          operation: 'track_event',
          integration_id: integration.id,
          store_id: integration.store_id,
          event_name: SpreePlunk::EventNames::ORDER_PLACED,
          email_present: true,
          resource_payload_present: true,
          status: 503,
          error_code: 'http_503',
          retry_exhausted: true,
          discarded: false
        )
      )
    )
  end
end
