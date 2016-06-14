module FinalAPI
  module ErrorHandling

    module HaltHelpers
      def halt_with_400(message)
        halt 400, error_response(message)
      end

      def halt_with_422(message)
        halt 422, error_response(message)
      end

      def halt_with_404(message)
        halt 404, error_response(message)
      end

      def halt_with_422_exception
        record = env['sinatra.error'].record
        errors = record.errors.to_h
        halt 422, {
          message: record.valid? ? 'Validation fails' : env['sinatra.error'].to_s,
          errors: errors.to_h
        }.to_json
      end

      private

      def error_response(message)
        {
          status: 'error',
          data: nil,
          message: message
        }.to_json
      end
    end

    def self.registered(app)
      app.helpers HaltHelpers

      app.error ActiveRecord::RecordNotFound, Travis::RepositoryNotFoundError do
        halt 404, { message: "Not found" }.to_json
      end

      app.error ActiveRecord::RecordInvalid do
        halt_with_422_exception
      end

      app.error ActiveRecord::UnknownAttributeError do
        halt_with_422
      end

      app.error ActiveRecord::DeleteRestrictionError do
        halt_with_400
      end

      app.error JSON::ParserError, MultiJson::DecodeError do
        halt_with_400("Cannot parse JSON")
      end
    end

  end
end



