require 'final-api/ddtf'

class Build
  include FinalAPI::DDTF

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
      case expr[0]
      when 'owner_id', 'stopped_by_id'
        builds = builds.where(expr[0].to_sym => retrieve_users(expr[2]))
      when 'state'
        builds = builds.where(expr[0].to_sym => retrieve_states(expr[2]))
      else
        if expr[1] == ":"
          builds = builds.where("#{expr[0]}::text ILIKE :expr", expr: "%#{expr[2]}%")
        else
          builds = builds.where(expr[0].to_sym => expr[2])
        end
      end
    end

    builds
  end

=begin
  def self.ddtf_search(query)
    res = scoped
    return res if query.blank?
    res_query = query.dup
    SEARCH_TOKENS_DEF.each_pair do |keys, column|
      if res_query.sub!(/(?:#{keys.join('|')})\s*([:=])\s*("(?:[^"]*?")|\S+)/, '')
        op = $1
        term = $2.gsub(/\A"(.*)"\z/, '\1')
        res = res.ddtf_search_column(column, op, term)
      end
    end
    # when no keyword found search in `name` field by "contaions" operator
    if res_query == query
      res = res.ddtf_search_column('name', ':', query)
    end
    res
  end

  def self.ddtf_search_column(column, operator, term)
    if (column == 'owner_id') || (column == 'stopped_by_id')
      if operator == ':'
        term = User.where("name ILIKE ?", "%#{term}%").pluck(:id)
      else
        term = User.where(name: term).pluck(:id)
      end
      operator = 'IN'
    end

    case operator
    when '='
      # makes search quite slow (and without index)
      # but users are unaware of types, and could write: WHERE id = 'string'
      # which leads to error:
      #   PG::InvalidTextRepresentation: ERROR:  invalid input syntax for integer
      column = "(#{column})::text"
    when ':'
      operator = 'ILIKE'
      term = "%#{term}%"
      column = "(#{column})::text"
    when 'IN'
      # empty
    else
      fail "Unknown operator: #{operator.inspect}"
    end
    where([column, operator, '(?)'].join(' '), term)
  end
=end

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
    array.map do |item|
      query_key = item[0].downcase
      column = SEARCH_TOKENS_DEF.select { |k| k.include? query_key }.values.first
      # TODO: return nil instead, then return status 400 or so and nice error message
      raise "Wrong search definition specified: #{query_key}" if column.nil?

      [
        column,
        item[1],
        item[2].tr("\"", '')
      ]
    end
  end

  def self.retrieve_users(query)
    User.where("name ILIKE :expr", expr: "%#{query}%").each_with_object([]) {|u,out| out << u.id }
  end

  # maps fragment of old state given to travis states
  def self.determine_states(query)
    states_map = FinalAPI::V1::Http::DDTF_Build::BUILD_STATE2API_V1STATUS
    states_map.reject { |k,v| k == '' }.each_with_object([]) do |(new, old), out|
      out << new if old.downcase.include? query.downcase
    end.compact
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

