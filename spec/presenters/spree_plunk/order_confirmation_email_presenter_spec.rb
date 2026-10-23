require 'spec_helper'

RSpec.describe SpreePlunk::OrderConfirmationEmailPresenter do
  it 'builds a Plunk order confirmation payload' do
    store = create(:store, name: 'Example Store', code: 'example-store', mail_from_address: 'orders@example.com')
    integration = build(:plunk_integration, store: store, preferred_order_confirmation_template_id: 'tpl_order')
    user = create(:customer, email: 'buyer@example.com')
    order = create(:completed_order_with_totals, store: store, customer: user, email: user.email)

    payload = described_class.new(plunk_integration: integration, resource: order).call

    aggregate_failures do
      expect(payload[:to]).to eq('buyer@example.com')
      expect(payload[:template]).to eq('tpl_order')
      expect(payload[:data]).to include(
        email_type: non_persistent_plunk_value(SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION),
        store_name: non_persistent_plunk_value('Example Store'),
        store_code: non_persistent_plunk_value('example-store'),
        order_number: non_persistent_plunk_value(order.number),
        recipient_email: non_persistent_plunk_value('buyer@example.com')
      )
      expect(plunk_data_value(payload[:data], :line_items)).to contain_exactly(hash_including(product_name: order.line_items.first.name))
      expect(plunk_data_value(payload[:data], :line_items_html)).to include('<table')
      expect(plunk_data_value(payload[:data], :totals_text)).to include('Total:')
      expect(plunk_data_value(payload[:data], :shipping_address_text)).to include('New York')
      expect(payload.dig(:headers, 'X-Spree-Plunk-Email-Type')).to eq(SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION)
    end
  end
end
