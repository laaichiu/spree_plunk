#!/usr/bin/env ruby
# frozen_string_literal: true

unless defined?(Rails)
  require 'bundler/setup'

  ENV['RAILS_ENV'] ||= 'test'
  ENV.delete('HTTP_PROXY')

  require_relative '../spec/dummy/config/environment'
end

module InspectTransactionalEmailHandoff
  module_function

  # This report covers event-triggered handoffs. Explicit Admin API sends are
  # outside the `spree_emails` subscriber ownership check.
  EMAIL_TYPES = [
    {
      type: SpreePlunk::TransactionalEmailTypes::PASSWORD_RESET,
      label: 'Password reset',
      enabled_preference: :preferred_password_reset_email_enabled,
      template_preference: :preferred_password_reset_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::CustomerMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::NEWSLETTER_CONFIRMATION,
      label: 'Newsletter confirmation',
      enabled_preference: :preferred_newsletter_confirmation_email_enabled,
      template_preference: :preferred_newsletter_confirmation_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::NewsletterMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION,
      label: 'Order confirmation',
      enabled_preference: :preferred_order_confirmation_email_enabled,
      template_preference: :preferred_order_confirmation_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::OrderMailer', 'Spree::OrderGroupMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND,
      label: 'Order confirmation resend',
      enabled_preference: :preferred_order_confirmation_resend_email_enabled,
      template_preference: :preferred_order_confirmation_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::OrderMailer', 'Spree::OrderGroupMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::ORDER_CANCELLATION,
      label: 'Order cancellation',
      enabled_preference: :preferred_order_cancellation_email_enabled,
      template_preference: :preferred_order_cancellation_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::OrderMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::FULFILLMENT_FULFILLED,
      label: 'Fulfillment fulfilled',
      enabled_preference: :preferred_fulfillment_fulfilled_email_enabled,
      template_preference: :preferred_fulfillment_fulfilled_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::FulfillmentMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::RETURN_REFUNDED,
      label: 'Return refund',
      enabled_preference: :preferred_return_refunded_email_enabled,
      template_preference: :preferred_return_refunded_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::ReturnMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::STORE_OWNER_NOTIFICATION,
      label: 'Store owner notification',
      enabled_preference: :preferred_store_owner_notification_email_enabled,
      template_preference: :preferred_store_owner_notification_template_id,
      store_gate: :operator,
      store_requirement: :new_order_notifications_email,
      spree_mailers: ['Spree::OrderMailer', 'Spree::OrderGroupMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::DIGITAL_ASSET_READY,
      label: 'Digital downloads ready/resend',
      enabled_preference: :preferred_digital_asset_ready_email_enabled,
      template_preference: :preferred_digital_asset_ready_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::DigitalAssetMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::COMPANY_INVITATION,
      label: 'Company invitation',
      enabled_preference: :preferred_company_invitation_email_enabled,
      template_preference: :preferred_company_invitation_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::CompanyMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::DATA_REQUEST_CONFIRMATION,
      label: 'Data request confirmation',
      enabled_preference: :preferred_data_request_confirmation_email_enabled,
      template_preference: :preferred_data_request_confirmation_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::CustomerMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::DATA_EXPORT_READY,
      label: 'Data export ready',
      enabled_preference: :preferred_data_export_ready_email_enabled,
      template_preference: :preferred_data_export_ready_template_id,
      store_gate: :consumer,
      spree_mailers: ['Spree::CustomerMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::SELLER_APPROVED,
      label: 'Seller approved',
      enabled_preference: :preferred_seller_approved_email_enabled,
      template_preference: :preferred_seller_approved_template_id,
      store_gate: :seller,
      spree_mailers: ['Spree::SellerMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::SELLER_SUSPENDED,
      label: 'Seller suspended',
      enabled_preference: :preferred_seller_suspended_email_enabled,
      template_preference: :preferred_seller_suspended_template_id,
      store_gate: :seller,
      spree_mailers: ['Spree::SellerMailer']
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::SELLER_REJECTED,
      label: 'Seller rejected',
      enabled_preference: :preferred_seller_rejected_email_enabled,
      template_preference: :preferred_seller_rejected_template_id,
      store_gate: :seller,
      spree_mailers: ['Spree::SellerMailer']
    }
  ].freeze

  SPREE_EMAIL_MAILERS = [
    'Spree::OrderMailer',
    'Spree::OrderGroupMailer',
    'Spree::CustomerMailer',
    'Spree::FulfillmentMailer',
    'Spree::ReturnMailer',
    'Spree::NewsletterMailer',
    'Spree::DigitalAssetMailer',
    'Spree::CompanyMailer',
    'Spree::SellerMailer'
  ].freeze

  CORE_MAILERS_OUTSIDE_SPREE_EMAILS = [
    'Spree::InvitationMailer',
    'Spree::ExportMailer',
    'Spree::ReportMailer',
    'Spree::WebhookMailer'
  ].freeze

  def run!
    puts 'Spree Plunk transactional email handoff'
    puts
    puts "Rails env: #{Rails.env}"
    puts "spree_emails gem loaded: #{Gem.loaded_specs.key?('spree_emails')}"
    puts "spree_plunk gem loaded: #{Gem.loaded_specs.key?('spree_plunk')}"
    puts "Spree::Emails::Engine: #{constant_status('Spree::Emails::Engine')}"
    puts

    puts 'spree_emails mailer constants'
    SPREE_EMAIL_MAILERS.each { |constant_name| puts "  #{constant_name}: #{constant_status(constant_name)}" }
    puts

    puts 'core mailers outside spree_emails'
    CORE_MAILERS_OUTSIDE_SPREE_EMAILS.each { |constant_name| puts "  #{constant_name}: #{constant_status(constant_name)}" }
    puts

    integration = selected_integration
    unless integration
      puts 'No Spree::Integrations::Plunk record found.'
      puts 'Create one in Spree Admin before running a live handoff check.'
      return
    end

    print_integration_summary(integration)
    print_email_type_table(integration)
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError => e
    warn "Could not read database-backed Plunk preferences: #{e.class}: #{e.message.lines.first&.strip}"
    exit 1
  end

  def selected_integration
    scope = Spree::Integrations::Plunk.includes(:store).order(:id)

    if ENV['PLUNK_INTEGRATION_ID'].present?
      return scope.find_by(id: ENV['PLUNK_INTEGRATION_ID'])
    end

    if ENV['STORE_CODE'].present?
      return scope.detect { |integration| integration.store&.code == ENV['STORE_CODE'] }
    end

    scope.first
  end

  def print_integration_summary(integration)
    puts 'selected Plunk integration'
    puts "  id: #{integration.id}"
    puts "  store: #{integration.store&.code || integration.store&.name || 'unknown'}"
    puts "  integration active: #{on_off(integration.active?)}"
    puts "  transactional master switch: #{on_off(integration.preferred_transactional_email_enabled)}"
    puts "  consumer transactional emails: #{on_off(integration.store&.prefers_send_consumer_transactional_emails?)}"
    puts "  seller transactional emails: #{on_off(integration.store&.prefers_send_seller_transactional_emails?)}"
    puts "  default sender domain: #{sender_domain(integration) || 'not configured'}"
    puts
  end

  def print_email_type_table(integration)
    puts 'transactional email switches'
    puts format('%-29s %-30s %-8s %-10s %-13s %-28s', 'Label', 'Type', 'Plunk', 'Template', 'Store gate', 'Potential sender(s)')
    puts '-' * 124

    EMAIL_TYPES.each do |email_type|
      plunk_enabled = plunk_enabled?(integration, email_type)
      template_configured = integration.public_send(email_type.fetch(:template_preference)).present?
      store_gate = store_gate_enabled?(integration.store, email_type)

      puts format(
        '%-29s %-30s %-8s %-10s %-13s %-28s',
        email_type.fetch(:label),
        email_type.fetch(:type),
        on_off(plunk_enabled),
        yes_no(template_configured),
        on_off(store_gate),
        effective_sender(integration, email_type, plunk_enabled)
      )
    end
  end

  def plunk_enabled?(integration, email_type)
    integration.active? &&
      integration.preferred_transactional_email_enabled &&
      integration.public_send(email_type.fetch(:enabled_preference)) &&
      store_gate_enabled?(integration.store, email_type)
  end

  def store_gate_enabled?(store, email_type)
    return false unless store
    return false if email_type[:store_requirement] && store.public_send(email_type[:store_requirement]).blank?

    case email_type.fetch(:store_gate)
    when :consumer then store.prefers_send_consumer_transactional_emails?
    when :seller then store.prefers_send_seller_transactional_emails?
    when :operator then true
    else false
    end
  end

  def effective_sender(integration, email_type, plunk_enabled)
    spree_emails_enabled = Gem.loaded_specs.key?('spree_emails') &&
                           email_type.fetch(:spree_mailers).any? { |mailer| constant_status(mailer) != 'missing' } &&
                           store_gate_enabled?(integration.store, email_type)

    return 'both (duplicate risk)' if plunk_enabled && spree_emails_enabled
    return 'spree_plunk' if plunk_enabled
    return 'spree_emails' if spree_emails_enabled

    'none configured'
  end

  def sender_domain(integration)
    sender = integration.preferred_default_from_email.presence || integration.store&.mail_from_address
    return if sender.blank? || !sender.include?('@')

    sender.split('@', 2).last
  end

  def constant_status(constant_name)
    binding.eval("defined?(#{constant_name})") || 'missing'
  end

  def on_off(value)
    value ? 'ON' : 'OFF'
  end

  def yes_no(value)
    value ? 'yes' : 'no'
  end
end

InspectTransactionalEmailHandoff.run!
