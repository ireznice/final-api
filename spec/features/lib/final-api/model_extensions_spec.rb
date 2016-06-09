describe Build do

  describe '::ddtf_search' do
    it 'use JSON \'name\' column when no column expressions are used' do
      b = Build
      expect(b).to receive(:ddtf_search_column).with("config ->> 'name'", ':', 'TERM')
      b.search('TERM', 42, 0)
    end

    it 'search for equal in name and nam' do
      b = Build
      expect(b).to receive(:ddtf_search_column).with("config ->> 'name'", '=', 'TERM').exactly(3).times
      b.ddtf_search('name= TERM')
      b.ddtf_search('name = TERM')
      b.ddtf_search('nam= TERM')
    end

    it 'search for combination of search expression' do
      b = Build
      expect(b).to receive(:ddtf_search_column).with("id", '=', '1').once.and_return(b)
      expect(b).to receive(:ddtf_search_column).with("config ->> 'name'", ':', 'TERM1').once.and_return(b)
      expect(b).to receive(:ddtf_search_column).with("config ->> 'enqueuedBy'", ':', 'TERM2').once.and_return(b)
      expect(b).to receive(:ddtf_search_column).with("config ->> 'protonId'", '=', '666').once.and_return(b)
      b.ddtf_search('id = 1 nam: TERM1 enq: TERM2 protonId= 666')
    end
  end

  describe '::ddtf_search_column' do
    it 'use ilike SQL operator when when \':\' operator is used' do
      sql = Build.ddtf_search_column('id', ':', 'TERM').to_sql
      expect(sql).to match(/ILIKE/)
    end
    it 'search for "contaions" when \':\' operator is used' do
      sql = Build.ddtf_search_column('id', ':', 'TERM').to_sql
      expect(sql).to match(/%TERM%/)
    end

    it 'use = SQL operator when \'=\' operator is used' do
      sql = Build.ddtf_search_column('id', '=', 'TERM').to_sql
      expect(sql).to match(/=.{1,3}TERM/)
    end
    it 'raise exception on uknown operator' do
      expect {
        Build.ddtf_search_column('id', 'unknown', 'TERM')
      }.to raise_error(/Unknown operator/)
    end

    it 'converts column to text in SQL' do
      sql = Build.ddtf_search_column('MY_COLUMN', '=', 'TERM').to_sql
      expect(sql).to match(/\(MY_COLUMN\)::text/)

      sql = Build.ddtf_search_column('MY_COLUMN', ':', 'TERM').to_sql
      expect(sql).to match(/\(MY_COLUMN\)::text/)
    end
  end

  describe '#parts_groups' do
  end

  describe '#sanitize' do
    # It is usefull only in case that the DB contains not valid rows
    it 'fullfill mandator relations' do
      b = Build.new
      b.sanitize
      expect(b.repository).not_to be_nil
      expect(b.owner).not_to be_nil
      expect(b.request).not_to be_nil
    end
  end
end

describe Job do
  describe '#ddtf_test_resutls' do
  end

  describe '#ddtf_machine' do
  end
end
