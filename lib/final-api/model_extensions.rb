require 'final-api/ddtf'

class Build
  include FinalAPI::DDTF

  class InvalidQueryError < StandardError
  end

  # Represents mapping of query language used by frontend
  # *key* are query keywords
  # *values* are columns in DB
  SEARCH_TOKENS_DEF = {
    ['id']                    => 'id',  #where(id OP id)
    ['nam', 'name']           => 'name',
    ['sta', 'startedby']      => 'owner_id',  # where('owner_id IN (?)', User.where('name ILIKE ?', '%KEY%'))
    ['sto', 'stoppedby']      => 'stopped_by_id',
    ['sts', 'stat', 'status', 'state'] => 'state',
    ['bui', 'build']          => 'build_info',
    ['protonid']  => 'proton_id'
  }

  def parts_groups
    matrix.group_by do |t|
      t.config_vars_hash.get_ikey('part')
    end
  end

  class << self
    def search(query, limit, offset)
      builds = Build.order(Build.arel_table['created_at'].desc).limit(limit).offset(offset)
      return builds if query.nil?
      expressions = parse_query(query)
      expressions.each do |expr|
        builds = builds.where(retrieve_filter(*expr))
      end

      builds
    end

    private

    def check_query(query)
      query_copy = query.dup
      while query_copy.slice!(query_pattern) != nil do end
      raise InvalidQueryError, "Invalid expression: #{query_copy}" unless query_copy.blank?
    end

    # Returns list of parsed subqueries
    #
    # For example:
    #   parse_query('nam:"foo bar baz" bui =qux id : 1')
    #     => [ ['nam', ':', 'foo bar baz'], ['bui', '=', 'qux'], ['id', ':', '1']]
    def parse_query(query)
      expression_pattern = query_pattern
      query = query.dup.strip

      first_expression = query.slice(expression_pattern)

      if first_expression.nil?
        query = query.dup.strip
        if query.starts_with?('"') && query.ends_with?('"')
          query = query.dup.slice(1..-1)
          query = query.dup.slice(0..-2)
        end
      else
        check_query(query)
      end

      array = query.scan(expression_pattern)
      return [['name', ':', query]] if array.empty?
      wrong_keys = []
      result = array.map do |item|
        query_key = item[0].downcase
        operator = item[1]
        query_value = item[2]
        wrong_keys << query_key if query_value.to_s.empty?

        column = SEARCH_TOKENS_DEF.select { |k| k.include? query_key }.values.first
        wrong_keys << query_key if column.nil?

        [
          column,
          operator,
          query_value.tr("\"", '')
        ]
      end

      raise InvalidQueryError,
            "Wrong search definition(s) specified: #{wrong_keys.join(', ')}" unless wrong_keys.empty?

      result
    end

    def query_pattern
      /([^\ ]*)\ *([:=])\ *("[^"\:]*"|[^\:\ \=]*)/
    end

    def retrieve_users(query, exact_match = false)
      if exact_match
        User.where(name: query).each_with_object([]) {|u,out| out << u.id }
      else
        User.where(
          "name ILIKE ?",
          "%#{query.gsub( "\\", "\\\\\\")}%")
        .each_with_object([]) {|u,out| out << u.id }
      end
    end

    # maps fragment of old state given to travis states
    def determine_states(query, exact_match = false)
      states_map = FinalAPI::V1::Http::DDTF_Build::BUILD_STATE2API_V1STATUS
      states_map.reject { |k,v| k == '' }.each_with_object([]) do |(travis_state, ddtf_state), out|
        if exact_match
          out << travis_state if ddtf_state.downcase == query.downcase
        else
          out << travis_state if ddtf_state.downcase.include? query.downcase
        end
      end.compact
    end

    def retrieve_filter(key, operator, value)
      exact_match = (operator == '=')
      case key
      when 'owner_id', 'stopped_by_id'
        { key.to_sym => retrieve_users(value, exact_match) }
      when 'state'
        { key.to_sym => determine_states(value, exact_match) }
      else
        escaped_value = value.gsub(/[%_]/) { |str| "\\#{str}" }
        if exact_match
          [ "#{key}::text ILIKE :expr", expr: escaped_value ]
        else
          [ "#{key}::text ILIKE :expr", expr: "%#{escaped_value}%" ]
        end
      end
    end
  end
end

class Job
  include FinalAPI::DDTF

  def ddtf_test_resutls
    test_results_path = File.join(Travis.config.test_results.results_path, "#{id}.json")
    raw_test_results = MultiJson.load(File.read(test_results_path)) rescue []
  end

  def ddtf_machine
    config_vars_hash['MACHINE'] || config_vars_hash['Machine'] || 'NoMachineDefined'
  end

  def ddtf_part
    config_vars_hash.get_ikey('part') || 'NoPartDefined'
  end
end

