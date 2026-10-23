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

  EMAIL_TYPES = [
    {
      type: SpreePlunk::TransactionalEmailTypes::PASSWORD_RESET,
      label: 'Password reset',
      enabled_preference: :preferred_password_reset_email_enabled,
      template_preference: :preferred_password_reset_template_id
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::NEWSLETTER_CONFIRMATION,
      label: 'Newsletter confirmation',
      enabled_preference: :preferred_newsletter_confirmation_email_enabled,
      template_preference: :preferred_newsletter_confirmation_template_id
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION,
      label: 'Order confirmation',
      enabled_preference: :preferred_order_confirmation_email_enabled,
      template_preference: :preferred_order_confirmation_template_id
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::ORDER_CONFIRMATION_RESEND,
      label: 'Order confirmation resend',
      enabled_preference: :preferred_order_confirmation_resend_email_enabled,
      template_preference: :preferred_order_confirmation_template_id
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::ORDER_CANCELLATION,
      label: 'Order cancellation',
      enabled_preference: :preferred_order_cancellation_email_enabled,
      template_preference: :preferred_order_cancellation_template_id
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::FULFILLMENT_FULFILLED,
      label: 'Fulfillment fulfilled',
      enabled_preference: :preferred_fulfillment_fulfilled_email_enabled,
      template_preference: :preferred_fulfillment_fulfilled_template_id
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::RETURN_REFUNDED,
      label: 'Return refund',
      enabled_preference: :preferred_return_refunded_email_enabled,
      template_preference: :preferred_return_refunded_template_id
    },
    {
      type: SpreePlunk::TransactionalEmailTypes::STORE_OWNER_NOTIFICATION,
      label: 'Store owner notification',
      enabled_preference: :preferred_store_owner_notification_email_enabled,
      template_preference: :preferred_store_owner_notification_template_id
    }
  ].freeze

  SPREE_EMAIL_MAILERS = [
    'Spree::OrderMailer',
    'Spree::FulfillmentMailer',
    'Spree::ReturnMailer',
    'Spree::NewsletterMailer'
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
    puts "  transactional master switch: #{on_off(integration.preferred_transactional_email_enabled)}"
    puts "  default sender domain: #{sender_domain(integration) || 'not configured'}"
    puts
  end

  def print_email_type_table(integration)
    puts 'transactional email switches'
    puts format('%-28s %-30s %-8s %-10s %-20s', 'Label', 'Type', 'Enabled', 'Template', 'Effective owner')
    puts '-' * 104

    EMAIL_TYPES.each do |email_type|
      enabled = integration.preferred_transactional_email_enabled &&
                integration.public_send(email_type.fetch(:enabled_preference))
      template_configured = integration.public_send(email_type.fetch(:template_preference)).present?
      owner = enabled ? 'spree_plunk' : 'none when spree_emails absent'

      puts format(
        '%-28s %-30s %-8s %-10s %-20s',
        email_type.fetch(:label),
        email_type.fetch(:type),
        on_off(enabled),
        yes_no(template_configured),
        owner
      )
    end
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
