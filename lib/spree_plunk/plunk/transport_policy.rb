require 'ipaddr'

module SpreePlunk
  module Plunk
    module TransportPolicy
      module_function

      def valid_uri?(uri)
        !uri.host.to_s.empty? && uri.userinfo.nil? && valid_transport?(uri)
      end

      def valid_transport?(uri)
        scheme = uri.scheme.to_s.downcase
        scheme == 'https' || (scheme == 'http' && loopback_host?(uri.host))
      end

      def loopback_host?(host)
        normalized_host = host.to_s.downcase.delete_prefix('[').delete_suffix(']').delete_suffix('.')
        return true if normalized_host == 'localhost'

        IPAddr.new(normalized_host).loopback?
      rescue IPAddr::InvalidAddressError
        false
      end
    end
  end
end
