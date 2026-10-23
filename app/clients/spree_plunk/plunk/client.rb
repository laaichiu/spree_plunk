require 'json'
require 'net/http'
require 'uri'

module SpreePlunk
  module Plunk
    class Client
      class Result < ::Spree::ServiceModule::Result; end

      def initialize(base_url:, secret_api_key:, open_timeout: nil, read_timeout: nil)
        @base_url = base_url
        @secret_api_key = secret_api_key
        @open_timeout = open_timeout || SpreePlunk::Config[:plunk_api_open_timeout]
        @read_timeout = read_timeout || SpreePlunk::Config[:plunk_api_read_timeout]
      end

      def get(path)
        request(Net::HTTP::Get, path)
      end

      def post(path, body, headers: {})
        request(Net::HTTP::Post, path, body, headers: headers)
      end

      def patch(path, body)
        request(Net::HTTP::Patch, path, body)
      end

      private

      attr_reader :base_url, :secret_api_key, :open_timeout, :read_timeout

      def request(klass, path, body = nil, headers: {})
        uri = build_uri(path)
        http_request = klass.new(uri)
        http_request['Accept'] = 'application/json'
        http_request['Authorization'] = "Bearer #{secret_api_key}"
        http_request['Content-Type'] = 'application/json'
        headers.each { |name, value| http_request[name] = value }
        http_request.body = JSON.generate(body) if body

        response = http(uri).request(http_request)

        Result.new(
          response.is_a?(Net::HTTPSuccess),
          {
            status: response.code.to_i,
            body: parse_body(response.body),
            headers: response.to_hash
          }
        )
      rescue StandardError => e
        Result.new(
          false,
          {
            status: nil,
            body: { 'error' => e.message },
            headers: {}
          }
        )
      end

      def build_uri(path)
        URI.join(normalized_base_url, normalized_path(path))
      end

      def normalized_base_url
        @normalized_base_url ||= base_url.end_with?('/') ? base_url : "#{base_url}/"
      end

      def normalized_path(path)
        path.to_s.sub(%r{\A/+}, '')
      end

      def http(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |client|
          client.use_ssl = uri.scheme == 'https'
          client.open_timeout = open_timeout
          client.read_timeout = read_timeout
        end
      end

      def parse_body(body)
        return nil if body.nil? || body.empty?

        JSON.parse(body)
      rescue JSON::ParserError
        body
      end
    end
  end
end
