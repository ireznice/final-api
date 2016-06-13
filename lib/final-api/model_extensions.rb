require 'final-api/ddtf'

class Build
  include FinalAPI::DDTF

  class InvalidQueryError < StandardError
  end

  # Represents metadat for query language used by frondend
  # *key* are query keywords
  # *values* are columns in DB
  SEARCH_TOKENS_DEF = {
    ['id']                    => 'id',  #where(id OP id)
    ['nam', 'name']           => 'name',
    ['sta', 'startedby']      => 'owner_id',  # where('owner_id IN (?)', User.where('name ILIKE ?', '%KEY%'))
    ['sto', 'stoppedby']      => 'stopped_by_id',
    ['sts', 'stat', 'status', 'state'] => 'state',
    ['bui', 'build']          => 'build_info',
    ['buildid', 'protonid']  => 'proton_id'
  }

  def self.search(query, limit, offset)
    builds = Build.order(Build.arel_table['created_at'].desc).limit(limit).offset(offset)
    return builds if query.nil?
    expressions = parse_query(query)
    expressions.each do |expr|
      builds = builds.where(retrieve_filter(expr))
    end

    builds
  end

  def parts_groups
    matrix.group_by do |t|
      t.config_vars_hash['PART'] || t.config_vars_hash['Part']
    end
  end

  # set mandatory properties
  # this is temporary solution for invalid data in DB
  # ...and just for development phase
  def sanitize
    self.repository ||= Repository.new
    self.owner ||= User.new
    self.request ||= Request.new
    self
  end

  private

  # Returns list of parsed subqueries
  #
  # For example:
  #   parse_query('nam:"foo bar baz" bui =qux id : 1')
  #     => [ ['nam', ':', 'foo bar baz'], ['bui', '=', 'qux'], ['id', ':', '1']]
  def self.parse_query(query)
    array = query.scan(/([^\s]*)\s*([:=])\s*("[^"]*"|\S*)/)
    return [['name' , ':', query]] if array.length == 0
    wrong_keys = []
    result = array.map do |item|
      query_key = item[0].downcase
      column = SEARCH_TOKENS_DEF.select { |k| k.include? query_key }.values.first
      wrong_keys << query_key if column.nil?

      [
        column,
        item[1],
        item[2].tr("\"", '')
      ]
    end

    raise InvalidQueryError,
          "Wrong search definition(s) specified: #{wrong_keys.join(", ")}" unless wrong_keys.empty?

    result
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
    states_map.reject { |k,v| k == '' }.each_with_object([]) do |(new, old), out|
      if exact_match
        out << new if old.downcase == query.downcase
      else
        out << new if old.downcase.include? query.downcase
      end
    end.compact
  end

  def self.retrieve_filter(expr)
    exact_match = (expr[1] == '=')
    case expr[0]
    when 'owner_id', 'stopped_by_id'
      { expr[0].to_sym => retrieve_users(expr[2], exact_match) }
    when 'state'
      { expr[0].to_sym => determine_states(expr[2], exact_match) }
    else
      if exact_match
        { expr[0].to_sym => expr[2] }
      else
         [ "#{expr[0]}::text ILIKE :expr", expr: "%#{expr[2]}%" ]
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

