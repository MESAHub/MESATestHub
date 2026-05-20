require 'rails_helper'

RSpec.describe CommitRelation, type: :model do
  describe 'associations' do
    it 'belongs to a parent commit and a child commit' do
      parent = create(:commit)
      child  = create(:commit)
      rel = CommitRelation.create!(parent: parent, child: child)

      expect(rel.parent).to eq(parent)
      expect(rel.child).to eq(child)
    end
  end

  describe 'unique (child, parent) constraint' do
    it 'rejects a duplicate edge from the database' do
      parent = create(:commit)
      child  = create(:commit)
      CommitRelation.create!(parent: parent, child: child)

      expect {
        CommitRelation.connection.execute(
          ActiveRecord::Base.send(:sanitize_sql_array, [
            'INSERT INTO commit_relations (parent_id, child_id, parent_index) VALUES (?, ?, ?)',
            parent.id, child.id, 0
          ])
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'Commit#parents / Commit#children' do
    it 'walks both directions of an edge' do
      p = create(:commit)
      c = create(:commit)
      CommitRelation.create!(parent: p, child: c)

      expect(c.parents).to contain_exactly(p)
      expect(p.children).to contain_exactly(c)
    end

    it 'supports merge commits with multiple parents (distinct parent_index)' do
      p1 = create(:commit)
      p2 = create(:commit)
      merge = create(:commit)
      CommitRelation.create!(parent: p1, child: merge, parent_index: 0)
      CommitRelation.create!(parent: p2, child: merge, parent_index: 1)

      expect(merge.parents).to contain_exactly(p1, p2)
    end

    it 'deletes edges when the commit is destroyed' do
      p = create(:commit)
      c = create(:commit)
      CommitRelation.create!(parent: p, child: c)

      expect { c.destroy }.to change(CommitRelation, :count).by(-1)
    end
  end
end
