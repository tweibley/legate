require 'spec_helper'
require 'adk/web/routes/authentication_routes'
require 'ostruct'
require 'logger'

# Dummy class to include the module
class AuthRoutesTester
  # Mock helpers method to define methods on the class
  def self.helpers(&block)
    class_eval(&block)
  end

  # Mock route defining methods
  def self.get(*args); end
  def self.post(*args); end
  def self.put(*args); end
  def self.delete(*args); end

  # Include the module which calls registered
  extend ADK::Web::AuthenticationRoutes

  # Mock logger
  def logger
    @logger ||= Logger.new(nil)
  end

  # Mock instance_variable_set
  def instance_variable_set(name, value)
    @instance_variables ||= {}
    @instance_variables[name] = value
  end
end

RSpec.describe ADK::Web::AuthenticationRoutes do
  let(:tester) { AuthRoutesTester.new }

  # Trigger the registration to define the helper methods
  before(:all) do
    ADK::Web::AuthenticationRoutes.registered(AuthRoutesTester)
  end

  describe '#test_authenticated_api_call' do
    let(:auth_manager) { instance_double('ADK::Auth::Manager') }
    let(:scheme) { OpenStruct.new(scheme_type: :api_key) }
    let(:credential) { { api_key: 'secret', location: 'header', name: 'X-API-Key' } }

    before do
      allow(ADK::Auth::Manager).to receive(:instance).and_return(auth_manager)
      allow(auth_manager).to receive(:get_scheme).with(:my_scheme).and_return(scheme)
      allow(auth_manager).to receive(:get_credential).with(:my_cred).and_return(credential)

      allow(tester).to receive(:mapping_scheme_credential_compatible?).and_return(true)
    end

    it 'blocks requests to a local URL (SSRF protection)' do
      url = 'http://127.0.0.1:8080/sensitive'

      # We expect Net::HTTP.new NOT to be called
      expect(Net::HTTP).not_to receive(:new)

      result = tester.test_authenticated_api_call(url, 'my_scheme', 'my_cred')

      expect(result[:success]).to be false
      expect(result[:error]).to include('Invalid or internal URL')
    end

    it 'allows requests to a public URL' do
      url = 'http://example.com/api'

      # Mock Resolv to return a safe IP
      allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])

      # Expect Net::HTTP to be called with hostname
      http_mock = instance_double(Net::HTTP)
      expect(Net::HTTP).to receive(:new).with('example.com', 80).and_return(http_mock)
      allow(http_mock).to receive(:use_ssl=)
      allow(http_mock).to receive(:read_timeout=)

      response = instance_double(Net::HTTPResponse, code: '200', message: 'OK', to_hash: {}, body: 'safe')
      expect(http_mock).to receive(:request).and_return(response)

      result = tester.test_authenticated_api_call(url, 'my_scheme', 'my_cred')
      expect(result[:success]).to be true
      expect(result[:body_preview]).to eq('safe')
    end
  end
end
