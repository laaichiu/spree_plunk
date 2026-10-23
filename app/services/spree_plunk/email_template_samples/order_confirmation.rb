module SpreePlunk
  module EmailTemplateSamples
    class OrderConfirmation < Base
      def variables
        { order: order, resend: false }
      end

      private

      def order
        {
          number: 'R123456789',
          customer_name: 'Jane Doe',
          email: 'jane@example.com',
          currency: currency,
          status: 'placed',
          payment_status: 'paid',
          item_total: 48.0,
          discount_total: 0.0,
          delivery_total: 6.0,
          tax_total: 4.32,
          additional_tax_total: 4.32,
          included_tax_total: 0.0,
          gift_card_total: 0.0,
          store_credit_total: 0.0,
          fee_total: 0.0,
          total_minus_store_credits: 58.32,
          amount_due: 0.0,
          po_number: nil,
          promotion_discounts: [],
          manual_discounts: [],
          fee_lines: [],
          delivery_lines: [{ label: 'Standard delivery', amount: 6.0 }],
          billing_address: {
            first_name: 'Jane', last_name: 'Doe', full_name: 'Jane Doe',
            address1: '123 Example Street', postal_code: '10001', city: 'New York',
            country_name: 'United States', country_code: 'US', state_name: 'New York'
          },
          shipping_address: {
            first_name: 'Jane', last_name: 'Doe', full_name: 'Jane Doe',
            address1: '123 Example Street', postal_code: '10001', city: 'New York',
            country_name: 'United States', country_code: 'US', state_name: 'New York'
          },
          fulfillment_groups: [],
          unfulfilled_items: [],
          payments: [],
          discounts: [],
          fees: [],
          total: 58.32,
          items: [
            { id: 'li_preview', variant_id: 'variant_preview', currency: currency, name: 'Everyday T-shirt', slug: 'everyday-t-shirt', quantity: 2, price: 24.0, total: 48.0, amount: 48.0, options_text: 'Navy / M', option_values: [], url: 'https://shop.example.com/products/everyday-t-shirt', image_url: nil, sku: 'TSHIRT-NAVY-M' }
          ]
        }
      end
    end
  end
end
