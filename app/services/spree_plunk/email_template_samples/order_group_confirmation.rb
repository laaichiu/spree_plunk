module SpreePlunk
  module EmailTemplateSamples
    class OrderGroupConfirmation < Base
      def variables
        {
          order_group: {
            number: 'R123456789',
            customer_name: 'Jane Doe',
            email: 'jane@example.com',
            currency: currency,
            completed_at: Time.current.iso8601,
            po_number: 'PO-1001',
            order_count: 2,
            item_total: 72.0,
            discount_total: 0.0,
            delivery_total: 8.0,
            tax_total: 6.4,
            additional_tax_total: 6.4,
            included_tax_total: 0.0,
            gift_card_total: 0.0,
            fee_total: 0.0,
            store_credit_total: 0.0,
            total_minus_store_credits: 86.4,
            amount_due: 0.0,
            total: 86.4,
            payments: [],
            promotion_discounts: [],
            manual_discounts: [],
            fee_lines: [],
            delivery_lines: [{ label: 'Standard delivery', amount: 8.0 }],
            unfulfilled_items: [],
            items: [
              { id: 'li_preview_1', variant_id: 'variant_preview_1', currency: currency, name: 'Everyday T-shirt', slug: 'everyday-t-shirt', quantity: 2, price: 24.0, total: 48.0, amount: 48.0, options_text: 'Navy / M', option_values: [], url: 'https://shop.example.com/products/everyday-t-shirt', sku: 'TSHIRT-NAVY-M' },
              { id: 'li_preview_2', variant_id: 'variant_preview_2', currency: currency, name: 'Canvas Tote', slug: 'canvas-tote', quantity: 1, price: 24.0, total: 24.0, amount: 24.0, options_text: 'Natural', option_values: [], url: 'https://shop.example.com/products/canvas-tote', sku: 'TOTE-NATURAL' }
            ],
            fulfillment_groups: [
              {
                name: 'Standard delivery',
                unpriced: false,
                cost: 8.0,
                seller_names: ['Example Seller'],
                items: [
                  { id: 'li_preview_3', variant_id: 'variant_preview_3', currency: currency, name: 'Canvas Tote', slug: 'canvas-tote', quantity: 1, price: 24.0, total: 24.0, amount: 24.0, options_text: 'Natural', option_values: [], url: 'https://shop.example.com/products/canvas-tote', sku: 'TOTE-NATURAL' }
                ]
              }
            ]
          },
          resend: false
        }
      end
    end
  end
end
