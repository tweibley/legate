# frozen_string_literal: true

require 'spec_helper'
require 'adk/configuration/webhooks'
require 'adk/session_service/in_memory' # Corrected path

RSpec.describe ADK::Configuration::Webhooks do
  subject(:config) { described_class.new }

  describe '#initialize' do
    it 'sets default values' do
      expect(config.listener_enabled).to be true
      expect(config.listen_address).to eq('127.0.0.1')
      expect(config.listen_port).to eq(9292)
      expect(config.base_path).to eq('/webhooks')
      expect(config.enable_dynamic_agent_handler).to be true
      expect(config.dynamic_agent_route_pattern).to eq('/agents/:agent_name/trigger')
      expect(config.global_validator).to be_nil
      expect(config.global_secret).to be_nil
      expect(config.default_session_service).to be_nil
      expect(config.instance_variable_get(:@validators).keys).to contain_exactly(:hmac_sha256)
      expect(config.static_routes).to eq({})
    end

    # Redundant specific tests removed as they are covered by 'sets default values'
    # it 'sets listener_enabled to true' do ... end
    # it 'sets enable_dynamic_agent_handler to true' do ... end
    # ... other specific default tests ...
  end

  describe 'accessors' do
    it { is_expected.to respond_to(:listener_enabled=) }
    it { is_expected.to respond_to(:listen_address=) }
    it { is_expected.to respond_to(:listen_port=) }
    it { is_expected.to respond_to(:base_path=) }
    it { is_expected.to respond_to(:enable_dynamic_agent_handler=) }
    it { is_expected.to respond_to(:dynamic_agent_route_pattern=) }
    it { is_expected.to respond_to(:global_validator=) }
    it { is_expected.to respond_to(:global_secret=) }
    it { is_expected.to respond_to(:default_session_service=) }

    it 'allows setting default_session_service to a SessionService instance' do
      service = ADK::SessionService::InMemory.new
      config.default_session_service = service
      expect(config.default_session_service).to eq(service)
    end
  end

  describe '#register_validator' do
    let(:validator_proc) { ->(req, sec) { true } }

    it 'registers a validator with a block' do
      expect { config.register_validator(:my_validator, &validator_proc) }
        .to change { config.find_validator(:my_validator) }.from(nil).to(validator_proc)
    end

    it 'raises an error if no block is given' do
      expect { config.register_validator(:my_validator) }
        .to raise_error(ArgumentError, 'Validator requires a block.')
    end

    it 'raises an error if the name is already registered' do
      config.register_validator(:my_validator, &validator_proc)
      expect { config.register_validator(:my_validator) {} }
        .to raise_error(ArgumentError, 'Validator name :my_validator is already registered.')
    end
  end

  describe '#find_validator' do
    let(:validator_proc) { ->(req, sec) { true } }

    before do
      config.register_validator(:existing, &validator_proc)
    end

    it 'returns the proc for a registered validator' do
      expect(config.find_validator(:existing)).to eq(validator_proc)
    end

    it 'returns nil for an unregistered validator' do
      expect(config.find_validator(:non_existent)).to be_nil
    end
  end

  describe '#register_route' do
    let(:handler_proc) { ->(req) { [200, {}, ['OK']] } }
    let(:route_path) { 'GET /health' }

    it 'registers a route with a block' do
      expect { config.register_route(route_path) { |rc| rc.handler = handler_proc } }
        .to change { config.static_routes.key?(route_path) }.from(false).to(true)
    end

    it 'yields a RouteConfig object to the block' do
      yielded_config = nil
      config.register_route(route_path) { |rc| yielded_config = rc }
      expect(yielded_config).to be_a(ADK::Configuration::Webhooks::RouteConfig)
    end

    it 'stores the configured RouteConfig object' do
      config.register_route(route_path) do |rc|
        rc.handler = handler_proc
        rc.validator = :some_validator
        rc.secret = 'shhh'
      end
      route_config = config.static_routes[route_path]
      expect(route_config.handler).to eq(handler_proc)
      expect(route_config.validator).to eq(:some_validator)
      expect(route_config.secret).to eq('shhh')
    end

    it 'raises an error if no block is given' do
      expect { config.register_route(route_path) }
        .to raise_error(ArgumentError, 'Route registration requires a block.')
    end

    it 'raises an error if the path is already registered' do
      config.register_route(route_path) {}
      expect { config.register_route(route_path) {} }
        .to raise_error(ArgumentError, "Route path \"#{route_path}\" is already registered.")
    end
  end

  describe '#static_routes' do
    it 'returns a hash of registered routes' do
      config.register_route('GET /a') {}
      config.register_route('POST /b') {}
      expect(config.static_routes.keys).to contain_exactly('GET /a', 'POST /b')
      expect(config.static_routes.values).to all(be_a(ADK::Configuration::Webhooks::RouteConfig))
    end

    it 'returns a duplicate of the internal hash' do
      internal_routes = config.instance_variable_get(:@static_routes)
      returned_routes = config.static_routes
      expect(returned_routes).to eq(internal_routes)
      expect(returned_routes).not_to be(internal_routes)
      # Modify the returned hash and check the original is unchanged
      returned_routes['GET /new'] = 'test'
      expect(config.static_routes).not_to have_key('GET /new')
    end
  end

  describe ADK::Configuration::Webhooks::RouteConfig do
    subject(:route_config) { described_class.new }

    it { is_expected.to respond_to(:handler) }
    it { is_expected.to respond_to(:handler=) }
    it { is_expected.to respond_to(:validator) }
    it { is_expected.to respond_to(:validator=) }
    it { is_expected.to respond_to(:secret) }
    it { is_expected.to respond_to(:secret=) }

    it 'initializes handler to nil' do
      expect(route_config.handler).to be_nil
    end

    it 'initializes validator to nil' do
      expect(route_config.validator).to be_nil
    end

    it 'initializes secret to nil' do
      expect(route_config.secret).to be_nil
    end
  end
end
