require 'spec_helper'
require 'final-api/app'

describe FinalAPI::V1::Http::DDTF_Build do
  let(:fake_user) { double('fake_user', name: 'quux') }
  let(:params) do
    double(
            'fake_build',
            commit: 'foo',
            request: double('fake_request', message: 'bar'),
            id: 'bax',
            name: 'qux',
            build_info: 'quux',
            state: 'garply',
            created_at: 'foo',
            canceled_at: 'foop',
            started_at: 'bar',
            stopped_by: fake_user,
            execution_logs: [],
            owner: fake_user,
            parts_groups: [],
            matrix: {},
            config: {}
    )
  end
  let(:subject) do
    FinalAPI::V1::Http::DDTF_Build.new(params)
  end
  let(:fake_step) do
    {
      :result => 'foo',
      :data => {
        :status => ''
      }
    }
  end

  context '#test_data' do
    {
      %w{passed failed Passed Failed PASSED FAILED} => 'Finished',
      %w{created Created CREATED} => 'Configured',
      %w{received Received RECEIVED} => 'Pending',
      %w{started Started STARTED} => 'Running',
      %w{canceled Canceled CANCELED} => 'Stopped',
      %w{errored Errored ERRORED} => 'Aborted',
      [nil, ''] => 'Unbeknownst',
    }.each do |k, v|
      context "returns correct state: #{v}" do
        k.each do |state|
          it "for #{state}" do
            allow(params).to receive(:state) { state }
            expect(subject.test_data['status']).to eq v
          end
        end
      end
    end
  end

  context '#atom_response' do
    it 'returns string id' do
      allow(params).to receive(:id) { 2334568786432234 }
      expect(String === subject.atom_response[:id]).to be true
    end
  end

  context '#state2api_v1status' do
    it 'returns NotSet when bug occured' do
      fake_step[:result] = 'pending'
      fake_step[:data][:status] = nil
      expect(subject.send(:state2api_v1status, fake_step)).to eq 'NotSet'
    end

    {
      { result: 'created', data: {} } => 'NotSet',
      { result: 'blocked', data: {} } => 'NotTested',
      { result: 'passed', data: {}  } => 'Passed',
      { result: 'failed', data: {}  } => 'Failed',
      { result: 'failed', data: { 'status' => 'known_bug'} } => 'KnownBug',
      { result: 'pending', data: { 'status' => 'not_performed'} } => 'NotPerformed',
      { result: 'pending', data: { 'status' => 'skipped'} } => 'Skipped',
    }.each do |k, v|
      it "returns #{v} for #{k}" do
        expect(subject.send(:state2api_v1status, k)).to eq v
      end
    end
  end

  context '#execution_logs' do
    let(:time) { Time.now }
    let(:first_message) do
      ExecutionLog.new ({
        position: 1,
        timestamp: time,
        message: 'first message'
      })
    end

    before :each do
      allow(params).to receive_message_chain(:execution_logs) { [first_message] }
    end

    it 'returns array of messages' do
      expect(subject.execution_logs).to be_an_instance_of Array
    end

    it 'returns all message properties' do
      expect(subject.execution_logs.first).to include(:position, :timestamp, :message)
    end

    it 'returns timestamp in ISO-8601 format' do
      expect(subject.execution_logs.first[:timestamp]).to eq time.iso8601
    end
  end
end
