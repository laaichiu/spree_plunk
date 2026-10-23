module SpreePlunk
  class OrderTransactionalEmailPresenter < TransactionalEmailPresenter
    private

    def resolved_email
      email.presence || resource&.email.presence || resource&.customer&.email
    end

    def order_number
      resource&.number
    end

    def order_data(email_type:)
      return {} unless resource

      non_persistent_data_hash(
        email_type: email_type,
        store_name: store_name,
        store_code: store&.code,
        recipient_email: resolved_email,
        customer_email: customer_email,
        customer_name: customer_name,
        customer_first_name: customer_first_name,
        customer_last_name: customer_last_name,
        order_id: resource.prefixed_id,
        order_number: resource.number,
        status: order_status,
        payment_status: resource.payment_status,
        fulfillment_status: resource.fulfillment_status,
        order_total: display_total,
        order_total_amount: numeric_value { resource.total },
        currency: resource.currency,
        item_total: resource.item_total&.to_f,
        item_total_display: display_money(resource.item_total),
        delivery_total: resource.delivery_total&.to_f,
        delivery_total_display: display_money(resource.delivery_total),
        tax_total: resource.tax_total&.to_f,
        tax_total_display: display_money(resource.tax_total),
        discount_total: resource.discount_total&.to_f,
        discount_total_display: display_money(resource.discount_total),
        gift_card_total: numeric_value { resource.gift_card_total },
        gift_card_total_display: display_money(resource.gift_card_total),
        item_count: item_count,
        line_items_count: resource.line_items.size,
        line_items: line_items_data,
        line_items_text: line_items_text,
        line_items_html: line_items_html,
        totals: totals_data,
        totals_text: totals_text,
        totals_html: totals_html,
        fulfillments: fulfillments_data,
        fulfillments_text: fulfillments_text,
        fulfillments_html: fulfillments_html,
        billing_address: address_data(resource.bill_address),
        billing_address_text: address_text(resource.bill_address),
        shipping_address: address_data(resource.ship_address),
        shipping_address_text: address_text(resource.ship_address),
        completed_at: completed_at&.iso8601,
        canceled_at: (resource.canceled_at if resource.is_a?(::Spree::Order))&.iso8601,
        store_url: storefront_url
      )
    end

    def display_total
      return unless resource
      "#{resource.currency} #{format('%.2f', resource.total.to_f)}"
    end

    def completed_at
      return resource.orders.filter_map(&:completed_at).max if resource.is_a?(::Spree::OrderGroup)

      resource.completed_at
    end

    def order_status
      resource.status if resource.is_a?(::Spree::Order)
    end

    def item_count
      return resource.line_items.sum(&:quantity) if resource.is_a?(::Spree::OrderGroup)

      resource.total_quantity
    end

    def customer_email
      resource&.email.presence || resource&.customer&.email
    end

    def customer_name
      name_from_address.presence || name_from_customer
    end

    def customer_first_name
      resource&.ship_address&.first_name.presence ||
        resource&.bill_address&.first_name.presence ||
        resource&.customer&.first_name
    end

    def customer_last_name
      resource&.ship_address&.last_name.presence ||
        resource&.bill_address&.last_name.presence ||
        resource&.customer&.last_name
    end

    def name_from_address
      address = resource&.ship_address || resource&.bill_address
      address&.full_name
    end

    def name_from_customer
      return unless resource&.customer

      resource.customer.full_name
    end

    def line_items_data
      @line_items_data ||= resource.line_items.map do |line_item|
        line_item_data(line_item)
      end
    end

    def line_item_data(line_item)
      SpreePlunk::LineItemPresenter.new(line_item: line_item, store: store, email: resolved_email).call.merge(
        unit_price_display: display_money(line_item.price),
        line_item_total_display: display_money(line_item.amount),
        variant_options_text: variant_options_text(line_item)
      ).reject { |_key, value| plunk_data_blank?(value) }
    end

    def variant_options_text(line_item)
      option_values = line_item.variant&.option_values
      return if option_values.blank?

      option_values.map { |option_value| option_value.presentation || option_value.name }.join(', ')
    end

    def line_items_text
      return if line_items_data.empty?

      line_items_data.map do |line_item|
        [
          line_item[:product_name],
          "x #{line_item[:quantity]}",
          line_item[:line_item_total_display] || line_item[:line_item_total]
        ].compact.join(' ')
      end.join("\n")
    end

    def line_items_html
      return if line_items_data.empty?

      rows = line_items_data.map do |line_item|
        option_text = line_item[:variant_options_text].present? ? "<br><small>#{h(line_item[:variant_options_text])}</small>" : ''
        <<~HTML
          <tr>
            <td style="padding: 8px 0;">
              <strong>#{h(line_item[:product_name])}</strong>#{option_text}
              #{line_item[:sku].present? ? "<br><small>SKU: #{h(line_item[:sku])}</small>" : ''}
            </td>
            <td style="padding: 8px 0; text-align: center;">#{h(line_item[:quantity])}</td>
            <td style="padding: 8px 0; text-align: right;">#{h(line_item[:line_item_total_display] || line_item[:line_item_total])}</td>
          </tr>
        HTML
      end

      <<~HTML
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse: collapse;">
          <thead>
            <tr>
              <th align="left" style="border-bottom: 1px solid #e5e7eb; padding: 8px 0;">Item</th>
              <th align="center" style="border-bottom: 1px solid #e5e7eb; padding: 8px 0;">Qty</th>
              <th align="right" style="border-bottom: 1px solid #e5e7eb; padding: 8px 0;">Total</th>
            </tr>
          </thead>
          <tbody>
            #{rows.join("\n")}
          </tbody>
        </table>
      HTML
    end

    def totals_data
      @totals_data ||= [
        total_row('Subtotal', resource.item_total),
        total_row('Shipping', resource.delivery_total),
        total_row('Tax', resource.tax_total),
        total_row('Discount', resource.discount_total),
        gift_card_total_row,
        total_row('Total', resource.total, display_total)
      ].compact.reject { |row| row[:amount].to_f.zero? && row[:label] != 'Total' }
    end

    def total_row(label, amount, display_amount = nil)
      return if amount.nil?

      {
        label: label,
        amount: amount.to_f,
        display_amount: display_amount.presence || display_money(amount)
      }
    end

    def gift_card_total_row
      total_row('Gift card', resource.gift_card_total)
    end

    def totals_text
      totals_data.map { |row| "#{row[:label]}: #{row[:display_amount]}" }.join("\n")
    end

    def totals_html
      rows = totals_data.map do |row|
        <<~HTML
          <tr>
            <td style="padding: 4px 0;">#{h(row[:label])}</td>
            <td style="padding: 4px 0; text-align: right;">#{h(row[:display_amount])}</td>
          </tr>
        HTML
      end

      <<~HTML
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse: collapse;">
          <tbody>
            #{rows.join("\n")}
          </tbody>
        </table>
      HTML
    end

    def fulfillments_data
      @fulfillments_data ||= resource.fulfillments.map do |fulfillment|
        SpreePlunk::FulfillmentPresenter.new(fulfillment: fulfillment, store: store).call.merge(
          tracking_url: fulfillment.tracking_url,
          delivery_total_display: display_money(fulfillment.cost)
        ).reject { |_key, value| plunk_data_blank?(value) }
      end
    end

    def fulfillments_text
      return if fulfillments_data.empty?

      fulfillments_data.map do |fulfillment|
        [
          fulfillment[:fulfillment_number],
          fulfillment[:delivery_method_name],
          fulfillment[:tracking].present? ? "Tracking: #{fulfillment[:tracking]}" : nil
        ].compact.join(' - ')
      end.join("\n")
    end

    def fulfillments_html
      return if fulfillments_data.empty?

      items = fulfillments_data.map do |fulfillment|
        details = [
          fulfillment[:delivery_method_name],
          fulfillment[:tracking].present? ? "Tracking: #{fulfillment[:tracking]}" : nil,
          fulfillment[:tracking_url]
        ].compact.map { |value| h(value) }.join('<br>')

        "<li><strong>#{h(fulfillment[:fulfillment_number])}</strong><br>#{details}</li>"
      end

      "<ul>#{items.join}</ul>"
    end

    def address_data(address)
      return {} unless address

      {
        name: address.full_name,
        firstname: address.first_name,
        lastname: address.last_name,
        address1: address.address1,
        address2: address.address2,
        city: address.city,
        zipcode: address.postal_code,
        state_name: address.state_name_text,
        country_name: address_country_name(address),
        phone: address.phone
      }.reject { |_key, value| plunk_data_blank?(value) }
    end

    def address_text(address)
      data = address_data(address)
      return if data.empty?

      [
        data[:name],
        data[:address1],
        data[:address2],
        [data[:city], data[:state_name], data[:zipcode]].compact_blank.join(', '),
        data[:country_name],
        data[:phone].present? ? "Phone: #{data[:phone]}" : nil
      ].compact_blank.join("\n")
    end

    def address_country_name(address)
      address.country&.name
    end

    def numeric_value
      value = yield
      value&.to_f
    rescue NoMethodError, TypeError
      nil
    end

    def display_money(amount)
      return if amount.nil?

      ::Spree::Money.new(amount, currency: resource.currency).to_s
    rescue StandardError
      "#{resource.currency} #{format('%.2f', amount.to_f)}"
    end
  end
end
