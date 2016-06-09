require 'spec_helper'
require 'final-api/app'

describe FinalAPI::Endpoint::DDTF do
  context "#get_field_from_runtime_config" do
    it 'parses protonid correctly when input is a hash' do
      rt2 = {
        foo: 'bar',
        baz: 'qux',
        protonid: 'quux'
      }
      result = FinalAPI::Endpoint::DDTF::DdtfHelpers
        .send(:get_field_from_runtime_config, rt2, 'protonid')
      expect(result).to eq('quux')
    end

    it 'parses protonid correctly when input is an array' do
      rt = [
        {definition: 'foo', value: 'bar'},
        {definition: 'baz', value: 'qux'},
        {definition: 'protonid', value: 'quux'},
      ]
      result = FinalAPI::Endpoint::DDTF::DdtfHelpers
        .send(:get_field_from_runtime_config, rt, 'protonid')
      expect(result).to eq('quux')
    end
  end
end
