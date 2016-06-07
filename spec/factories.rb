require 'travis/testing/factories'

FactoryGirl.define do
  factory :test_step do
    description 'Test step'
  end

  factory :test_case do
    description 'Test case'
  end

  factory :build_customized, parent: :build do
    sequence(:name) { |n| "foo #{n} bar baz qux quux #{n}" }
    sequence(:build_info) { |n| "qux #{n} description" }
    sequence(:state) { |n| (n % 3 == 0) ? 'created' : 'passed' }
  end
end
