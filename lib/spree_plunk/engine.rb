module SpreePlunk
  class Engine < Rails::Engine
    require 'spree/core'

    isolate_namespace Spree
    engine_name 'spree_plunk'

    config.generators do |g|
      g.test_framework :rspec
    end

    config.paths.add 'app/subscribers', eager_load: true

    initializer 'spree_plunk.environment', before: :load_config_initializers do |_app|
      SpreePlunk::Config = SpreePlunk::Configuration.new
    end

    # Spree 6 owns the editable-template registry and Admin API in core. The
    # optional spree_emails gem normally registers its customer email views;
    # register the subset that this integration sends so merchants can edit
    # them in the dashboard without installing its Action Mailer subscribers.
    initializer 'spree_plunk.editable_email_templates' do
      {
        'spree/order_mailer/confirm_email' => 'SpreePlunk::EmailTemplateSamples::OrderConfirmation',
        'spree/order_group_mailer/confirm_email' => 'SpreePlunk::EmailTemplateSamples::OrderGroupConfirmation',
        'spree/order_mailer/cancel_email' => 'SpreePlunk::EmailTemplateSamples::OrderCancellation',
        'spree/customer_mailer/password_reset_email' => 'SpreePlunk::EmailTemplateSamples::PasswordReset',
        'spree/newsletter_mailer/email_confirmation' => 'SpreePlunk::EmailTemplateSamples::NewsletterConfirmation',
        'spree/fulfillment_mailer/fulfilled_email' => 'SpreePlunk::EmailTemplateSamples::Fulfillment',
        'spree/return_mailer/refunded_email' => 'SpreePlunk::EmailTemplateSamples::Return'
      }.each do |key, sample|
        Spree.editable_email_templates.register(key, kind: :email, sample: sample)
      end

      # This layout is shipped by Spree core. Registering it makes its published
      # store override part of the same Plunk send path as the email body.
      Spree.editable_email_templates.register('layouts/spree/base_mailer', kind: :layout)

      # Keep the default email bodies previewable and publishable without the
      # optional spree_emails engine. These are the partials those bodies use.
      %w[line_item order_summary purchase_totals fulfillment_group summary_row].each do |partial|
        Spree.editable_email_templates.register("spree/shared/#{partial}", kind: :partial)
      end
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |path|
        Rails.configuration.cache_classes ? require(path) : load(path)
      end

      SpreePlunk::CustomerDecorator.install!
    end

    config.to_prepare(&method(:activate).to_proc)
  end
end
