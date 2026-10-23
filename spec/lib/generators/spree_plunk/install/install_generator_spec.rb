require 'spec_helper'
require 'generators/spree_plunk/install/install_generator'
require 'fileutils'
require 'tmpdir'

RSpec.describe SpreePlunk::Generators::InstallGenerator do
  let(:destination_root) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(destination_root) if File.exist?(destination_root)
  end

  it 'defines a migrate option enabled by default' do
    expect(described_class.class_options.fetch(:migrate).default).to be(true)
  end

  describe '#add_migrations' do
    it 'discovers the extension migration files' do
      generator = described_class.new([], {}, destination_root: destination_root)

      expect(generator.send(:extension_has_migrations?)).to be(true)
    end

    it 'installs migrations when the extension provides them' do
      generator = described_class.new([], {}, destination_root: destination_root)

      allow(generator).to receive(:extension_has_migrations?).and_return(true)
      expect(generator).to receive(:rake).with('railties:install:migrations FROM=spree_plunk')

      generator.add_migrations
    end

    it 'prints a skip message when there are no migrations to install' do
      generator = described_class.new([], {}, destination_root: destination_root)

      allow(generator).to receive(:extension_has_migrations?).and_return(false)
      expect(generator).to receive(:say_status).with(:skip, 'No spree_plunk migrations to install', :yellow)
      expect(generator).not_to receive(:rake)

      generator.add_migrations
    end
  end

  describe '#run_migrations' do
    it 'runs db:migrate when migrate is enabled and migrations exist' do
      generator = described_class.new([], { migrate: true }, destination_root: destination_root)

      allow(generator).to receive(:extension_has_migrations?).and_return(true)
      expect(generator).to receive(:rake).with('db:migrate')

      generator.run_migrations
    end

    it 'skips db:migrate when migrate is disabled' do
      generator = described_class.new([], { migrate: false }, destination_root: destination_root)

      expect(generator).not_to receive(:rake)

      generator.run_migrations
    end
  end

  describe '#print_next_steps' do
    it 'prints the non-interactive next-step banner' do
      generator = described_class.new([], {}, destination_root: destination_root)

      expect(generator).to receive(:say).with(include('spree_plunk is installed.', 'Open Spree Admin and configure the Plunk integration for your store.'))

      generator.print_next_steps
    end
  end
end
