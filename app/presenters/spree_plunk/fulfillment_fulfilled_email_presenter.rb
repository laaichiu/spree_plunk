module SpreePlunk
  class FulfillmentFulfilledEmailPresenter < TransactionalEmailPresenter
    def call
      base_payload(
        to: resolved_email,
        subject: "Your #{store_name} order #{order_number} has shipped",
        body: body,
        template_id: plunk_integration.preferred_fulfillment_fulfilled_template_id,
        data: fulfillment_data,
        headers: headers(
          email_type: TransactionalEmailTypes::FULFILLMENT_FULFILLED,
          resource_type: ::Spree::Fulfillment.name,
          resource_id: resource&.id
        )
      )
    end

    private

    def resolved_email
      email.presence || order&.email.presence || order&.customer&.email
    end

    def order
      resource&.owner
    end

    def order_number
      order&.number
    end

    def fulfillment_data
      return {} unless resource

      non_persistent_data_hash(
        SpreePlunk::FulfillmentPresenter.new(fulfillment: resource, store: store).call.merge(
          email_type: TransactionalEmailTypes::FULFILLMENT_FULFILLED,
          store_name: store_name,
          recipient_email: resolved_email,
          customer_email: customer_email,
          customer_name: customer_name,
          tracking_url: tracking_url,
          tracking_link_html: tracking_link_html,
          delivery_total_display: display_money(resource.cost),
          discount_total_display: display_money(resource.discount_total),
          fulfillment_items_count: fulfillment_items_data.sum { |item| item[:quantity].to_i },
          fulfillment_items: fulfillment_items_data,
          fulfillment_items_text: fulfillment_items_text,
          fulfillment_items_html: fulfillment_items_html,
          order_total: order_display_total,
          order_total_amount: numeric_value { order&.total },
          store_url: storefront_url
        )
      )
    end

    def body
      paragraphs = ["Your order #{order_number} has shipped."]
      paragraphs << "Tracking: #{resource.tracking}" if resource&.tracking.present?
      paragraphs << "Track your fulfillment: #{tracking_url}" if tracking_url.present?

      html_document(
        "Your #{store_name} order has shipped",
        paragraphs: paragraphs,
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

    def tracking_url
      @tracking_url ||= resource&.tracking_url
    end

    def tracking_link_html
      return if tracking_url.blank?

      %(<a href="#{h(tracking_url)}">#{h(tracking_url)}</a>)
    end

    def fulfillment_items_data
      @fulfillment_items_data ||= resource.manifest.map do |manifest_item|
        fulfillment_item_data(manifest_item)
      end.reject { |item| item[:product_name].blank? && item[:sku].blank? }
    end

    def fulfillment_item_data(manifest_item)
      line_item = manifest_item.line_item
      variant = manifest_item.variant || line_item&.variant
      quantity = manifest_item.quantity.to_i
      unit_price = numeric_value { line_item&.price }
      line_item_total = unit_price && quantity.positive? ? unit_price * quantity : nil

      SpreePlunk::LineItemPresenter.new(line_item: line_item, store: store, email: resolved_email).call.merge(
        quantity: quantity,
        unit_price: unit_price,
        unit_price_display: display_money(unit_price),
        line_item_total: line_item_total,
        line_item_total_display: display_money(line_item_total),
        variant_options_text: variant_options_text(variant)
      ).reject { |_key, value| plunk_data_blank?(value) }
    end

    def variant_options_text(variant)
      return if variant.blank?
      return variant.options_text if variant.options_text.present?

      option_values = variant.option_values
      return if option_values.blank?

      option_values.map { |option_value| option_value.presentation || option_value.name }.join(', ')
    end

    def fulfillment_items_text
      return if fulfillment_items_data.empty?

      fulfillment_items_data.map do |item|
        [
          item[:sku].present? ? "SKU: #{item[:sku]}" : nil,
          item[:product_name],
          item[:variant_options_text].present? ? "(#{item[:variant_options_text]})" : nil,
          "x #{item[:quantity]}",
          item[:line_item_total_display] || item[:line_item_total]
        ].compact.join(' ')
      end.join("\n")
    end

    def fulfillment_items_html
      return if fulfillment_items_data.empty?

      rows = fulfillment_items_data.map do |item|
        option_text = item[:variant_options_text].present? ? "<br><small>#{h(item[:variant_options_text])}</small>" : ''
        sku_text = item[:sku].present? ? "<br><small>SKU: #{h(item[:sku])}</small>" : ''

        <<~HTML
          <tr>
            <td style="padding: 8px 0;">
              <strong>#{h(item[:product_name])}</strong>#{option_text}#{sku_text}
            </td>
            <td style="padding: 8px 0; text-align: center;">#{h(item[:quantity])}</td>
            <td style="padding: 8px 0; text-align: right;">#{h(item[:line_item_total_display] || item[:line_item_total])}</td>
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

    def order_display_total
      return unless order
      order.display_total.to_s
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
