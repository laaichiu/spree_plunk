require 'spec_helper'

RSpec.describe SpreePlunk::ReturnRefundedEmailPresenter do
  it 'builds a Plunk return payload' do
    store = create(:store, name: 'Example Store', code: 'example-store', mail_from_address: 'orders@example.com')
    integration = build(:plunk_integration, store: store, preferred_return_refunded_template_id: 'tpl_return')
    customer = create(:customer, email: 'buyer@example.com')
    order = create_fulfilled_order(store: store, customer: customer)
    return_record = create(:return, store: store, order: order, stock_location: order.fulfillments.first.stock_location)

    payload = described_class.new(plunk_integration: integration, resource: return_record).call

    aggregate_failures do
      expect(payload[:to]).to eq('buyer@example.com')
      expect(payload[:template]).to eq('tpl_return')
      expect(payload[:data][:email_type]).to eq(non_persistent_plunk_value(SpreePlunk::TransactionalEmailTypes::RETURN_REFUNDED))
      expect(plunk_data_value(payload[:data], :store_name)).to eq('Example Store')
      expect(plunk_data_value(payload[:data], :return_number)).to eq(return_record.number)
      expect(plunk_data_value(payload[:data], :refunded_total)).to be_present
      expect(plunk_data_value(payload[:data], :order_number)).to eq(return_record.order.number)
      expect(plunk_data_value(payload[:data], :recipient_email)).to eq('buyer@example.com')
      expect(plunk_data_value(payload[:data], :refunded_total_display)).to be_present
      expect(plunk_data_value(payload[:data], :return_items)).not_to be_empty
      expect(plunk_data_value(payload[:data], :return_items_html)).to include('<table')
      expect(plunk_data_value(payload[:data], :return_items_text)).to include('x ')
      expect(plunk_data_value(payload[:data], :reimbursement_number)).to be_nil
      expect(payload.dig(:headers, 'X-Spree-Plunk-Email-Type')).to eq(SpreePlunk::TransactionalEmailTypes::RETURN_REFUNDED)
    end
  end
end
