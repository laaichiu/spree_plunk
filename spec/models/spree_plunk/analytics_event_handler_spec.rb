require 'spec_helper'

RSpec.describe SpreePlunk::AnalyticsEventHandler do
  include ActiveJob::TestHelper

  let(:store) { create(:store) }
  let(:user) { create(:customer, email: 'handler-customer@example.com') }
  let(:order) { create(:order, customer: user, store: store, email: 'order@example.com') }
  let!(:plunk_integration) { create(:plunk_integration, store: store, active: true) }

  subject(:handler) { described_class.new(customer: user, store: store) }

  before do
    clear_enqueued_jobs
  end

  it 'keeps its storefront context' do
    expect(handler.store).to eq(store)
    expect(handler.customer).to eq(user)
  end

  it 'ignores checkout events because they are sourced from server-side services' do
    expect {
      handler.handle_event('checkout_email_entered', { order: order, email: 'checkout@example.com' })
    }.not_to have_enqueued_job(SpreePlunk::TrackEventJob)
  end

  it 'ignores coupon events because they are sourced from the coupon handler lifecycle' do
    expect {
      handler.handle_event('coupon_applied', { order: order })
    }.not_to have_enqueued_job(SpreePlunk::TrackEventJob)
  end

  it 'ignores checkout step events because they are sourced from checkout services' do
    expect {
      handler.handle_event('checkout_step_completed', { order: order })
    }.not_to have_enqueued_job(SpreePlunk::TrackEventJob)
  end

  it 'returns early when the primary event resource is missing' do
    expect {
      handler.handle_event('coupon_applied', {})
    }.not_to have_enqueued_job(SpreePlunk::TrackEventJob)
  end

  it 'returns early when no email can be resolved' do
    order.update!(email: nil)
    email_free_handler = described_class.new(customer: nil, store: store)

    expect {
      email_free_handler.handle_event('coupon_denied', { order: order })
    }.not_to have_enqueued_job(SpreePlunk::TrackEventJob)
  end

  it 'returns early when no active Plunk integration is available' do
    plunk_integration.update!(active: false)

    expect {
      handler.handle_event('coupon_applied', { order: order })
    }.not_to have_enqueued_job(SpreePlunk::TrackEventJob)
  end
end
