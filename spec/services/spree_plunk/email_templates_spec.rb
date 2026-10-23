require 'spec_helper'

RSpec.describe 'SpreePlunk editable email templates' do
  let(:store) { create(:store, default_locale: 'en', default_currency: 'USD') }

  let(:email_keys) do
    %w[
      spree/order_mailer/confirm_email
      spree/order_group_mailer/confirm_email
      spree/order_mailer/cancel_email
      spree/customer_mailer/password_reset_email
      spree/newsletter_mailer/email_confirmation
      spree/fulfillment_mailer/fulfilled_email
      spree/return_mailer/refunded_email
    ]
  end

  it 'registers the Spree 6 customer emails and their shared partials without spree_emails' do
    expect(Spree.editable_email_templates.emails.map(&:key)).to include(*email_keys)
    expect(Spree.editable_email_templates['layouts/spree/base_mailer']&.kind).to eq(:layout)
    expect(%w[line_item order_summary purchase_totals fulfillment_group summary_row]).to all(satisfy { |name|
      expect(Spree.editable_email_templates["spree/shared/#{name}"]&.kind).to eq(:partial)
    })
  end

  it 'previews every registered customer email using its bundled sample and view dependencies' do
    email_keys.each do |key|
      rendered = Spree::EmailTemplates::Preview.new(store: store, key: key).call

      expect(rendered.subject).to be_present, "expected #{key} to render a subject"
      expect(rendered.html).to include('<html'), "expected #{key} to render through the Spree email layout"
    end
  end
end
