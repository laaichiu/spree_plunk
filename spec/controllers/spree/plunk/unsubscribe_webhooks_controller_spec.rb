require 'spec_helper'

RSpec.describe Spree::Plunk::UnsubscribeWebhooksController, type: :controller do
  routes { Spree::Core::Engine.routes }

  let(:store) { Spree::Store.default }
  let(:integration) do
    create(
      :plunk_integration,
      store: store,
      preferred_unsubscribe_webhook_enabled: true,
      preferred_unsubscribe_webhook_authorization_token: 'whsec_test'
    )
  end

  describe 'POST #create' do
    it 'returns not found while the intake stays disabled' do
      integration.update!(
        preferred_unsubscribe_webhook_enabled: false,
        preferred_unsubscribe_webhook_authorization_token: nil
      )

      request.headers['Authorization'] = 'Bearer whsec_test'

      post :create, params: {
        integration_id: integration.to_param,
        contact: { email: 'newsletter@example.com', subscribed: false }
      }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns unauthorized when the bearer token does not match' do
      request.headers['Authorization'] = 'Bearer wrong-token'

      post :create, params: {
        integration_id: integration.to_param,
        contact: { email: 'newsletter@example.com', subscribed: false }
      }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'acknowledges a valid unsubscribe payload and removes the local subscriber' do
      subscriber = create(:newsletter_subscriber, :verified, email: 'newsletter@example.com')
      request.headers['Authorization'] = 'Bearer whsec_test'

      post :create, params: {
        integration_id: integration.to_param,
        contact: { email: subscriber.email, subscribed: false }
      }, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(Spree::NewsletterSubscriber.find_by(id: subscriber.id)).to be_nil
      end
    end

    it 'acknowledges a valid subscribe payload and restores the local subscriber state' do
      user = create(:customer, email: 'newsletter@example.com', accepts_email_marketing: false)
      request.headers['Authorization'] = 'Bearer whsec_test'

      post :create, params: {
        integration_id: integration.to_param,
        contact: { email: user.email, subscribed: true }
      }, as: :json

      subscriber = Spree::NewsletterSubscriber.find_by(email: user.email)

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(subscriber).to be_present
        expect(subscriber).to be_verified
        expect(user.reload.accepts_email_marketing).to be(true)
      end
    end

    it 'returns ok for unmatched emails so the intake stays safely idempotent' do
      request.headers['Authorization'] = 'Bearer whsec_test'

      post :create, params: {
        integration_id: integration.to_param,
        contact: { email: 'missing@example.com', subscribed: false }
      }, as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'returns bad request when the webhook body is not valid JSON' do
      request.headers['Authorization'] = 'Bearer whsec_test'
      request.headers['CONTENT_TYPE'] = 'application/json'

      expect {
        post :create,
             params: { integration_id: integration.to_param },
             body: '{"contact":'
      }.not_to raise_error

      expect(response).to have_http_status(:bad_request)
    end
  end
end
