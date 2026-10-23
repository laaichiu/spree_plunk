require 'cgi'
require 'erb'
require 'uri'

module SpreePlunk
  class TransactionalEmailPresenter
    SENSITIVE_DATA_KEYS = %i[
      confirmation_url
      payment_url
      reset_token
      reset_url
      verification_token
      verification_url
    ].freeze

    def initialize(plunk_integration:, resource: nil, email: nil, event_payload: nil)
      @plunk_integration = plunk_integration
      @resource = resource
      @email = email
      @event_payload = event_payload || {}
    end

    private

    attr_reader :plunk_integration, :resource, :email, :event_payload

    def base_payload(to:, subject:, body:, template_id:, data:, headers:)
      payload = {
        to: to,
        from: sender,
        data: plunk_data(data),
        headers: headers
      }

      if template_id.present?
        payload[:template] = template_id
      else
        payload[:subject] = subject
        payload[:body] = body
      end

      payload.delete(:from) if payload[:from].blank?
      payload.delete(:data) if payload[:data].blank?
      payload.delete(:headers) if payload[:headers].blank?
      payload
    end

    def sender
      sender_email = plunk_integration.preferred_default_from_email.presence || store&.mail_from_address
      return if sender_email.blank?

      sender_name = plunk_integration.preferred_default_from_name.presence || store&.name
      return sender_email if sender_name.blank?

      { name: sender_name, email: sender_email }
    end

    def plunk_data(data)
      data.compact_blank.to_h do |key, value|
        if non_persistent_data_value?(value)
          [key, value]
        elsif SENSITIVE_DATA_KEYS.include?(key.to_sym)
          [key, { value: value, persistent: false }]
        else
          [key, value]
        end
      end
    end

    def non_persistent_data(value)
      { value: value, persistent: false }
    end

    def non_persistent_data_hash(data)
      data.each_with_object({}) do |(key, value), payload|
        next if plunk_data_blank?(value)

        payload[key] = non_persistent_data(value)
      end
    end

    def non_persistent_data_value?(value)
      return false unless value.is_a?(Hash)

      (value.key?(:value) || value.key?('value')) &&
        (value[:persistent] == false || value['persistent'] == false)
    end

    def plunk_data_blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def headers(email_type:, resource_type: nil, resource_id: nil)
      {
        'X-Spree-Plunk-Email-Type' => email_type,
        'X-Spree-Plunk-Resource-Type' => resource_type,
        'X-Spree-Plunk-Resource-Id' => resource_id&.to_s
      }.compact
    end

    def event_value(key)
      return event_payload[key.to_s] if event_payload.key?(key.to_s)
      return event_payload[key.to_sym] if event_payload.key?(key.to_sym)

      nil
    end

    def append_token(url, token)
      return if url.blank? || token.blank?

      uri = URI.parse(url.to_s)
      params = URI.decode_www_form(uri.query || '')
      params << ['token', token.to_s]
      uri.query = URI.encode_www_form(params)
      uri.to_s
    rescue URI::InvalidURIError
      separator = url.to_s.include?('?') ? '&' : '?'
      "#{url}#{separator}token=#{CGI.escape(token.to_s)}"
    end

    def storefront_url
      store&.storefront_url
    end

    def store
      @store ||= plunk_integration.store || resource_store || event_store || ::Spree::Store.default
    end

    def resource_store
      resource.store if resource.respond_to?(:store)
    rescue ActiveModel::MissingAttributeError
      nil
    end

    def event_store
      store_id = event_value(:store_id)
      return if store_id.blank?

      ::Spree::Store.find_by_param(store_id)
    end

    def store_name
      store&.name.presence || 'Store'
    end

    def h(value)
      ERB::Util.html_escape(value.to_s)
    end

    def html_document(title, paragraphs:, action_url: nil, action_label: nil)
      body_parts = paragraphs.map { |paragraph| "<p>#{h(paragraph)}</p>" }
      if action_url.present? && action_label.present?
        escaped_url = h(action_url)
        body_parts << %(<p><a href="#{escaped_url}">#{h(action_label)}</a></p>)
        body_parts << %(<p>If the button does not work, copy this link into your browser:</p><p><a href="#{escaped_url}">#{escaped_url}</a></p>)
      end

      <<~HTML
        <h1>#{h(title)}</h1>
        #{body_parts.join("\n")}
      HTML
    end
  end
end
