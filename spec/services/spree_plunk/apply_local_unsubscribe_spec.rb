require 'spec_helper'

RSpec.describe SpreePlunk::ApplyLocalUnsubscribe do
  before do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it 'removes the matching newsletter subscriber and clears customer marketing without re-enqueuing outbound sync jobs' do
    user = create(:customer, email: 'newsletter@example.com', accepts_email_marketing: true)
    subscriber = Spree::NewsletterSubscriber.find_by!(email: user.email)
    clear_enqueued_jobs

    result = nil

    expect {
      result = described_class.call(email: subscriber.email)
    }.to change(Spree::NewsletterSubscriber, :count).by(-1)

    aggregate_failures do
      expect(result).to be_success
      expect(result.value).to include(
        email: 'newsletter@example.com',
        unsubscribed: true,
        subscriber_removed: true,
        customer_updated: true
      )
      expect(user.reload.accepts_email_marketing).to be(false)
      expect(enqueued_jobs.map { |job| job[:job] }).not_to include(
        SpreePlunk::UpsertContactJob,
        SpreePlunk::SubscribeJob,
        SpreePlunk::UnsubscribeJob,
        SpreePlunk::TrackEventJob
      )
    end
  end

  it 'does not change customer consent when this store has no newsletter subscriber row' do
    user = create(:customer, email: 'customer@example.com', accepts_email_marketing: true)
    Spree::NewsletterSubscriber.where(email: user.email).delete_all

    result = described_class.call(email: 'customer@example.com')

    aggregate_failures do
      expect(result).to be_success
      expect(result.value).to include(skipped: true, reason: 'local_email_not_found')
      expect(user.reload.accepts_email_marketing).to be(true)
    end
  end

  it 'acknowledges already-cleared local state for a matching user email' do
    create(:customer, email: 'customer@example.com', accepts_email_marketing: false)

    result = described_class.call(email: 'customer@example.com')

    expect(result.value).to include(skipped: true, reason: 'local_email_not_found')
  end

  it 'no-ops when no local subscriber or user matches the email' do
    result = described_class.call(email: 'missing@example.com')

    expect(result.value).to include(skipped: true, reason: 'local_email_not_found')
  end

  it 'only removes this store subscription and preserves consent while another store subscription remains' do
    store = create(:store)
    other_store = create(:store)
    user = create(:customer, email: 'multi-store@example.com')
    local_subscriber = create(:newsletter_subscriber, :verified, customer: user, email: user.email, store: store)
    other_subscriber = create(:newsletter_subscriber, :verified, customer: user, email: user.email, store: other_store)
    user.update_column(:accepts_email_marketing, true)

    result = described_class.call(email: user.email, store: store)

    aggregate_failures do
      expect(result).to be_success
      expect(Spree::NewsletterSubscriber.exists?(local_subscriber.id)).to be(false)
      expect(other_subscriber.reload).to be_present
      expect(user.reload.accepts_email_marketing).to be(true)
    end
  end
end
