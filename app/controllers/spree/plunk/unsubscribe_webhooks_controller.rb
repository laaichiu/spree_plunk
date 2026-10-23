module Spree
  module Plunk
    class UnsubscribeWebhooksController < ActionController::API
      rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_bad_request

      def create
        integration = ::Spree::Integrations::Plunk.active.find_by_param(params[:integration_id])
        return head :not_found unless integration&.preferred_unsubscribe_webhook_enabled
        return head :unauthorized unless authorized?(integration)

        result = ::SpreePlunk::ProcessUnsubscribeWebhook.call(
          plunk_integration: integration,
          payload: webhook_payload
        )

        return head :ok if result.success?

        report_failed_result(result, integration)
        head :unprocessable_entity
      rescue StandardError => e
        Rails.error.report(
          e,
          context: webhook_context(integration: integration),
          source: 'spree.plunk.webhooks'
        )

        head :internal_server_error
      end

      private

      def webhook_payload
        params.to_unsafe_h.except('controller', 'action', 'integration_id')
      end

      def authorized?(integration)
        provided_value = request.authorization.to_s
        expected_value = "Bearer #{integration.preferred_unsubscribe_webhook_authorization_token}"

        provided_value.present? &&
          expected_value.present? &&
          provided_value.bytesize == expected_value.bytesize &&
          ActiveSupport::SecurityUtils.secure_compare(provided_value, expected_value)
      end

      def report_failed_result(result, integration)
        Rails.error.report(
          StandardError.new(result.error.to_s),
          handled: true,
          context: webhook_context(
            integration: integration,
            result: result
          ),
          source: 'spree.plunk.webhooks'
        )
      end

      def webhook_context(integration:, result: nil)
        payload = webhook_payload

        {
          integration_id: integration&.id,
          integration_param: integration&.to_param,
          store_id: integration&.store_id,
          email: payload.dig('contact', 'email') || payload['email'],
          workflow_id: payload.dig('workflow', 'id'),
          workflow_name: payload.dig('workflow', 'name'),
          execution_id: payload.dig('execution', 'id') || payload['event_id'] || payload['delivery_id'],
          webhook_result: result&.value
        }.compact
      end

      def render_bad_request
        head :bad_request
      end
    end
  end
end
