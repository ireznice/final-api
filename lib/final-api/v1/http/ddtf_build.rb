require 'active_support/core_ext/string/inflections'
require 'test_aggregation'

module FinalAPI
  module V1
    module Http
      class DDTF_Build

        include ::Travis::Api::Formats

        attr_reader :build, :commit, :request

        def initialize(build, options = {})
          @build = build
          @commit = build.commit
          @request = build.request
        end

        #statuses are mapped in app/common/filters/status-class-filter.js on AtomUI side
        def test_data
          config = build.config

          {
            'id' => build.id,
            'buildId' => build.id,
            'ddtfUuid' => config[:ddtf_uuid] ||
              config[:ddtf_uid] ||
              config[:ddtfUuid],
            'name' => config[:name],
            'description' => config[:description],
            'branch' => config[:branch],
            'build' => config[:build],
            'queueName' => config[:queueName],

            #configured, pending, running, stopping, finished, stoped, aborted
            'status' => build.state, #TODO: convert to state?
            'strategy': config[:strategy],
            'email': config[:email],

            'started': build.created_at.to_s,  #TODO remove to_s
            'enqueued': build.started_at.to_s, #TODO remove to_s
            'startedBy': build.owner.try(:name).to_s,
            'enqueuedBy': build.owner.try(:name).to_s,    #TODO will be removed

            'stopped': build.state == 'cancelled',   # TODO: what does it mean status cancelled?
            'stoppedBy': nil, # TODO

            'isTsd': true,
            'checkpoints':    config[:checkpoints],
            'debugging':      config[:debbuging],
            'buildSignal':    config[:build_signal],
            'scenarioScript': config[:scenario_script],
            'packageSource':  config[:package_source],
            'executionLogs':  request.try(:message).to_s,
            'stashTSD':       config[:tsd_content],
            'runtimeConfig':  ddtf_runtimeConfig,

            'parts': parts_status,
            'tags': [],

            'result': build.state,

            #progress bar:
            'results': ddtf_results_distribution
          }
        end

        def parts_data
          ddtf_test_aggregation_result.as_json
        end

        def atom_response
          {
            id: build.id,
            name: build.config[:name],
            build: build.config[:build], # this is old DDTF build, not meaning test
            result: 'NotSet',
            results:
            {
              Type: 'NotSet',
              Value: 1.0
            },
            enqueued: Time.now
          }
        end

        private

        # returns hash of results of all test
        def ddtf_results_distribution
          res = ddtf_test_aggregation_result.results_hash
          %w(
            NotPerformed notPerformed not_performed
            Skipped skipped
          ).each do |not_reported_state|
            res.delete not_reported_state
          end

          sum = res.values.inject(0.0) { |s,i| s + i }
          res.inject([]) do |s, (result, count)|
            s << { 'type' => result, 'value' => count.to_f / sum }
          end
        end

        def ddtf_runtimeConfig
          runtimeConfig = build.config[:runtimeConfig] || []
        end

        def parts_status
          build.parts_groups.map do |part_name, jobs|
            {
              name: part_name,
              result: ddtf_test_aggregation_result.result(part: part_name)
            }
          end
        end

        def ddtf_test_aggregation_result
          return @ddtf_test_aggregation_result if (
            defined?(@ddtf_test_aggregation_result) &&
            @ddtf_test_aggregation_result
          )

          @ddtf_test_aggregation_result ||= TestAggregation::BuildResults.new(
            build,
            ->(job) { job.ddtf_part },
            ->(job) { job.ddtf_machine },
            lambda do |step_result|
              {
                description: step_result.name,
                machines: step_result.results.inject({}) do |s, (k, v)|
                  s[k] = { result: v[:result], message: '', resultId: v[:uuid] }
                  s
                end
              }
            end,
            ->(step_result) {
              result = (step_result['data'] and step_result['data']['status']).try(:camelcase)
              result ||= step_result['result'].downcase
            }
          )
          build.matrix.each do |job|
            StepResult.where(job_id: job.id).order('id desc').each do |sr|
              @ddtf_test_aggregation_result.parse(sr.data)
            end
          end
          @ddtf_test_aggregation_result
        end

      end
    end
  end
end
