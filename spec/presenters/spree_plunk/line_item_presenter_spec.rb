require 'spec_helper'

RSpec.describe SpreePlunk::LineItemPresenter do
  let(:store) { create(:store, code: 'default-store') }

  it 'builds cart event data from a line item' do
    user = create(:customer, email: 'buyer@example.com')
    order = create(:order, store: store, customer: user, email: user.email)
    product = create(:product, store: store)
    line_item = create(:line_item, order: order, product: product, quantity: 2, price: 19.99, currency: 'USD')

    payload = described_class.new(line_item: line_item, store: store).call

    expect(payload).to include(
      line_item_id: line_item.prefixed_id,
      order_id: order.prefixed_id,
      order_number: order.number,
      store_code: 'default-store',
      email: 'buyer@example.com',
      quantity: 2,
      unit_price: 19.99,
      line_item_total: 39.98,
      currency: 'USD',
      variant_id: line_item.variant.prefixed_id,
      preorder: line_item.variant.preorder?,
      product_id: product.prefixed_id,
      product_name: product.name,
      slug: product.slug,
      adjustment_total: line_item.adjustment_total.to_f,
      additional_tax_total: line_item.additional_tax_total.to_f,
      included_tax_total: line_item.included_tax_total.to_f,
      discount_total: line_item.discount_total.to_f,
      pre_tax_amount: line_item.pre_tax_amount.to_f,
      discounted_amount: line_item.discounted_amount.to_f,
      sku: line_item.sku
    )
  end

  it 'builds cart event data from a line-item payload snapshot' do
    payload = {
      'line_item_id' => 'li_123',
      'order_id' => 'or_123',
      'order_number' => 'R123456',
      'store_code' => 'default-store',
      'email' => 'buyer@example.com',
      'quantity' => 2,
      'unit_price' => 19.99,
      'line_item_total' => 39.98,
      'currency' => 'USD',
      'variant_id' => 'variant_123',
      'product_id' => 'product_123',
      'product_name' => 'Product 1',
      'sku' => 'SKU-1'
    }

    result = described_class.new(line_item: payload, store: store).call

    expect(result).to include(
      line_item_id: 'li_123',
      order_id: 'or_123',
      order_number: 'R123456',
      store_code: 'default-store',
      email: 'buyer@example.com',
      quantity: 2,
      unit_price: 19.99,
      line_item_total: 39.98,
      currency: 'USD',
      variant_id: 'variant_123',
      product_id: 'product_123',
      product_name: 'Product 1',
      sku: 'SKU-1'
    )
  end
end
