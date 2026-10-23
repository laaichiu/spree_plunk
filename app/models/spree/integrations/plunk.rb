require 'base64'

module Spree
  module Integrations
    class Plunk < Spree::Integration
      class ApiError < StandardError; end

      CONNECTION_CHECK_PATH = 'contacts?limit=1'.freeze
      KNOWN_ENDPOINT_PATHS = %w[/contacts /contacts/lookup /events/track /v1/track /v1/send].freeze
      RETRYABLE_STATUS_CODES = [408, 429].freeze
      MAX_URL_LENGTH = 255
      MAX_API_KEY_LENGTH = 255
      MAX_SENDER_EMAIL_LENGTH = 255
      MAX_SENDER_NAME_LENGTH = 255
      MAX_TEMPLATE_ID_LENGTH = 255
      PLUNK_LOGO_PATH = SpreePlunk::Engine.root.join('app/assets/images/integration_icons/plunk-logo.png')
      preference :plunk_base_url, :string, default: 'https://next-api.useplunk.com'
      preference :plunk_secret_api_key, :password
      preference :plunk_public_api_key, :string
      preference :default_from_email, :string
      preference :default_from_name, :string
      preference :transactional_email_enabled, :boolean, default: false
      preference :password_reset_email_enabled, :boolean, default: false
      preference :password_reset_template_id, :string
      preference :newsletter_confirmation_email_enabled, :boolean, default: false
      preference :newsletter_confirmation_template_id, :string
      preference :order_confirmation_email_enabled, :boolean, default: false
      preference :order_confirmation_resend_email_enabled, :boolean, default: false
      preference :order_confirmation_template_id, :string
      preference :order_cancellation_email_enabled, :boolean, default: false
      preference :order_cancellation_template_id, :string
      preference :fulfillment_fulfilled_email_enabled, :boolean, default: false
      preference :fulfillment_fulfilled_template_id, :string
      preference :return_refunded_email_enabled, :boolean, default: false
      preference :return_refunded_template_id, :string
      preference :store_owner_notification_email_enabled, :boolean, default: false
      preference :store_owner_notification_template_id, :string
      preference :unsubscribe_webhook_enabled, :boolean, default: false
      preference :unsubscribe_webhook_authorization_token, :password

      before_validation :normalize_preferences

      validates :preferred_plunk_base_url, :preferred_plunk_secret_api_key, presence: true
      validates :preferred_plunk_base_url, length: { maximum: MAX_URL_LENGTH }, allow_blank: true
      validates :preferred_plunk_secret_api_key, length: { maximum: MAX_API_KEY_LENGTH }, allow_blank: true
      validates :preferred_plunk_public_api_key, length: { maximum: MAX_API_KEY_LENGTH }, allow_blank: true
      validates :preferred_unsubscribe_webhook_authorization_token, length: { maximum: MAX_API_KEY_LENGTH }, allow_blank: true
      validates :preferred_default_from_email, length: { maximum: MAX_SENDER_EMAIL_LENGTH }, allow_blank: true,
                                                      format: { with: URI::MailTo::EMAIL_REGEXP, message: :invalid_email_address }
      validates :preferred_default_from_name, length: { maximum: MAX_SENDER_NAME_LENGTH }, allow_blank: true
      validates :preferred_password_reset_template_id, length: { maximum: MAX_TEMPLATE_ID_LENGTH }, allow_blank: true
      validates :preferred_newsletter_confirmation_template_id, length: { maximum: MAX_TEMPLATE_ID_LENGTH }, allow_blank: true
      validates :preferred_order_confirmation_template_id, length: { maximum: MAX_TEMPLATE_ID_LENGTH }, allow_blank: true
      validates :preferred_order_cancellation_template_id, length: { maximum: MAX_TEMPLATE_ID_LENGTH }, allow_blank: true
      validates :preferred_fulfillment_fulfilled_template_id, length: { maximum: MAX_TEMPLATE_ID_LENGTH }, allow_blank: true
      validates :preferred_return_refunded_template_id, length: { maximum: MAX_TEMPLATE_ID_LENGTH }, allow_blank: true
      validates :preferred_store_owner_notification_template_id, length: { maximum: MAX_TEMPLATE_ID_LENGTH }, allow_blank: true

      validate :validate_plunk_base_url
      validate :validate_api_keys
      validate :validate_sender_defaults
      validate :validate_unsubscribe_webhook_preferences

      def self.integration_group
        'marketing'
      end

      def self.logo_url
        return unless PLUNK_LOGO_PATH.exist?

        @logo_url ||= "data:image/png;base64,#{Base64.strict_encode64(PLUNK_LOGO_PATH.binread)}"
      end

      def can_connect?
        self.connection_error_message = nil

        # Spree validates an activation by calling #can_connect?. Validating
        # the Plunk credentials here must not trigger that activation check
        # again when the record is changing from inactive to active.
        @checking_connection = true
        unless valid?
          self.connection_error_message = invalid_configuration_message
          return false
        end

        result = client.get(CONNECTION_CHECK_PATH)
        self.connection_error_message = connection_error_message_for(result) if result.failure?

        result.success?
      ensure
        @checking_connection = false
      end

      def upsert_contact(payload)
        return inactive_result unless active?

        handle_result(client.post('contacts', payload))
      end

      def lookup_contact(email:)
        return inactive_result unless active?

        handle_result(client.post('contacts/lookup', { emails: [email] }))
      end

      def subscribe_contact(payload)
        return inactive_result unless active?

        handle_result(client.post('contacts', payload.merge(subscribed: true)))
      end

      def unsubscribe_contact(payload)
        return inactive_result unless active?

        handle_result(client.post('contacts', payload.merge(subscribed: false)))
      end

      def track_event(payload)
        return inactive_result unless active?

        handle_result(client.post('events/track', payload))
      end

      def send_transactional_email(payload, idempotency_key: nil)
        return inactive_result unless active?

        headers = { 'Idempotency-Key' => idempotency_key } if idempotency_key.present?
        result = client.post('v1/send', payload, headers: headers || {})

        if result.failure? && result.value[:status].to_i == 409 && idempotency_key.present?
          body = result.value[:body]
          original_status = body.dig('details', 'originalStatusCode') if body.is_a?(Hash)
          message = 'Plunk rejected this retry because the idempotency key was already used.'
          message += " The original request returned HTTP #{original_status}; check Plunk delivery logs before resending." if original_status.present?

          return Spree::ServiceModule::Result.new(false, {
            status: 409,
            error_message: message,
            error_code: 'idempotency_conflict',
            retryable: false,
            response_body: body
          })
        end

        handle_result(result)
      end

      private

      def must_connect_when_activating
        return if @checking_connection

        super
      end

      def inactive_result
        Spree::ServiceModule::Result.new(true, { skipped: true, reason: 'integration_inactive' })
      end

      def client
        ::SpreePlunk::Plunk::Client.new(
          base_url: preferred_plunk_base_url,
          secret_api_key: preferred_plunk_secret_api_key
        )
      end

      def normalize_preferences
        self.preferred_plunk_base_url = normalize_string(preferred_plunk_base_url)&.sub(%r{/*\z}, '')
        self.preferred_plunk_secret_api_key = normalize_string(preferred_plunk_secret_api_key)
        self.preferred_plunk_public_api_key = normalize_string(preferred_plunk_public_api_key)
        self.preferred_unsubscribe_webhook_authorization_token = normalize_string(preferred_unsubscribe_webhook_authorization_token)
        self.preferred_default_from_email = normalize_string(preferred_default_from_email)&.downcase
        self.preferred_default_from_name = normalize_string(preferred_default_from_name)
        self.preferred_password_reset_template_id = normalize_string(preferred_password_reset_template_id)
        self.preferred_newsletter_confirmation_template_id = normalize_string(preferred_newsletter_confirmation_template_id)
        self.preferred_order_confirmation_template_id = normalize_string(preferred_order_confirmation_template_id)
        self.preferred_order_cancellation_template_id = normalize_string(preferred_order_cancellation_template_id)
        self.preferred_fulfillment_fulfilled_template_id = normalize_string(preferred_fulfillment_fulfilled_template_id)
        self.preferred_return_refunded_template_id = normalize_string(preferred_return_refunded_template_id)
        self.preferred_store_owner_notification_template_id = normalize_string(preferred_store_owner_notification_template_id)
      end

      def normalize_string(value)
        return value unless value.is_a?(String)

        value.strip.presence
      end

      def validate_plunk_base_url
        return if preferred_plunk_base_url.blank?

        uri = URI.parse(preferred_plunk_base_url)

        unless uri.is_a?(URI::HTTP) && uri.host.present?
          errors.add(:preferred_plunk_base_url, :invalid_http_url)
          return
        end

        errors.add(:preferred_plunk_base_url, :query_or_fragment_not_allowed) if uri.query.present? || uri.fragment.present?
        errors.add(:preferred_plunk_base_url, :endpoint_path_not_allowed) if endpoint_path?(uri.path)
      rescue URI::InvalidURIError
        errors.add(:preferred_plunk_base_url, :invalid_http_url)
      end

      def validate_api_keys
        validate_key_whitespace(:preferred_plunk_secret_api_key)
        validate_key_whitespace(:preferred_plunk_public_api_key)
        validate_key_whitespace(:preferred_unsubscribe_webhook_authorization_token)
      end

      def validate_key_whitespace(attribute)
        return if public_send(attribute).blank?

        errors.add(attribute, :whitespace_not_allowed) if public_send(attribute).match?(/\s/)
      end

      def validate_sender_defaults
        return unless preferred_default_from_name.present? && preferred_default_from_email.blank?

        errors.add(:preferred_default_from_email, :required_when_sender_name_present)
      end

      def validate_unsubscribe_webhook_preferences
        return unless preferred_unsubscribe_webhook_enabled
        return if preferred_unsubscribe_webhook_authorization_token.present?

        errors.add(:preferred_unsubscribe_webhook_authorization_token, :blank)
      end

      def endpoint_path?(path)
        normalized_path = path.to_s.sub(%r{/*\z}, '')
        KNOWN_ENDPOINT_PATHS.include?(normalized_path)
      end

      def invalid_configuration_message
        "Review the highlighted configuration fields: #{errors.full_messages.uniq.to_sentence}"
      end

      def connection_error_message_for(result)
        status = result.value[:status]
        message = extract_error_message(result.value[:body])

        return invalid_secret_api_key_message if [401, 403].include?(status)
        return missing_api_endpoint_message if status == 404
        return timeout_connection_message if timeout_error?(message)
        return unreachable_connection_message if transport_error?(message)
        return "Plunk returned HTTP #{status}: #{message}" if status.present? && message.present?
        return "Plunk returned HTTP #{status} during the connection check." if status.present?

        message.presence || 'The Plunk connection check failed for an unknown reason.'
      end

      def invalid_secret_api_key_message
        'Plunk rejected the secret API key. Confirm that you pasted a valid secret server key for this workspace and try again.'
      end

      def missing_api_endpoint_message
        "Spree reached #{preferred_plunk_base_url}, but the expected Plunk API endpoint was not found. Use the API base URL only, not a specific endpoint path."
      end

      def timeout_connection_message
        "Spree timed out while contacting Plunk at #{preferred_plunk_base_url}. Check DNS, port, TLS, firewall, and that the self-hosted API is reachable from the app server."
      end

      def unreachable_connection_message
        "Spree could not reach Plunk at #{preferred_plunk_base_url}. Check DNS, port, TLS, firewall, and that the self-hosted API is reachable from the app server."
      end

      def timeout_error?(message)
        message.to_s.match?(/execution expired|timed out|timeout/i)
      end

      def transport_error?(message)
        message.to_s.match?(/getaddrinfo|failed to open tcp connection|connection refused|no route to host|econnrefused|ssl_connect|certificate/i)
      end

      def handle_result(result)
        if result.success?
          Spree::ServiceModule::Result.new(true, result.value[:body])
        else
          status = result.value[:status]
          error_message = extract_error_message(result.value[:body])

          Spree::ServiceModule::Result.new(false, {
            status: status,
            error_message: error_message,
            error_code: error_code_for(status: status, error_message: error_message),
            retryable: retryable_failure?(status: status, error_message: error_message),
            response_body: result.value[:body]
          })
        end
      end

      def retryable_failure?(status:, error_message:)
        retryable_status?(status) || timeout_error?(error_message) || transport_error?(error_message)
      end

      def retryable_status?(status)
        status.to_i >= 500 || RETRYABLE_STATUS_CODES.include?(status)
      end

      def error_code_for(status:, error_message:)
        return 'timeout' if timeout_error?(error_message)
        return 'transport_error' if transport_error?(error_message)
        return "http_#{status}" if status.present?

        'unknown_error'
      end

      def extract_error_message(body)
        case body
        when Hash
          body = body.with_indifferent_access
          errors = body[:errors]

          body[:error] ||
            body[:message] ||
            (errors.first if errors.is_a?(Array) && errors.first.is_a?(String)) ||
            body.dig(:errors, 0, :message) ||
            body.dig(:errors, 0, :detail) ||
            body.inspect
        else
          body.to_s
        end
      end
    end
  end
end
