module SpreePlunk
  class ProcessUnsubscribeWebhook < Base
    REPLAY_CACHE_NAMESPACE = 'spree_plunk:subscription_webhook'.freeze
    REPLAY_TTL = 1.day

    def self.replay_cache_store
      return Rails.cache unless Rails.cache.is_a?(ActiveSupport::Cache::NullStore)

      @replay_cache_store ||= ActiveSupport::Cache::MemoryStore.new
    end

    def call(plunk_integration:, payload:)
      return noop_result('integration_inactive') unless plunk_integration&.active?
      return noop_result('webhook_disabled') unless plunk_integration&.preferred_unsubscribe_webhook_enabled

      normalized_payload = normalize_payload(payload)
      return noop_result('temporary_suppression') if temporary_suppression?(normalized_payload)

      subscribed = resolved_subscription_state(normalized_payload)
      return noop_result('unsupported_payload') if subscribed.nil?
      return noop_result('spree_confirmation_required') if subscribed

      email = resolved_email(normalized_payload)
      return noop_result('missing_email') if email.blank?

      delivery_id = replay_identifier(normalized_payload)
      if delivery_id.present?
        delivery_cache_key = replay_cache_key(plunk_integration: plunk_integration, delivery_id: delivery_id)
      end
      return noop_result('duplicate_delivery') if delivery_cache_key && !claim_delivery!(delivery_cache_key)

      result = SpreePlunk::ApplyLocalUnsubscribe.call(email: email, store: plunk_integration.store)
      release_delivery!(delivery_cache_key) if delivery_cache_key && result.failure?

      result
    end

    private

    def normalize_payload(payload)
      payload.to_h.deep_stringify_keys
    end

    def resolved_subscription_state(payload)
      explicit_value = payload.dig('contact', 'subscribed')
      explicit_value = payload['subscribed'] if explicit_value.nil? && payload.key?('subscribed')
      unless explicit_value.nil?
        case explicit_value
        when true, 1, '1'
          return true
        when false, 0, '0'
          return false
        when String
          case explicit_value.strip.downcase(:ascii)
          when 'true'
            return true
          when 'false'
            return false
          end
        end

        return
      end

      case event_name(payload)
      when 'contact.subscribed'
        true
      when 'contact.unsubscribed'
        false
      end
    end

    def temporary_suppression?(payload)
      %w[snooze snooze_expired].include?(event_reason(payload))
    end

    def event_reason(payload)
      payload.dig('event', 'reason').presence ||
        payload.dig('event', 'eventData', 'reason').presence ||
        payload.dig('event_data', 'reason').presence ||
        payload['reason'].presence
    end

    def event_name(payload)
      payload.dig('event', 'name').presence ||
        payload['event_name'].presence ||
        payload['name'].presence
    end

    def resolved_email(payload)
      normalize_email(payload.dig('contact', 'email') || payload['email'])
    end

    def normalize_email(value)
      value.to_s.strip.downcase.presence
    end

    def replay_cache_key(plunk_integration:, delivery_id:)
      [
        REPLAY_CACHE_NAMESPACE,
        plunk_integration.id,
        delivery_id
      ].join(':')
    end

    def replay_identifier(payload)
      execution_id = payload.dig('execution', 'id').presence
      return "execution:#{execution_id}" if execution_id

      event_id = payload.dig('event', 'id').presence ||
                 payload.dig('event', 'event_id').presence ||
                 payload['event_id'].presence
      return "event:#{event_id}" if event_id

      delivery_id = payload['delivery_id'].presence
      "delivery:#{delivery_id}" if delivery_id
    end

    def claim_delivery!(cache_key)
      replay_cache.write(cache_key, true, expires_in: REPLAY_TTL, unless_exist: true)
    end

    def release_delivery!(cache_key)
      replay_cache.delete(cache_key)
    end

    def replay_cache
      self.class.replay_cache_store
    end
  end
end
