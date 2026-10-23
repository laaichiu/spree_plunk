module SpreePlunk
  module Generators
    class InstallGenerator < Rails::Generators::Base
      class_option :migrate,
                   type: :boolean,
                   default: true,
                   desc: 'Run pending migrations after installing any spree_plunk migrations'

      def add_migrations
        unless extension_has_migrations?
          say_status :skip, 'No spree_plunk migrations to install', :yellow
          return
        end

        rake 'railties:install:migrations FROM=spree_plunk'
      end

      def run_migrations
        return unless options[:migrate]
        return unless extension_has_migrations?

        rake 'db:migrate'
      end

      def print_next_steps
        say <<~MESSAGE

          spree_plunk is installed.

          Next steps:
            1. Open Spree Admin and configure the Plunk integration for your store.
            2. Add the Plunk base URL and secret API key.
            3. Verify contact sync and event tracking in a non-production environment first.
        MESSAGE
      end

      private

      def extension_has_migrations?
        Dir.glob(File.join(extension_migrations_path, '*.rb')).any?
      end

      def extension_migrations_path
        File.expand_path('../../../../db/migrate', __dir__)
      end
    end
  end
end
