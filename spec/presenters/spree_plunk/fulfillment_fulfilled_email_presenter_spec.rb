require 'spec_helper'

RSpec.describe SpreePlunk::FulfillmentFulfilledEmailPresenter do
  it 'builds a Plunk fulfillment fulfilled payload' do
    store = create(:store, name: 'Example Store', code: 'example-store', mail_from_address: 'orders@example.com')
    integration = build(:plunk_integration, store: store, preferred_fulfillment_fulfilled_template_id: 'tpl_fulfillment')
    user = create(:customer, email: 'buyer@example.com')
    fulfillment = create_fulfilled_order(store: store, customer: user).fulfillments.first
    fulfillment.deliveries.first.update!(tracking_number: 'TRACK123')
    fulfillment.update_columns(fulfilled_at: Time.utc(2026, 5, 25, 8, 0, 0))

    payload = described_class.new(plunk_integration: integration, resource: fulfillment).call

    aggregate_failures do
      expect(payload[:to]).to eq('buyer@example.com')
      expect(payload[:template]).to eq('tpl_fulfillment')
      expect(payload[:data][:email_type]).to eq(non_persistent_plunk_value(SpreePlunk::TransactionalEmailTypes::FULFILLMENT_FULFILLED))
      expect(plunk_data_value(payload[:data], :store_name)).to eq('Example Store')
      expect(plunk_data_value(payload[:data], :fulfillment_number)).to eq(fulfillment.number)
      expect(plunk_data_value(payload[:data], :delivery_method_name)).to be_present
      expect(plunk_data_value(payload[:data], :tracking)).to eq('TRACK123')
      expect(plunk_data_value(payload[:data], :fulfilled_at)).to eq('2026-05-25T08:00:00Z')
      expect(plunk_data_value(payload[:data], :recipient_email)).to eq('buyer@example.com')
      expect(plunk_data_value(payload[:data], :fulfillment_items)).not_to be_empty
      expect(plunk_data_value(payload[:data], :fulfillment_items_html)).to include('<table')
      expect(plunk_data_value(payload[:data], :fulfillment_items_text)).to include('x ')
      expect(plunk_data_value(payload[:data], :shipment_number)).to be_nil
      expect(plunk_data_value(payload[:data], :order_total)).to be_present
      expect(payload.dig(:headers, 'X-Spree-Plunk-Email-Type')).to eq(SpreePlunk::TransactionalEmailTypes::FULFILLMENT_FULFILLED)
    end
  end
end
