ENV['ENV'] = ENV['RAILS_ENV'] = ENV['RACK_ENV'] = 'test'

require 'factory_girl'
require 'database_cleaner'
require 'final-api'
require 'final-api/v1/http'
require 'rack/test'
require 'factories'
require 'sidekiq/testing'
require 'test_aggregation'


FinalAPI.setup
FinalAPI.logger = Logger.new(StringIO.new)



DatabaseCleaner.clean_with(:truncation)
DatabaseCleaner.strategy = :transaction

RSpec.configure do |config|

  config.around(:each) do |example|
    Sidekiq::Worker.clear_all
    DatabaseCleaner.cleaning do
      example.run
    end
  end


  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.filter_run :focus
  config.run_all_when_everything_filtered = true
end
