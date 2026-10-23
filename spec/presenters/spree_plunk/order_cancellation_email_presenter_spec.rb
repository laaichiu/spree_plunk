require 'spec_helper'

RSpec.describe SpreePlunk::OrderCancellationEmailPresenter do
  it 'builds a Plunk order cancellation payload' do
    store = create(:store, name: 'Example Store', code: 'example-store', mail_from_address: 'orders@example.com')
    integration = build(:plunk_integration, store: store, preferred_order_cancellation_template_id: 'tpl_cancel')
    user = create(:customer, email: 'buyer@example.com')
    order = create(:completed_order_with_totals, store: store, customer: user, email: user.email, canceled_at: Time.utc(2026, 5, 25, 8, 0, 0))

    payload = described_class.new(plunk_integration: integration, resource: order).call

    aggregate_failures do
      expect(payload[:to]).to eq('buyer@example.com')
      expect(payload[:template]).to eq('tpl_cancel')
      expect(payload[:data]).to include(
        email_type: non_persistent_plunk_value(SpreePlunk::TransactionalEmailTypes::ORDER_CANCELLATION),
        store_name: non_persistent_plunk_value('Example Store'),
        order_number: non_persistent_plunk_value(order.number),
        canceled_at: non_persistent_plunk_value('2026-05-25T08:00:00Z'),
        recipient_email: non_persistent_plunk_value('buyer@example.com')
      )
      expect(plunk_data_value(payload[:data], :line_items_text)).to include(order.line_items.first.name)
      expect(plunk_data_value(payload[:data], :totals_html)).to include('<table')
      expect(payload.dig(:headers, 'X-Spree-Plunk-Email-Type')).to eq(SpreePlunk::TransactionalEmailTypes::ORDER_CANCELLATION)
    end
  end
end
