module SpreePlunk
  # Adapts Plunk's privacy-wrapped send data to the Spree 6 email variables
  # used by the dashboard editor and the default Spree email templates.
  class EmailTemplateAssignments
    def self.call(email_type:, payload:, resource: nil)
      new(email_type: email_type, payload: payload, resource: resource).call
    end

    def initialize(email_type:, payload:, resource: nil)
      @email_type = email_type.to_s
      @payload = payload
      @resource = resource
      @data = unwrap(payload[:data] || {})
    end

    def call
      case email_type
      when TransactionalEmailTypes::PASSWORD_RESET
        {
          customer: {
            first_name: data[:customer_first_name],
            last_name: data[:customer_last_name],
            email: data[:recipient_email] || payload[:to]
          },
          reset_url: data[:reset_url]
        }
      when TransactionalEmailTypes::NEWSLETTER_CONFIRMATION
        { confirmation_url: data[:confirmation_url] || data[:verification_url] }
      when TransactionalEmailTypes::DIGITAL_ASSET_READY
        {
          order: order,
          downloads: data[:downloads] || [],
          resend: data[:resend] || false
        }
      when TransactionalEmailTypes::COMPANY_INVITATION
        {
          company: data[:company] || {},
          accept_url: data[:accept_url]
        }
      when TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION
        {
          kind: data[:kind],
          confirmation_url: data[:confirmation_url],
          expires_at: data[:expires_at]
        }
      when TransactionalEmailTypes::DATA_EXPORT_READY
        {
          download_url: data[:download_url],
          expires_at: data[:expires_at]
        }
      when TransactionalEmailTypes::PAYMENT_LINK
        {
          order: order,
          payment_url: data[:payment_url]
        }
      when TransactionalEmailTypes::FULFILLMENT_FULFILLED
        {
          order: order,
          fulfillment: fulfillment,
          resend: false
        }
      when TransactionalEmailTypes::RETURN_REFUNDED
        {
          order: order,
          return: return_data,
          resend: false
        }
      when TransactionalEmailTypes::ORDER_CONFIRMATION,
           TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND,
           TransactionalEmailTypes::ORDER_CANCELLATION
        if data[:order_group].present?
          {
            order_group: order_group,
            resend: data[:resend] || email_type == TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND
          }
        else
          { order: order, resend: email_type == TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND }
        end
      else
        {}
      end
    end

    private

    attr_reader :email_type, :payload, :resource, :data

    def order
      @order ||= purchase_assignments(data, purchase_resource)
    end

    def order_group
      @order_group ||= purchase_assignments(data[:order_group], purchase_resource)
    end

    def purchase_assignments(source, purchase)
      source = unwrap(source || {})
      items = source[:items] || source[:line_items]

      {
        id: source[:id] || prefixed_id(purchase),
        number: source[:number] || source[:order_number],
        email: source[:email] || source[:customer_email] || source[:recipient_email] || payload[:to],
        customer_name: source[:customer_name],
        customer_note: model_value(purchase, :customer_note),
        po_number: source[:po_number] || model_value(purchase, :po_number),
        currency: source[:currency] || model_value(purchase, :currency) || data[:currency],
        locale: model_value(purchase, :locale),
        status: source[:status] || data[:status],
        fulfillment_status: source[:fulfillment_status] || data[:fulfillment_status],
        payment_status: source[:payment_status] || data[:payment_status],
        completed_at: source[:completed_at] || data[:completed_at],
        item_total: amount(source, :item_total, purchase),
        discount_total: amount(source, :discount_total, purchase),
        tax_total: amount(source, :tax_total, purchase),
        included_tax_total: amount(source, :included_tax_total, purchase),
        additional_tax_total: amount(source, :additional_tax_total, purchase),
        delivery_total: amount(source, :delivery_total, purchase),
        fee_total: amount(source, :fee_total, purchase),
        gift_card_total: amount(source, :gift_card_total, purchase),
        store_credit_total: amount(source, :store_credit_total, purchase),
        total: amount(source, :total, purchase, fallback: :order_total_amount),
        amount_due: amount(source, :amount_due, purchase),
        total_minus_store_credits: amount(source, :total_minus_store_credits, purchase, fallback: :total),
        total_quantity: source[:total_quantity] || line_item_quantity(purchase) || data[:item_count],
        order_count: source[:order_count] || model_value(purchase, :order_count),
        coupon_code: model_value(purchase, :coupon_code),
        covered_by_store_credit: model_value(purchase, :covered_by_store_credit) || false,
        items: line_items(items),
        unfulfilled_items: line_items(source[:unfulfilled_items]),
        fulfillment_groups: fulfillment_groups(source[:fulfillment_groups]),
        fulfillments: unwrap(source[:fulfillments] || data[:fulfillments] || []),
        payments: unwrap(source[:payments] || []),
        discounts: unwrap(source[:discounts] || []),
        fees: unwrap(source[:fees] || []),
        promotion_discounts: amount_lines(source, :promotion_discounts, purchase, :promotion_discounts),
        manual_discounts: amount_lines(source, :manual_discounts, purchase, :manual_discounts),
        fee_lines: amount_lines(source, :fee_lines, purchase, :fee_lines),
        delivery_lines: amount_lines(source, :delivery_lines, purchase, :delivery_lines),
        billing_address: address(source[:billing_address] || data[:billing_address] || model_value(purchase, :bill_address)),
        shipping_address: address(source[:shipping_address] || data[:shipping_address] || model_value(purchase, :ship_address))
      }.compact
    end

    def fulfillment
      source = data
      {
        id: source[:fulfillment_id],
        number: source[:fulfillment_number],
        status: source[:fulfillment_status],
        tracking: source[:tracking],
        tracking_url: source[:tracking_url],
        delivery_method_name: source[:delivery_method_name],
        manifest_items: line_items(source[:fulfillment_items]),
        items: fulfillment_item_references,
        deliveries: [],
        delivery_rates: [],
        fulfillment_type: source[:fulfillment_type],
        fulfilled_at: source[:fulfilled_at],
        cost: source[:delivery_total],
        total: source[:delivery_total],
        discount_total: source[:discount_total],
        tax_total: source[:tax_total]
      }.compact
    end

    def return_data
      {
        id: data[:return_id],
        number: data[:return_number],
        status: data[:return_status],
        order_id: data[:order_id],
        refund_total: data[:refund_total],
        refunded_total: data[:refunded_total],
        returned_items: returned_items
      }.compact
    end

    def returned_items
      return line_items(data[:return_items]) unless resource.is_a?(::Spree::Return)

      items = resource.return_line_items.filter_map(&:line_item).uniq.map do |line_item|
        SpreePlunk::LineItemPresenter.new(
          line_item: line_item,
          store: resource.store,
          email: data[:recipient_email] || payload[:to]
        ).call.merge(variant_options_text: line_item.options_text)
      end
      line_items(items)
    end

    def fulfillment_item_references
      return [] unless resource.is_a?(::Spree::Fulfillment)

      resource.manifest.filter_map do |manifest_item|
        line_item = manifest_item.line_item
        next unless line_item

        {
          item_id: line_item.prefixed_id,
          variant_id: (manifest_item.variant || line_item.variant)&.prefixed_id,
          quantity: manifest_item.quantity
        }
      end
    end

    def line_items(items)
      Array(unwrap(items || [])).map do |item|
        item = unwrap(item || {})
        amount = item[:amount] || item[:line_item_total] || item[:total] || item[:refund_amount]
        {
          id: item[:id] || item[:line_item_id],
          variant_id: item[:variant_id],
          seller_id: item[:seller_id],
          preorder: item[:preorder] || false,
          preorder_ships_at: item[:preorder_ships_at],
          quantity: item[:quantity],
          currency: item[:currency] || data[:currency],
          name: item[:name] || item[:product_name],
          slug: item[:slug],
          options_text: item[:options_text] || item[:variant_options_text],
          price: item[:price] || item[:unit_price],
          total: item[:total] || item[:line_item_total] || item[:refund_amount] || amount,
          adjustment_total: item[:adjustment_total],
          additional_tax_total: item[:additional_tax_total],
          included_tax_total: item[:included_tax_total],
          discount_total: item[:discount_total],
          pre_tax_amount: item[:pre_tax_amount],
          discounted_amount: item[:discounted_amount],
          compare_at_amount: item[:compare_at_amount],
          option_values: unwrap(item[:option_values] || []),
          url: item[:url],
          image_url: item[:image_url],
          sku: item[:sku],
          amount: amount
        }
      end
    end

    def fulfillment_groups(groups)
      Array(unwrap(groups || [])).map do |group|
        group = unwrap(group || {})
        {
          name: group[:name],
          unpriced: group[:unpriced] || false,
          cost: group[:cost],
          seller_names: group[:seller_names] || [],
          items: line_items(group[:items])
        }.compact
      end
    end

    def address(value)
      if value.respond_to?(:prefixed_id)
        return {
          id: value.prefixed_id,
          first_name: value.first_name,
          last_name: value.last_name,
          full_name: value.full_name,
          address1: value.address1,
          address2: value.address2,
          postal_code: value.postal_code,
          city: value.city,
          phone: value.phone,
          company: value.company,
          country_name: value.country&.name,
          country_code: value.country&.iso,
          state_text: value.state_name_text,
          state_code: value.state_code,
          state_name: value.state_name_text
        }.compact
      end

      value = unwrap(value || {})
      return if value.empty?

      {
        id: value[:id],
        label: value[:label],
        first_name: value[:first_name] || value[:firstname],
        last_name: value[:last_name] || value[:lastname],
        full_name: value[:full_name] || value[:name],
        address1: value[:address1],
        address2: value[:address2],
        postal_code: value[:postal_code] || value[:zipcode],
        city: value[:city],
        phone: value[:phone],
        company: value[:company],
        country_name: value[:country_name],
        country_code: value[:country_code],
        state_text: value[:state_text],
        state_code: value[:state_code],
        state_name: value[:state_name]
      }.compact
    end

    def amount(source, key, purchase, fallback: nil)
      source[key] || data[key] || (fallback && source[fallback]) || (fallback && data[fallback]) || model_value(purchase, key)
    end

    def amount_lines(source, key, purchase, method)
      return unwrap(source[key]) if source[key].present?

      records = model_amount_lines(purchase, method)
      records || []
    end

    def model_amount_lines(purchase, method)
      return unless purchase

      case method
      when :promotion_discounts
        group_amounts(purchase.discounts.promotion) if purchase.respond_to?(:discounts)
      when :manual_discounts
        group_amounts(purchase.discounts.manual) if purchase.respond_to?(:discounts)
      when :fee_lines
        group_amounts(purchase.fees) if purchase.respond_to?(:fees)
      when :delivery_lines
        if purchase.respond_to?(:fulfillments)
          rows = purchase.fulfillments.to_a
          group_amounts(rows, label: ->(fulfillment) { fulfillment.selected_delivery_rate&.name }, amount: :cost, keep_zero: true)
        end
      end
    end

    def group_amounts(records, label: :label, amount: :amount, keep_zero: false)
      records.to_a.group_by { |record| label.respond_to?(:call) ? label.call(record) : record.public_send(label) }.filter_map do |name, rows|
        total = rows.sum { |row| row.public_send(amount).to_d }
        next if !keep_zero && total.zero?

        { label: name, amount: total.to_s('F') }
      end
    end

    def purchase_resource
      case resource
      when ::Spree::OrderGroup, ::Spree::Order
        resource
      when ::Spree::Fulfillment
        resource.owner
      when ::Spree::Return
        resource.order
      end
    end

    def prefixed_id(record)
      record.prefixed_id if record&.respond_to?(:prefixed_id)
    end

    def line_item_quantity(purchase)
      purchase.line_items.sum(&:quantity) if purchase&.respond_to?(:line_items)
    end

    def model_value(record, method)
      record.public_send(method) if record&.respond_to?(method)
    rescue ActiveModel::MissingAttributeError
      nil
    end

    def unwrap(value)
      if non_persistent_value?(value)
        return unwrap(value.key?(:value) ? value[:value] : value['value'])
      end

      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key.to_sym] = unwrap(item) }
      when Array
        value.map { |item| unwrap(item) }
      else
        value
      end
    end

    def non_persistent_value?(value)
      value.is_a?(Hash) && (value[:persistent] == false || value['persistent'] == false) &&
        (value.key?(:value) || value.key?('value'))
    end
  end
end
