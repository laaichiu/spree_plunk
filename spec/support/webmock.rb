require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.before do
    # Most integration factories create active records, whose Spree 6
    # activation validation performs a connection check. Keep those tests
    # offline; examples that exercise can_connect? provide their own response.
    stub_request(:get, 'https://next-api.useplunk.com/contacts?limit=1')
      .to_return(status: 200, body: '{"contacts":[]}', headers: { 'Content-Type' => 'application/json' })
  end
end
