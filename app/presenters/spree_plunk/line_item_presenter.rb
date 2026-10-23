module SpreePlunk
  class LineItemPresenter
    include ::Spree::ImagesHelper

    def initialize(line_item:, store: nil, email: nil)
      @line_item = line_item
      @store = store
      @email = email
    end

    def call
      {
        line_item_id: line_item_identifier,
        order_id: order_identifier,
        order_number: order_number,
        store_code: store_code,
        email: resolved_email,
        quantity: quantity,
        unit_price: unit_price,
        line_item_total: line_item_total,
        currency: currency,
        variant_id: variant_identifier,
        seller_id: seller_identifier,
        preorder: preorder?,
        preorder_ships_at: preorder_ships_at,
        product_id: product_identifier,
        product_name: product_name,
        slug: product_slug,
        options_text: options_text,
        adjustment_total: amount_attribute(:adjustment_total),
        additional_tax_total: amount_attribute(:additional_tax_total),
        included_tax_total: amount_attribute(:included_tax_total),
        discount_total: amount_attribute(:discount_total),
        pre_tax_amount: amount_attribute(:pre_tax_amount),
        discounted_amount: amount_attribute(:discounted_amount),
        compare_at_amount: amount_attribute(:compare_at_amount),
        sku: sku,
        url: product_url,
        image_url: image_url
      }.reject { |_key, value| value.nil? || value == '' }
    end

    private

    attr_reader :line_item, :store, :email

    def snapshot?
      line_item.is_a?(Hash)
    end

    def store_code
      return snapshot_value('store_code') if snapshot?

      store&.code || purchase&.store&.code
    end

    def resolved_email
      email.presence || snapshot_value('email') || purchase&.email.presence || purchase&.customer&.email
    end

    def purchase
      return if snapshot?

      @purchase ||= line_item.owner
    end

    def line_item_identifier
      return snapshot_value('line_item_id') if snapshot?

      line_item.prefixed_id
    end

    def order_identifier
      return snapshot_value('order_id') if snapshot?
      return unless purchase

      purchase.prefixed_id
    end

    def order_number
      return snapshot_value('order_number') if snapshot?

      return unless purchase
      return purchase.prefixed_id if purchase.is_a?(::Spree::Cart)

      purchase.number
    end

    def snapshot_value(key)
      return unless snapshot?

      line_item[key] || line_item[key.to_sym]
    end

    def quantity
      return line_item.quantity unless snapshot?

      snapshot_value('quantity')
    end

    def unit_price
      return line_item.price.to_f unless snapshot?

      numeric_snapshot_value('unit_price')
    end

    def line_item_total
      return line_item.amount.to_f unless snapshot?

      numeric_snapshot_value('line_item_total')
    end

    def currency
      return snapshot_value('currency') if snapshot?

      purchase&.currency
    end

    def variant_identifier
      return snapshot_value('variant_id') if snapshot?

      line_item.variant&.prefixed_id
    end

    def seller_identifier
      return snapshot_value('seller_id') if snapshot?

      line_item.seller&.prefixed_id
    end

    def preorder?
      return !!snapshot_value('preorder') if snapshot?

      line_item.variant&.preorder? || false
    end

    def preorder_ships_at
      return snapshot_value('preorder_ships_at') if snapshot?
      return unless preorder?

      line_item.variant.preorder_ships_at&.iso8601
    end

    def product_identifier
      return snapshot_value('product_id') if snapshot?

      line_item.product&.prefixed_id
    end

    def product_name
      return line_item.name unless snapshot?

      snapshot_value('product_name')
    end

    def product_slug
      return snapshot_value('slug') if snapshot?

      line_item.product&.slug
    end

    def options_text
      return snapshot_value('options_text') if snapshot?

      line_item.options_text
    end

    def amount_attribute(name)
      return numeric_snapshot_value(name.to_s) if snapshot?

      value = line_item.public_send(name)
      value&.to_f
    rescue NoMethodError
      nil
    end

    def sku
      return line_item.sku unless snapshot?

      snapshot_value('sku')
    end

    def product_url
      return snapshot_value('url') if snapshot?

      base_url = store&.storefront_url
      slug = line_item.product&.slug
      "#{base_url}/products/#{slug}" if base_url.present? && slug.present?
    end

    def image_url
      return snapshot_value('image_url') if snapshot?

      spree_image_url(line_item.thumbnail, variant: :small)
    rescue StandardError
      nil
    end

    def numeric_snapshot_value(key)
      value = snapshot_value(key)
      return if value.nil?

      value.to_f
    end
  end
end
