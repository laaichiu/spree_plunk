module SpreePlunk
  class OrderGroupConfirmationEmailPresenter < OrderTransactionalEmailPresenter
    def initialize(email_type:, **arguments)
      super(**arguments)
      @email_type = email_type.to_s
    end

    def call
      resend = email_type == TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND

      base_payload(
        to: resolved_email,
        subject: "Your #{store_name} order confirmation #{resource.number}",
        body: html_document(
          "Your #{store_name} order confirmation",
          paragraphs: [
            "Thank you for your order #{resource.number}.",
            "Order total: #{display_total}",
            "You can contact #{store_name} if anything looks wrong."
          ],
          action_url: storefront_url,
          action_label: "Visit #{store_name}"
        ),
        template_id: plunk_integration.preferred_order_confirmation_template_id,
        data: order_data(email_type: email_type).merge(
          non_persistent_data_hash(order_group: order_group_data, resend: resend)
        ),
        headers: headers(
          email_type: email_type,
          resource_type: ::Spree::OrderGroup.name,
          resource_id: resource.id
        )
      )
    end

    private

    attr_reader :email_type

    def order_group_data
      {
        id: resource.prefixed_id,
        number: resource.number,
        customer_name: customer_name,
        email: resolved_email,
        currency: resource.currency,
        completed_at: completed_at&.iso8601,
        po_number: resource.po_number,
        order_count: resource.orders.size,
        item_total: resource.item_total.to_f,
        discount_total: resource.discount_total.to_f,
        delivery_total: resource.delivery_total.to_f,
        tax_total: resource.tax_total.to_f,
        included_tax_total: resource.included_tax_total.to_f,
        additional_tax_total: resource.additional_tax_total.to_f,
        fee_total: resource.fee_total.to_f,
        gift_card_total: resource.gift_card_total.to_f,
        store_credit_total: resource.store_credit_total.to_f,
        total: resource.total.to_f,
        total_minus_store_credits: resource.total_minus_store_credits.to_f,
        amount_due: resource.amount_due.to_f,
        total_quantity: resource.line_items.sum(&:quantity),
        shipping_address: group_address(resource.ship_address),
        billing_address: group_address(resource.bill_address),
        items: line_items_data.map { |line_item| group_item(line_item) },
        unfulfilled_items: resource.unfulfilled_line_items.map do |line_item|
          group_item(SpreePlunk::LineItemPresenter.new(line_item: line_item, store: store, email: resolved_email).call.merge(
            variant_options_text: variant_options_text(line_item)
          ))
        end,
        fulfillment_groups: resource.fulfillment_groups.map { |group| fulfillment_group_data(group) },
        payments: []
      }
    end

    def group_item(line_item)
      line_item.merge(
        name: line_item[:product_name],
        price: line_item[:unit_price],
        total: line_item[:line_item_total],
        amount: line_item[:line_item_total],
        options_text: line_item[:variant_options_text]
      ).compact
    end

    def fulfillment_group_data(group)
      manifest = group.manifest.select(&:line_item)
      {
        name: group.name,
        unpriced: group.unpriced?,
        cost: group.cost.to_f,
        seller_names: group.sellers.map(&:name),
        items: manifest.map do |manifest_item|
          record = manifest_item.line_item
          line_item = SpreePlunk::LineItemPresenter.new(
            line_item: record,
            store: store,
            email: resolved_email
          ).call
          option_values = record.variant&.option_values
          options_text = option_values&.map { |value| value.presentation || value.name }&.join(', ')
          {
            id: line_item[:line_item_id],
            name: line_item[:product_name],
            quantity: manifest_item.quantity,
            sku: line_item[:sku],
            options_text: options_text,
            price: line_item[:unit_price],
            amount: line_item[:unit_price].to_f * manifest_item.quantity,
            url: line_item[:url],
            image_url: line_item[:image_url]
          }.compact
        end
      }
    end

    def group_address(address)
      return unless address

      {
        id: address.prefixed_id,
        first_name: address.first_name,
        last_name: address.last_name,
        full_name: address.full_name,
        address1: address.address1,
        address2: address.address2,
        postal_code: address.postal_code,
        city: address.city,
        phone: address.phone,
        company: address.company,
        country_name: address.country&.name,
        country_code: address.country&.iso,
        state_name: address.state_name_text,
        state_code: address.state_code
      }.compact
    end
  end
end
