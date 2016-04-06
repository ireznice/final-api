require 'final-api/ext/hash'

module FinalAPI
  module Endpoint
    module DDTF
      # Auxiliary routines for ddtf routes
      class DdtfHelpers
        class << self

          public
          def build_config(enqueue_data, tsd)
            {
              language: 'tsd',
              git:
              {
                no_clone: true
              },
              name: tsd['name'],
              description: test_data.get_ikey('Description'),
              branch: tsd['source']['git'] || tsd['source']['unc'],
              build: test_data.get_ikey('Build'),
              strategy: tsd['defaultStrategy'],
              email: test_data.get_ikey('Email'),
              checkpoint: test_data.get_ikey('Checkpoints') || false,
              scenarioScript: test_data.get_ikey('ScenarioScript'),
              stashTsd: test_data.get_ikey('StashTSD'),
              tsdContent: tsd,
              runtimeConfig: test_data.get_ikey('RuntimeConfigFields'),
              ddtfUuid: test_data.get_ikey('Id')
            }
          end

          def create_build(repository_id, user_id, config)
            ActiveRecord::Base.transaction do
              repo, commit, request = setup_build(repository_id, user_id)
              owner = request.owner

              build = Build.create!(
                repository: repo, commit: commit, request: request, config: config, owner: owner)

              clean_build_matrix(build)

              build
            end
          end

          def setup_build(repository_id, user_id)
            repository = Repository.find(repository_id) || Repository.first # FIXME: Proper repository retrieval
            commit = repository.commits.create!(
              commit: SecureRandom.hex(20), branch: 'branch', committed_at: Time.now) # FIXME: Proper commit retrieval
            request = Request.create!(
              repository: repository, owner: User.find(user_id))

            [repository, commit, request]
          end

          def clean_build_matrix(build)
            build.matrix.destroy_all
            build.cached_matrix_ids = nil
            # build.start(started_at: Time.now.utc)
            build.save!
          end
        end
      end
    end
  end
end
