

describe Build do

  describe '::search' do
    let(:user1) { FactoryGirl.create(:user, name: 'franta.lopata') }
    let(:user2) { FactoryGirl.create(:user, name: 'quux.qux') }

    let!(:builds) do
      build_overrides = {
        owner: user1,
        stopped_by: user2
      }

      FactoryGirl.create_list(:build_customized, 20, build_overrides)
    end

    it 'applies limit' do
      expect(Build.search("", 5, 0).length).to eq(5)
    end

    it 'applies offset' do
      db_ids = Build.order(Build.arel_table['created_at'].desc).map {|b| b.id}
      expect(Build.search("", 30, 5).map {|b| b.id}).to eq(db_ids.drop(5))
    end

    context 'exact match' do
      it 'filters by id' do
        id = builds[14].id
        expect(Build.search("id = \"#{id}\" ", 5, 0).first.id).to eq(id)
      end

      context 'when id does not exist' do
        it 'returns an empty array' do
          expect(Build.search("id = \"99999999999999\" ", 5, 0).length).to eq(0)
        end
      end

      it 'filters by startedBy' do
        builds << FactoryGirl.create(:build_customized, owner: user2)
        filtered = Build.search("sta = quux.qux", 5, 0)
        expect(filtered.first.owner.name).to eq('quux.qux')
        expect(filtered.length).to eq(1)
      end

      it 'filters by startedBy' do
        builds << FactoryGirl.create(:build_customized, owner: user2)
        filtered = Build.search("sta = franta.lopata", 500, 0)
        expect(filtered.length).to eq(20)
      end

      it 'filters by stoppedBy' do
        builds << FactoryGirl.create(:build_customized, stopped_by: user1, owner: user2)
        filtered = Build.search("sto= \"franta.lopata\" ", 5, 0)
        expect(filtered.first.stopped_by.name).to eq('franta.lopata')
        expect(filtered.length).to eq(1)
      end

      context 'when stoppedBy does not exist' do
        it 'returns no items' do
          builds << FactoryGirl.create(:build_customized, stopped_by: user1, owner: user2)
          filtered = Build.search("sto= \"frant\" ", 500, 0)
          expect(filtered.length).to eq(0)
        end
      end

      it 'filters by state Configured' do
        results = Build.search("sts= Confi", 100, 0)
        expect(results.length).to eq(0)
      end

      it 'filters by state Finished' do
        results = Build.search("sts= Fin", 100, 0)
        expect(results.length).to eq(0)
      end

      it 'filters by state Configured' do
        results = Build.search("sts= Configured", 100, 0)
        count_wanted = builds.keep_if {|i| i.state == 'created'}.size
        expect(results.length).to eq(count_wanted)
        results.each do |build|
          expect(build.state).to eq('created')
        end
      end

      it 'filters by state Finished' do
        results = Build.search("sts= Finished", 100, 0)
        expect(results.length).to eq(14)
        results.each do |build|
          expect(build.state).to eq('passed')
        end
      end
    end

    context 'partial match' do
      it 'filters by id' do
        id = builds[14].id
        expect(Build.search("id: \"#{id}\" ", 5, 0).first.id).to eq(id)
      end

      it 'filters by name' do
        build = builds[9]
        expect(Build.search("name: \"#{build.name[2..7]}\" ", 5, 0).first.id).to eq(build.id)
      end

      it 'filters by name and returns all suitable items' do
        expect(Build.search("name: \"foo \" ", 100, 0).length).to eq(builds.length)
      end

      it 'filters by build_info' do
        build = builds[9]
        expect(Build.search("bui: \"#{build.build_info[2..7]}\" ", 5, 0).first.id).to eq(build.id)
      end

      it 'filters by build_info and returns all suitable items' do
        expect(Build.search("bui: \"qux \" ", 100, 0).length).to eq(builds.length)
      end

      it 'filters by startedBy' do
        builds << FactoryGirl.create(:build_customized, owner: user2)
        filtered = Build.search("sta: \"quux\" ", 5, 0)
        expect(filtered.first.owner.name).to eq('quux.qux')
        expect(filtered.length).to eq(1)
      end

      it 'filters by startedBy and returns all suitable items' do
        builds << FactoryGirl.create(:build_customized, owner: user2)
        filtered = Build.search("sta: \".\" ", 500, 0)
        expect(filtered.length).to eq(builds.length)
      end

      it 'filters by stoppedBy' do
        builds << FactoryGirl.create(:build_customized, stopped_by: user1, owner: user2)
        filtered = Build.search("sto: \"fran\" ", 5, 0)
        expect(filtered.first.stopped_by.name).to eq('franta.lopata')
        expect(filtered.length).to eq(1)
      end

      it 'filters by stoppedBy and returns all suitable items' do
        builds << FactoryGirl.create(:build_customized, stopped_by: user1, owner: user2)
        filtered = Build.search("sto: \".\" ", 500, 0)
        expect(filtered.length).to eq(builds.length)
      end

      it 'filters by non stoppedBy' do
        builds << FactoryGirl.create(:build_customized, stopped_by: user1, owner: user2)
        filtered = Build.search("sto: \"fran\" ", 5, 0)
        expect(filtered.first.stopped_by.name).to eq('franta.lopata')
        expect(filtered.length).to eq(1)
      end

      it 'filters by state and returns all items' do
        expect(Build.search("sts: ed", 100, 0).length).to eq(builds.length)
      end

      it 'filters by state Configured' do
        results = Build.search("sts: Confi", 100, 0)
        count_wanted = builds.keep_if {|i| i.state == 'created'}.size
        expect(results.length).to eq(count_wanted)
        results.each do |build|
          expect(build.state).to eq('created')
        end
      end

      it 'filters by state Finished' do
        results = Build.search("sts: Fin", 100, 0)
        count_wanted = builds.keep_if {|i| i.state == 'passed'}.size
        expect(results.length).to eq(count_wanted)
        results.each do |build|
          expect(build.state).to eq('passed')
        end
      end
    end
  end

  describe '::patse_query' do
    {
      'id:0' => [['id', ':', '0']],
      'sta:jan.topor name:releasetest build:3580 sto:petr.s status:finished' => [
        ['owner_id', ':', 'jan.topor'],
        ['name', ':', 'releasetest'],
        ['build_info', ':', '3580'],
        ['stopped_by_id', ':', 'petr.s'],
        ['state', ':', 'finished']
      ],
      '' => [['name', ':', '']]
    }.each do |k, v|
      it "returns correct output for \"#{k}\"" do
        expect(Build.parse_query(k)).to eq(v)
      end
    end
  end
end
