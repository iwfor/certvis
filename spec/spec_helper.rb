# frozen_string_literal: true

require_relative '../lib/certvis'
require_relative 'support/tls_test_server'

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
