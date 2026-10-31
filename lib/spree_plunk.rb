require 'spree_core'
require 'spree_plunk/configuration'
require 'spree_plunk/internal_event_names'
require 'spree_plunk/engine'
require 'spree_plunk/event_names'
require 'spree_plunk/event_context'
require 'spree_plunk/sync_error'
require 'spree_plunk/transactional_email_types'
require 'spree_plunk/version'

module SpreePlunk
  mattr_accessor :queue

  def self.queue
    @@queue ||= Spree.queues.default
  end
end
