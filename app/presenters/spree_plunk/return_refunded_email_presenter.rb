module SpreePlunk
  class ReturnRefundedEmailPresenter < TransactionalEmailPresenter
    def call
      base_payload(
        to: resolved_email,
        subject: "Your #{store_name} refund for order #{order_number}",
        body: body,
        template_id: plunk_integration.preferred_return_refunded_template_id,
        data: return_data,
        headers: headers(
          email_type: TransactionalEmailTypes::RETURN_REFUNDED,
          resource_type: resource.class.name,
          resource_id: resource&.id
        )
      )
    end

    private

    def resolved_email
      email.presence || order&.email.presence || order&.customer&.email
    end

    def order
      resource&.order
    end

    def order_number
      order&.number
    end

    def return_data
      return {} unless resource

      non_persistent_data_hash(
        SpreePlunk::ReturnPresenter.new(return_record: resource, store: store).call.merge(
          email_type: TransactionalEmailTypes::RETURN_REFUNDED,
          store_name: store_name,
          recipient_email: resolved_email,
          customer_email: customer_email,
          customer_name: customer_name,
          refunded_total_display: refunded_total_display,
          refundable_total_display: display_money(resource.refundable_total),
          return_items: return_items_data,
          return_items_text: return_items_text,
          return_items_html: return_items_html,
          order_total: order_display_total,
          order_total_amount: numeric_value { order&.total },
          store_url: storefront_url
        )
      )
    end

    def body
      html_document(
        "Your #{store_name} refund",
        paragraphs: [
          "A refund has been processed for order #{order_number}.",
          "You can contact #{store_name} if you have any questions."
        ],
        action_url: storefront_url,
        action_label: "Visit #{store_name}"
      )
    end

    def customer_email
      order&.email.presence || order&.customer&.email
    end

    def customer_name
      name_from_address.presence || name_from_customer
    end

    def name_from_address
      address = order&.ship_address || order&.bill_address
      address&.full_name
    end

    def name_from_customer
      return unless order&.customer

      order.customer.full_name
    end

    def refunded_total_display
      resource.display_refunded_total.to_s
    end

    def return_items_data
      @return_items_data ||= resource.return_line_items.map do |return_item|
        return_item_data(return_item)
      end.reject { |item| item[:product_name].blank? && item[:sku].blank? }
    end

    def return_item_data(return_item)
      variant = return_item.variant
      line_item = return_item.line_item
      refund_amount = return_item.refund_amount

      {
        return_item_id: record_identifier(return_item),
        quantity: return_item.credited_quantity,
        received_quantity: return_item.received_quantity,
        return_status: return_item.return.status,
        refund_amount: refund_amount,
        refund_amount_display: return_item_display_total(refund_amount),
        variant_id: record_identifier(variant),
        product_id: record_identifier(variant&.product),
        product_name: variant&.product&.name || line_item&.name,
        variant_name: variant&.name,
        variant_options_text: variant_options_text(variant),
        sku: variant&.sku || line_item&.sku
      }.reject { |_key, value| plunk_data_blank?(value) }
    end

    def return_item_display_total(refund_amount)
      ::Spree::Money.new(refund_amount, currency: resource.currency).to_s
    end

    def return_items_text
      return if return_items_data.empty?

      return_items_data.map do |item|
        [
          item[:sku].present? ? "SKU: #{item[:sku]}" : nil,
          item[:product_name],
          item[:variant_options_text].present? ? "(#{item[:variant_options_text]})" : nil,
          "x #{item[:quantity]}",
          item[:refund_amount_display] || item[:refund_amount]
        ].compact.join(' ')
      end.join("\n")
    end

    def return_items_html
      return if return_items_data.empty?

      rows = return_items_data.map do |item|
        option_text = item[:variant_options_text].present? ? "<br><small>#{h(item[:variant_options_text])}</small>" : ''
        sku_text = item[:sku].present? ? "<br><small>SKU: #{h(item[:sku])}</small>" : ''

        <<~HTML
          <tr>
            <td style="padding: 8px 0;">
              <strong>#{h(item[:product_name])}</strong>#{option_text}#{sku_text}
            </td>
            <td style="padding: 8px 0; text-align: center;">#{h(item[:quantity])}</td>
            <td style="padding: 8px 0; text-align: right;">#{h(item[:refund_amount_display] || item[:refund_amount])}</td>
          </tr>
        HTML
      end

      <<~HTML
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse: collapse;">
          <thead>
            <tr>
              <th align="left" style="border-bottom: 1px solid #e5e7eb; padding: 8px 0;">Returned item</th>
              <th align="center" style="border-bottom: 1px solid #e5e7eb; padding: 8px 0;">Qty</th>
              <th align="right" style="border-bottom: 1px solid #e5e7eb; padding: 8px 0;">Refund</th>
            </tr>
          </thead>
          <tbody>
            #{rows.join("\n")}
          </tbody>
        </table>
      HTML
    end

    def order_display_total
      return unless order
      order.display_total.to_s
    end

    def variant_options_text(variant)
      return if variant.blank?
      return variant.options_text if variant.options_text.present?

      option_values = variant.option_values
      return if option_values.blank?

      option_values.map { |option_value| option_value.presentation || option_value.name }.join(', ')
    end

    def record_identifier(record)
      return if record.blank?

      record.prefixed_id
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
