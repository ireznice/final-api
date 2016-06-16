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

  def self.search(query, limit, offset)
    builds = Build.order(Build.arel_table['created_at'].desc).limit(limit).offset(offset)
    return builds if query.nil?
    expressions = parse_query(query)
    expressions.each do |expr|
      builds = builds.where(retrieve_filter(*expr))
    end

    builds
  end

  def parts_groups
    matrix.group_by do |t|
      t.config_vars_hash['PART'] || t.config_vars_hash['Part']
    end
  end

  private

  def self.check_query(query)
    q = query.dup
    while q.slice!(query_pattern) != nil do end
    raise InvalidQueryError unless q =~ /^\s*$/
  end

  # Returns list of parsed subqueries
  #
  # For example:
  #   parse_query('nam:"foo bar baz" bui =qux id : 1')
  #     => [ ['nam', ':', 'foo bar baz'], ['bui', '=', 'qux'], ['id', ':', '1']]
  def self.parse_query(query)
    expression_pattern = /([^\s]*)\s*([:=])\s*("[^"]*"|\S*)/
    check_query(query)
    array = query.scan(expression_pattern)
    return [['name', ':', query]] if array.empty?
    wrong_keys = []
    result = array.map do |item|
      query_key = item[0].downcase
      operator = item[1]
      query_value = item[2]
      column = SEARCH_TOKENS_DEF.select { |k| k.include? query_key }.values.first
      wrong_keys << query_key if column.nil?

      [
        column,
        operator,
        query_value.tr("\"", '')
      ]
    end

    raise InvalidQueryError,
          "Wrong search definition(s) specified: #{wrong_keys.join(", ")}" unless wrong_keys.empty?

    result
  end
  def self.query_pattern
    /([^\s]*)\s*([:=])\s*("[^"]*"|\S*)/
  end
  def self.retrieve_users(query, exact_match = false)
    if exact_match
      User.where(name: query).each_with_object([]) {|u,out| out << u.id }
    else
      User.where("name ILIKE :expr", expr: "%#{query}%").each_with_object([]) {|u,out| out << u.id }
    end
  end

  # maps fragment of old state given to travis states
  def self.determine_states(query, exact_match = false)
    states_map = FinalAPI::V1::Http::DDTF_Build::BUILD_STATE2API_V1STATUS
    states_map.reject { |k,v| k == '' }.each_with_object([]) do |(travis_state, ddtf_state), out|
      if exact_match
        out << travis_state if ddtf_state.downcase == query.downcase
      else
        out << travis_state if ddtf_state.downcase.include? query.downcase
      end
    end.compact
  end

  def self.retrieve_filter(key, operator, value)
    exact_match = (operator == '=')
    case key
    when 'owner_id', 'stopped_by_id'
      { key.to_sym => retrieve_users(value, exact_match) }
    when 'state'
      { key.to_sym => determine_states(value, exact_match) }
    else
      if exact_match
        [ "#{key}::text ILIKE :expr", expr: "#{value}" ]
      else
        [ "#{key}::text ILIKE :expr", expr: "%#{value}%" ]
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
    config_vars_hash['PART'] || config_vars_hash['Part'] || 'NoPartDefined'
  end

end

