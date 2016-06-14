require 'final-api/builder'
require 'tsd_utils'

require 'final-api/helpers/ddtf_helpers'
require 'securerandom'

module FinalAPI
  module Endpoint
    # Encapsulation for DDTF routes
    module DDTF
      class << self
        def registered(app)
          app.get '/ddtf/announcements' do
            {
              # TODO: needs to be plural 'announcements' - it is array
              announcement: ['Testing system - get rid of DB4o alfa version']
            }.to_json
          end

          app.get '/ddtf/tests/new' do
            halt_with_400('Please provide stashTSDLink url') unless params[:stashTSDLink]

            tsd = nil
            begin
              tsd_content = TsdUtils::ContentFetcher.load(params[:stashTSDLink])
              tsd = JSON.parse(tsd_content.encode('ASCII', undef: :replace, replace: ''))
            rescue
              halt_with_404("Unable to load tsd from: #{params[:stashTSDLink]}")
            end

            source = tsd.get_ikey('source')

            halt 200, {
              email: tsd.get_ikey('responsible'),
              packageFrom: source.get_ikey('git') ? 'GIT' : 'UNC',
              package: source.get_ikey('git') || source.get_ikey('unc'),
              strategy: tsd.get_ikey('defaultStrategy'),
              build: nil,
              description: tsd.get_ikey('description'),
              scenarioScripts: false,
              checkpoints: false,
              stashTSD: params[:stashTSDLink],
              runtimeConfigFields: tsd.get_ikey('runtimeConfig'),
              tsd: tsd.to_json
            }.to_json

          end

          # /ddtf/tests?limit=20&offset=0&q=yyyy+id:+my_id
          app.get '/ddtf/tests' do
            begin
              limit = params[:limit] ? params[:limit].to_i : 20
              offset = params[:offset] ? params[:offset].to_i : 0
              builds = Build.search(params[:q], limit, offset)

              FinalAPI::V1::Http::DDTF_Builds.new(builds, {}).data.to_json
            rescue Build::InvalidQueryError => e
              halt_with_400(e.to_s)
            end
          end

          app.get '/ddtf/tests/:id/executionLogs' do
            build = Build.find(params[:id])

            FinalAPI::V1::Http::DDTF_Build.new(build).execution_logs.to_json
          end

          app.get '/ddtf/tests/:id' do
            build = Build.find(params[:id])
            cache_control(:public, max_age: 36000) if build.finished?
            last_modified build.updated_at
            etag sha256.hexdigest(build.to_xml), :weak
            FinalAPI::V1::Http::DDTF_Build.new(build, {}).test_data.to_json
          end

          app.post '/ddtf/tests/:id/retest' do
            build = Build.find(params[:id])
            retest_data = FinalAPI::V1::Http::DDTF_Build.new(build, {}).retest_data
            retest_data['runtimeConfigFields'].reject! do |key, _|
              key[:definition].downcase.start_with?("webserver")
            end
            retest_data.to_json
          end

          app.get '/ddtf/tests/:id/parts' do
            build = Build.find(params[:id])
            last_modified build.updated_at
            etag sha256.hexdigest(build.to_xml), :weak
            cache_control(:public, max_age: 36000) if build.finished?
            FinalAPI::V1::Http::DDTF_Build.new(build, {}).parts_data.to_json
          end

          app.post '/ddtf/tests' do
            payload = MultiJson.load(request.body.read)

            enqueue_data = TsdUtils::EnqueueData.new(payload)

            begin
              enqueue_data.build_all
            rescue => err
              halt_with_422('Unable to process TSD data: ' + err.message)
            end

            halt 400, enqueue_data.errors.to_json unless enqueue_data.valid?

            config = DdtfHelpers.build_config(payload, enqueue_data)

            user_name = env['HTTP_NAME']
            halt_with_422("'name' header not specified") if user_name.blank?
            user = User.find_by_name(user_name) ||
                   User.create!(
                    name: user_name,
                    login: user_name,
                    email: "#{user_name}@#{FinalAPI.config.ddtf.email_domain}")

            repository = Repository.find_by_name('uploaded-tsd') ||
                         Repository.create!(name: 'uploaded-tsd', owner_name: user.name, owner_id: user.id, owner_type: 'User')

            build = DdtfHelpers.create_build(repository.id, user.id, config)

            halt_with_422('Could not create new build') if build.nil?

            cluster_name = enqueue_data.clusters.first
            cluster_endpoint = FinalAPI.config.tsd_utils.clusters[cluster_name.to_sym]

            enqueue_data.enqueue_data['BuildId'] = build.id

            node_starter_data = {
              build_id: build.id,
              config: {
                cluster_endpoint: cluster_endpoint,
                cluster_name: cluster_name,
                enqueued_by: request.env['HTTP_NAME']
              },
              enqueue_data: enqueue_data.to_xml
            }

            publisher = Travis::Amqp::Publisher.new(Travis.config.ddtf.node_queue)
            publisher.publish(node_starter_data)

            # TODO: imho atom_response should be removed,
            #  FinalAPI::V1::Http::DDTF_Build#test_data should be used
            halt 200, FinalAPI::V1::Http::DDTF_Build.new(build, {}).atom_response.to_json
          end

          app.put '/ddtf/tests/:id/stop' do
            service = Travis.service(:cancel_ddtf_build, current_user, params.merge(source: 'api'))
            halt(403, { messages: service.messages }.to_json) unless service.authorized?
            halt(204, { messages: service.messages }.to_json) unless service.build
            Travis.run_service(:cancel_ddtf_build, current_user, id: params['id'])
            halt 200
          end

          app.post '/ddtf/builds' do
            build = DdtfHelpers.create_build(params['repository_id'], params['user_id'], params['config'])
            halt 404 if build.nil?
            FinalAPI::Builder.new(build).data.to_json
          end

          app.post '/ddtf/builds/:build_id/jobs' do
            build = Build.lock.find(params[:build_id])
            parent_config = build.config.clone
            # just shrink size of config, we need specific TSD version for particular machine
            parent_config.delete :tsdContent
            job = build.matrix.create!(
              owner: build.owner,
              number: "#{build.number}.#{build.matrix.count + 1}",
              repository: build.repository,
              commit: build.commit,
              config: parent_config.deep_merge(params[:config])
            )
            job.receive(received_at: Time.now.utc)
            build.cached_matrix_ids = nil
            build.save!

            FinalAPI::Builder.new(job).data.to_json
          end

          # ids - ids of build separated by comma
          # otehrwise:
          # returns builds by param repository_id and you can specify:
          #   :number
          #   :event_type
          #   :after_number
          # if repository_id is not provided returns Build.recent
          app.get '/ddtf/builds' do
            params['ids'] = params['ids'].split(',') if params['ids'].is_a(String)
            result = Travis.service(:find_builds, params).run
            FinalAPI::Builder.new(result).data.to_json
          end

          app.post '/ddtf/builds/:id/restart' do
            service = Travis.service(:reset_model, current_user, build_id: params[:id])
            halt(403, { messages: service.messages }.to_json) unless service.accept?
            Travis.run_service(:reset_model, current_user, build_id: params['id'])
            halt 202
          end
        end
      end
    end
  end
end
