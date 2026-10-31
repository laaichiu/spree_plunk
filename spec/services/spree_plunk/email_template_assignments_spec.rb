require 'spec_helper'

RSpec.describe SpreePlunk::EmailTemplateAssignments do
  describe '.call' do
    it 'maps order data to the Spree 6 purchase and line-item assignment contract' do
      order = create(:completed_order_with_totals, store: create(:store), email: 'buyer@example.com')
      line_item = order.line_items.first
      payload = {
        to: 'buyer@example.com',
        data: {
          order_number: wrapped('R123456'),
          customer_name: wrapped('Jane Doe'),
          customer_email: wrapped('buyer@example.com'),
          currency: wrapped('USD'),
          order_total_amount: wrapped('58.32'),
          line_items: wrapped([
            {
              line_item_id: line_item.prefixed_id,
              variant_id: line_item.variant.prefixed_id,
              product_name: line_item.product.name,
              quantity: 2,
              unit_price: 24.0,
              line_item_total: 48.0,
              variant_options_text: 'Navy / M',
              url: 'https://shop.example.com/products/everyday-t-shirt',
              image_url: 'https://cdn.example.com/t-shirt.jpg'
            }
          ])
        }
      }

      assignments = described_class.call(
        email_type: SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION,
        payload: payload,
        resource: order
      )

      expect(assignments[:order]).to include(
        number: 'R123456',
        customer_name: 'Jane Doe',
        email: 'buyer@example.com',
        currency: 'USD',
        total: '58.32',
        total_minus_store_credits: order.total_minus_store_credits,
        additional_tax_total: order.additional_tax_total,
        items: [hash_including(
          id: line_item.prefixed_id,
          variant_id: line_item.variant.prefixed_id,
          name: line_item.product.name,
          quantity: 2,
          price: 24.0,
          total: 48.0,
          amount: 48.0,
          options_text: 'Navy / M',
          url: 'https://shop.example.com/products/everyday-t-shirt',
          image_url: 'https://cdn.example.com/t-shirt.jpg'
        )],
        promotion_discounts: [],
        manual_discounts: [],
        fee_lines: []
      )
      expect(assignments.dig(:order, :delivery_lines)).not_to be_empty
      expect(assignments.dig(:order, :delivery_lines)).to all(include(:label, :amount))
    end

    it 'maps fulfillment manifest items using the Spree 6 manifest_items key' do
      order = create_fulfilled_order(store: create(:store), customer: create(:customer, email: 'buyer@example.com'))
      fulfillment = order.fulfillments.first
      item_data = SpreePlunk::FulfillmentFulfilledEmailPresenter.new(
        plunk_integration: create(:plunk_integration, store: order.store),
        resource: fulfillment,
        email: 'buyer@example.com'
      ).call

      assignments = described_class.call(
        email_type: SpreePlunk::TransactionalEmailTypes::FULFILLMENT_FULFILLED,
        payload: item_data,
        resource: fulfillment
      )

      expect(assignments.dig(:fulfillment, :manifest_items)).not_to be_empty
      expect(assignments.dig(:fulfillment, :manifest_items).first).to include(:id, :name, :quantity, :price, :amount)
      expect(assignments.dig(:fulfillment, :items).first).to include(:item_id, :variant_id, :quantity)
    end

    it 'fills the split-checkout purchase fields used by Spree 6 templates' do
      user = create(:customer, email: 'buyer@example.com')
      group = create(:order_group, :with_parcels, store: create(:store), customer: user)
      integration = create(:plunk_integration, store: group.store)
      payload = SpreePlunk::OrderGroupConfirmationEmailPresenter.new(
        plunk_integration: integration,
        resource: group,
        email: user.email,
        email_type: SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION
      ).call

      assignments = described_class.call(
        email_type: SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION,
        payload: payload,
        resource: group
      )
      order_group = assignments[:order_group]

      expect(order_group).to include(
        number: group.number,
        email: user.email,
        currency: group.currency,
        order_count: group.orders.size,
        total_minus_store_credits: group.total_minus_store_credits,
        items: all(include(:id, :variant_id, :name, :quantity, :amount, :url, :image_url)),
        fulfillment_groups: all(include(:name, :unpriced, :cost, :seller_names, :items)),
        unfulfilled_items: be_a(Array),
        delivery_lines: all(include(:label, :amount))
      )
    end

    it 'maps digital download, invitation, privacy, and payment-link assignments to Spree email variables' do
      order = create(:order_with_line_items, store: create(:store), email: 'buyer@example.com')
      downloads = [{ filename: 'manual.pdf', url: 'https://shop.example.com/download/token', expires_at: '2026-11-30T12:00:00Z' }]
      base_data = {
        order_number: wrapped('R123'),
        customer_name: wrapped('Jane Doe'),
        recipient_email: wrapped('buyer@example.com'),
        downloads: wrapped(downloads),
        resend: wrapped(false),
        company: wrapped({ name: 'Example Company' }),
        accept_url: wrapped('https://shop.example.com/account/company-invitation?token=invite'),
        kind: wrapped('access'),
        confirmation_url: wrapped('https://shop.example.com/data-request?token=confirm'),
        expires_at: wrapped('2026-11-30T12:00:00Z'),
        download_url: wrapped('https://shop.example.com/data-export?token=download'),
        payment_url: wrapped("https://shop.example.com/checkout/#{order.token}/payment")
      }

      assignments_for = lambda do |email_type|
        described_class.call(email_type: email_type, payload: { to: 'buyer@example.com', data: base_data }, resource: order)
      end

      expect(assignments_for.call(SpreePlunk::TransactionalEmailTypes::DIGITAL_ASSET_READY)).to include(
        downloads: downloads,
        resend: false
      )
      expect(assignments_for.call(SpreePlunk::TransactionalEmailTypes::COMPANY_INVITATION)).to include(
        company: { name: 'Example Company' },
        accept_url: 'https://shop.example.com/account/company-invitation?token=invite'
      )
      expect(assignments_for.call(SpreePlunk::TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION)).to include(
        kind: 'access',
        confirmation_url: 'https://shop.example.com/data-request?token=confirm'
      )
      expect(assignments_for.call(SpreePlunk::TransactionalEmailTypes::DATA_EXPORT_READY)).to include(
        download_url: 'https://shop.example.com/data-export?token=download'
      )
      expect(assignments_for.call(SpreePlunk::TransactionalEmailTypes::PAYMENT_LINK)).to include(
        payment_url: "https://shop.example.com/checkout/#{order.token}/payment",
        order: include(number: 'R123', email: 'buyer@example.com')
      )
    end

    it 'maps return item and refund fields to the current Spree 6 names' do
      order = create_fulfilled_order(store: create(:store), customer: create(:customer, email: 'buyer@example.com'))
      return_record = create(:return, order: order, stock_location: order.fulfillments.first.stock_location, status: 'refunded')
      payload = {
        to: order.email,
        data: {
          return_id: wrapped(return_record.prefixed_id),
          return_number: wrapped(return_record.number),
          return_status: wrapped('refunded'),
          refund_total: wrapped('19.99'),
          refunded_total: wrapped('19.99'),
          return_items: wrapped([{ line_item_id: 'li_123', product_name: 'T-shirt', quantity: 1, line_item_total: '19.99' }])
        }
      }

      assignments = described_class.call(
        email_type: SpreePlunk::TransactionalEmailTypes::RETURN_REFUNDED,
        payload: payload,
        resource: nil
      )

      expect(assignments[:return]).to include(
        id: return_record.prefixed_id,
        number: return_record.number,
        status: 'refunded',
        refund_total: '19.99',
        refunded_total: '19.99',
        returned_items: [hash_including(id: 'li_123', name: 'T-shirt', amount: '19.99')]
      )
    end
  end

  def wrapped(value)
    { value: value, persistent: false }
  end
end
