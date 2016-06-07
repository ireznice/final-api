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
    ['buildid', 'protonid']  => 'protonId'
  }

  def self.search(query, limit, offset)
    search_struct = parse_query(query)
    query = Build.order(Build.arel_table['created_at'].desc).limit(limit).offset(offset)
    search_struct.each do |request|
      if request[1] == ":"
        query = query.where("#{request[0]} ILIKE :expr", expr: "%#{request[2]}%")
      else
        query = query.where("#{request[0]} = :expr", expr: "%#{request[2]}%")
      end
    end

    query
  end

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

  def self.parse_query(query)
    array = query.scan(/([^\s]*)\s*([:=])\s*("[^"]*"|\S*)/)
    array.map do |item|
      query_key = item[0].downcase
      column = SEARCH_TOKENS_DEF.select { |k| k.include? query_key }.values.first
      raise "Wrong search definition specified" if column.nil?

      [
        column,
        item[1],
        item[2].tr("\"", '')
      ]
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

