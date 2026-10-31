module Spree
  module Api
    module V3
      module Admin
        module Orders
          class PaymentLinksController < BaseController
            def create
              return render_unavailable unless payable_order?
              return render_unavailable if @order.email.blank?
              integration = plunk_integration
              return render_unavailable unless integration&.preferred_transactional_email_enabled && integration.preferred_payment_link_email_enabled
              return render_unavailable unless @order.store.prefers_send_consumer_transactional_emails?

              SpreePlunk::SendTransactionalEmailJob.perform_later(
                integration.id,
                SpreePlunk::TransactionalEmailTypes::PAYMENT_LINK,
                ::Spree::Order.name,
                @order.id,
                @order.email,
                { 'store_id' => @order.store.to_param, 'locale' => @order.locale }
              )
              render json: { data: { order_id: @order.prefixed_id, email_queued: true } }, status: :accepted
            end

            private

            def payable_order?
              @order.completed_at.nil? && !@order.canceled?
            end

            def plunk_integration
              ::Spree::Integrations::Plunk.active.find_by(store_id: @order.store_id)
            end

            def render_unavailable
              render_error(
                code: Spree::Api::V3::ErrorHandler::ERROR_CODES[:validation_error],
                message: 'This order cannot receive a Plunk payment-link email with the current store settings.',
                status: :unprocessable_content
              )
            end
          end
        end
      end
    end
  end
end
