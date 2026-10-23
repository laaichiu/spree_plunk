module SpreePlunk
  class BaseJob < ApplicationJob
    queue_as SpreePlunk.queue

    retry_on SpreePlunk::RetryableSyncError, wait: :polynomially_longer, attempts: 5 do |job, error|
      job.send(:report_sync_error, error, retry_exhausted: true)
    end

    discard_on SpreePlunk::DiscardableSyncError do |job, error|
      job.send(:report_sync_error, error, discarded: true)
    end

    private

    def find_active_plunk_integration(id)
      ::Spree::Integrations::Plunk.active.find_by(id: id)
    end

    def ensure_sync_success!(result, operation:, **context)
      return result unless result&.failure?

      failure = normalize_failure_payload(result.value)
      exception_class = failure[:retryable] ? SpreePlunk::RetryableSyncError : SpreePlunk::DiscardableSyncError

      raise exception_class.new(
        failure[:error_message],
        status: failure[:status],
        error_code: failure[:error_code],
        context: {
          operation: operation,
          **context,
          status: failure[:status],
          error_code: failure[:error_code]
        }.compact
      )
    end

    def report_sync_error(error, retry_exhausted: false, discarded: false)
      Rails.error.report(
        error,
        handled: true,
        context: error.context.merge(
          job_class: self.class.name,
          queue_name: queue_name,
          executions: executions,
          retry_exhausted: retry_exhausted,
          discarded: discarded
        ),
        source: 'spree.plunk'
      )
    end

    def normalize_failure_payload(payload)
      failure = payload.is_a?(Hash) ? payload.deep_symbolize_keys : { error_message: payload.to_s }
      error_message = failure[:error_message].presence || failure[:error].presence || 'Plunk sync failed.'

      failure.merge(error_message: error_message, error_code: failure[:error_code] || failure[:error], retryable: !!failure[:retryable])
    end
  end
end
