require 'spec_helper'

RSpec.describe 'Admin order payment-link API', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:order) { create(:order_with_line_items, store: store, email: 'buyer@example.com') }
  let!(:integration) do
    create(
      :plunk_integration,
      store: store,
      active: true,
      preferred_transactional_email_enabled: true,
      preferred_payment_link_email_enabled: true
    )
  end

  it 'queues a payment-link email for an authorized incomplete order' do
    expect {
      post "/api/v3/admin/orders/#{order.prefixed_id}/payment_link", headers: headers
    }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
      integration.id,
      SpreePlunk::TransactionalEmailTypes::PAYMENT_LINK,
      Spree::Order.name,
      order.id,
      order.email,
      { 'store_id' => store.to_param, 'locale' => order.locale }
    )

    expect(response).to have_http_status(:accepted)
    expect(JSON.parse(response.body).dig('data', 'email_queued')).to be(true)
  end

  it 'does not enqueue when the integration email type is disabled' do
    integration.update!(preferred_payment_link_email_enabled: false)

    expect {
      post "/api/v3/admin/orders/#{order.prefixed_id}/payment_link", headers: headers
    }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'does not enqueue for a completed order' do
    order.update_column(:completed_at, Time.current)

    expect {
      post "/api/v3/admin/orders/#{order.prefixed_id}/payment_link", headers: headers
    }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'requires order-write authorization' do
    reader = create(:admin_user, :without_admin_role)
    role = create(:role, name: 'Order reader', resource: store, permissions: ['read_orders'])
    reader.spree_roles << role
    token = Spree::Api::V3::TestingSupport.generate_jwt(
      reader,
      audience: Spree::Api::V3::JwtAuthentication::JWT_AUDIENCE_ADMIN
    )
    reader_headers = api_key_headers.merge('Authorization' => "Bearer #{token}")

    expect {
      post "/api/v3/admin/orders/#{order.prefixed_id}/payment_link", headers: reader_headers
    }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)

    expect(response).to have_http_status(:forbidden)
  end
end
