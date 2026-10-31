require 'spec_helper'

RSpec.describe SpreePlunk::TransactionalEmailSubscriber do
  include ActiveJob::TestHelper

  let(:store) { create(:store) }
  let(:integration) do
    create(
      :plunk_integration,
      store: store,
      preferred_transactional_email_enabled: true,
      preferred_digital_asset_ready_email_enabled: true,
      preferred_company_invitation_email_enabled: true,
      preferred_data_request_confirmation_email_enabled: true,
      preferred_data_export_ready_email_enabled: true,
      preferred_seller_approved_email_enabled: true,
      preferred_seller_suspended_email_enabled: true,
      preferred_seller_rejected_email_enabled: true
    )
  end
  let(:subscriber) { described_class.new }

  before do
    integration
    allow(Spree::Store).to receive(:default).and_return(store)
    clear_enqueued_jobs
  end

  it 'sends ready digital links from order placement and on an explicit resend' do
    order = create(:completed_order_with_totals, store: store, email: 'buyer@example.com')
    line_item = order.line_items.first
    digital_asset = create(:digital_asset, variant: line_item.variant)
    create(:digital_link, line_item: line_item, digital_asset: digital_asset)
    order.reload

    placed_event = Spree::Event.new(
      name: 'order.placed',
      store_id: store.id,
      payload: { 'id' => order.to_param }
    )

    expect {
      subscriber.send(:handle_order_completed, placed_event)
    }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
      integration.id,
      SpreePlunk::TransactionalEmailTypes::DIGITAL_ASSET_READY,
      Spree::Order.name,
      order.id,
      order.email,
      { 'id' => order.to_param, 'resend' => false }
    )

    clear_enqueued_jobs
    resend_event = Spree::Event.new(
      name: 'order.resend_digital_links_email',
      store_id: store.id,
      payload: { 'id' => order.to_param }
    )

    expect {
      subscriber.send(:handle_digital_links_resend, resend_event)
    }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
      integration.id,
      SpreePlunk::TransactionalEmailTypes::DIGITAL_ASSET_READY,
      Spree::Order.name,
      order.id,
      order.email,
      { 'id' => order.to_param, 'resend' => true }
    )
  end

  it 'sends company invitation events only while the invitation is pending' do
    invitation = create(:company_invitation, company: create(:company, store: store), email: 'buyer@example.com')
    event = Spree::Event.new(
      name: 'company_invitation.created',
      store_id: store.id,
      payload: { 'id' => invitation.to_param }
    )

    expect {
      subscriber.send(:handle_company_invitation_created, event)
    }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
      integration.id,
      SpreePlunk::TransactionalEmailTypes::COMPANY_INVITATION,
      Spree::CompanyInvitation.name,
      invitation.id,
      invitation.email,
      { 'id' => invitation.to_param }
    )

    invitation.update!(revoked_at: Time.current)
    expect {
      subscriber.send(:handle_company_invitation_created, event)
    }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)
  end

  it 'sends data-request confirmation and access-export events with the current resources' do
    customer = create(:customer, email: 'buyer@example.com')
    confirmation = create(:data_request, :awaiting_confirmation, store: store, customer: customer)
    confirmation_event = Spree::Event.new(
      name: 'data_request.confirmation_requested',
      store_id: store.id,
      payload: { 'id' => confirmation.to_param, 'confirmation_token' => 'confirm-token' }
    )

    expect {
      subscriber.send(:handle_data_request_confirmation, confirmation_event)
    }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
      integration.id,
      SpreePlunk::TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION,
      Spree::DataRequest.name,
      confirmation.id,
      confirmation.email,
      confirmation_event.payload
    )

    export = create(:data_request, :completed, store: store, customer: customer)
    export.export_file.attach(
      io: StringIO.new('private export'),
      filename: 'export.zip',
      content_type: 'application/zip'
    )
    export_event = Spree::Event.new(
      name: 'data_request.completed',
      store_id: store.id,
      payload: { 'id' => export.to_param }
    )

    expect {
      subscriber.send(:handle_data_request_completed, export_event)
    }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
      integration.id,
      SpreePlunk::TransactionalEmailTypes::DATA_EXPORT_READY,
      Spree::DataRequest.name,
      export.id,
      export.email,
      export_event.payload
    )
  end

  %w[approved suspended rejected].each do |state|
    it "hands off seller #{state} lifecycle emails to the seller recipients" do
      seller = create(:seller, store: store, contact_email: 'owner@example.com')
      staffer = create(:admin_user, :without_admin_role, email: 'member@example.com')
      seller.add_user(staffer)
      email_type = SpreePlunk::TransactionalEmailTypes.const_get("SELLER_#{state.upcase}")
      event = Spree::Event.new(
        name: "seller.#{state}",
        store_id: store.id,
        payload: { 'id' => seller.to_param }
      )

      expect {
        subscriber.send("handle_seller_#{state}", event)
      }.to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob).with(
        integration.id,
        email_type,
        Spree::Seller.name,
        seller.id,
        nil,
        { 'id' => seller.to_param, 'email_type' => email_type }
      )
    end
  end

  it 'does not enqueue seller lifecycle mail when there is no recipient' do
    seller = create(:seller, store: store, contact_email: nil)
    event = Spree::Event.new(
      name: 'seller.approved',
      store_id: store.id,
      payload: { 'id' => seller.to_param }
    )

    expect {
      subscriber.send(:handle_seller_approved, event)
    }.not_to have_enqueued_job(SpreePlunk::SendTransactionalEmailJob)
  end
end
