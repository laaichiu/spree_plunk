require 'spec_helper'

RSpec.describe SpreePlunk::SendTransactionalEmail do
  let(:store) { create(:store, name: 'Example Store') }
  let(:integration) do
    create(
      :plunk_integration,
      store: store,
      preferred_transactional_email_enabled: true,
      preferred_digital_asset_ready_email_enabled: true,
      preferred_company_invitation_email_enabled: true,
      preferred_data_request_confirmation_email_enabled: true,
      preferred_data_export_ready_email_enabled: true,
      preferred_payment_link_email_enabled: true,
      preferred_seller_approved_email_enabled: true,
      preferred_seller_suspended_email_enabled: true,
      preferred_seller_rejected_email_enabled: true
    )
  end

  before do
    stub_request(:post, 'https://next-api.useplunk.com/v1/send')
      .to_return(status: 200, body: '{"id":"email_123"}', headers: { 'Content-Type' => 'application/json' })
  end

  def send_email(type, resource:, email: nil, event_payload: {})
    described_class.call(
      plunk_integration: integration,
      email_type: type,
      resource: resource,
      email: email,
      event_payload: event_payload
    )
  end

  def last_payload
    JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
  end

  it 'sends digital download links as non-persistent Plunk template data' do
    order = create(:order_with_line_items, store: store, email: 'buyer@example.com')
    line_item = order.line_items.first
    digital_asset = create(:digital_asset, variant: line_item.variant)
    digital_link = create(:digital_link, line_item: line_item, digital_asset: digital_asset)
    order.reload

    result = send_email(
      SpreePlunk::TransactionalEmailTypes::DIGITAL_ASSET_READY,
      resource: order,
      email: order.email,
      event_payload: { 'resend' => true }
    )

    expect(result).to be_success
    expect(result.value).not_to include(skipped: true)
    payload = last_payload
    expect(payload.dig('data', 'downloads', 'persistent')).to be(false)
    expect(payload.dig('data', 'downloads', 'value').first['url']).to include(digital_link.token)
    expect(payload.dig('data', 'resend')).to eq('value' => true, 'persistent' => false)
  end

  it 'sends company invitation URLs as non-persistent data and skips revoked invitations' do
    invitation = create(:company_invitation, company: create(:company, store: store), email: 'buyer@example.com')

    result = send_email(SpreePlunk::TransactionalEmailTypes::COMPANY_INVITATION, resource: invitation)

    expect(result).to be_success
    expect(result.value).not_to include(skipped: true)
    payload = last_payload
    expect(payload.dig('data', 'accept_url', 'value')).to include('token=', invitation.token)
    expect(payload.dig('data', 'accept_url', 'persistent')).to be(false)

    invitation.update!(revoked_at: Time.current)
    skipped = send_email(SpreePlunk::TransactionalEmailTypes::COMPANY_INVITATION, resource: invitation)
    expect(skipped.value).to include(skipped: true, reason: 'company_invitation_not_pending')
  end

  it 'sends data request confirmation URLs without persisting the confirmation credential' do
    customer = create(:customer, email: 'buyer@example.com')
    request = create(:data_request, :awaiting_confirmation, store: store, customer: customer, email: customer.email)
    token = request.generate_token_for(:confirmation)

    result = send_email(
      SpreePlunk::TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION,
      resource: request,
      event_payload: { 'confirmation_token' => token }
    )

    expect(result).to be_success
    expect(result.value).not_to include(skipped: true)
    payload = last_payload
    expect(payload.dig('data', 'confirmation_url', 'value')).to include(token)
    expect(payload.dig('data', 'confirmation_url', 'persistent')).to be(false)
  end

  it 'uses Spree signed download URL generation for subject access exports' do
    customer = create(:customer, email: 'buyer@example.com')
    request = create(:data_request, :completed, store: store, customer: customer, email: customer.email)
    request.export_file.attach(io: StringIO.new('private export'), filename: 'export.zip', content_type: 'application/zip')
    download_url = Spree::Api::DataRequestUrls.download_url(request, store.formatted_url)

    result = send_email(SpreePlunk::TransactionalEmailTypes::DATA_EXPORT_READY, resource: request)

    expect(result).to be_success
    expect(result.value).not_to include(skipped: true)
    payload = last_payload
    expect(payload.dig('data', 'download_url')).to eq('value' => download_url, 'persistent' => false)
  end

  it 'sends payment links only for payable draft orders and keeps the order token transient' do
    order = create(:order, store: store, email: 'buyer@example.com')

    result = send_email(SpreePlunk::TransactionalEmailTypes::PAYMENT_LINK, resource: order)

    expect(result).to be_success
    expect(result.value).not_to include(skipped: true)
    payload = last_payload
    expect(payload.dig('data', 'payment_url', 'value')).to include("/checkout/#{order.token}/payment")
    expect(payload.dig('data', 'payment_url', 'persistent')).to be(false)

    order.update_column(:completed_at, Time.current)
    skipped = send_email(SpreePlunk::TransactionalEmailTypes::PAYMENT_LINK, resource: order)
    expect(skipped.value).to include(skipped: true, reason: 'order_not_payable')
  end

  it 'sends seller lifecycle notifications to seller users and contact email under the seller mail switch' do
    seller = create(:seller, :approved, store: store, contact_email: 'owner@example.com')
    user = create(:admin_user, :without_admin_role, email: 'member@example.com')
    seller.add_user(user)

    result = send_email(
      SpreePlunk::TransactionalEmailTypes::SELLER_APPROVED,
      resource: seller,
      event_payload: { 'email_type' => SpreePlunk::TransactionalEmailTypes::SELLER_APPROVED }
    )

    expect(result).to be_success
    expect(result.value).not_to include(skipped: true)
    expect(last_payload['to']).to eq(['member@example.com', 'owner@example.com'])

    store.update!(preferred_send_seller_transactional_emails: false)
    skipped = send_email(
      SpreePlunk::TransactionalEmailTypes::SELLER_APPROVED,
      resource: seller,
      event_payload: { 'email_type' => SpreePlunk::TransactionalEmailTypes::SELLER_APPROVED }
    )
    expect(skipped.value).to include(skipped: true, reason: 'seller_transactional_emails_disabled')
  end
end
