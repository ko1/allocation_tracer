require 'spec_helper'
require 'tmpdir'
require 'fileutils'

describe ObjectSpace::AllocationTracer do
  describe 'ObjectSpace::AllocationTracer.trace' do
    it 'should includes allocation information' do
      line = __LINE__ + 2
      result = ObjectSpace::AllocationTracer.trace do
        Object.new
      end

      expect(result.length).to be >= 1
      expect(result[[__FILE__, line]]).to eq [1, 0, 0, 0, 0, 0]
    end

    it 'should run twice' do
      line = __LINE__ + 2
      result = ObjectSpace::AllocationTracer.trace do
        Object.new
      end
      #GC.start
      # p result
      expect(result.length).to be >= 1
      expect(result[[__FILE__, line]]).to eq [1, 0, 0, 0, 0, 0]
    end

    it 'should analyze many objects' do
      line = __LINE__ + 3
      result = ObjectSpace::AllocationTracer.trace do
        50_000.times{|i|
          i.to_s
          i.to_s
          i.to_s
        }
      end

      GC.start
      #pp result

      expect(result[[__FILE__, line + 0]][0]).to be >= 50_000
      expect(result[[__FILE__, line + 1]][0]).to be >= 50_000
      expect(result[[__FILE__, line + 2]][0]).to be >= 50_000
    end

    it 'should count old objects' do
      a = nil
      line = __LINE__ + 2
      result = ObjectSpace::AllocationTracer.trace do
        a = 'x' # it will be old object
        32.times{GC.start}
      end

      expect(result.length).to be >= 1
      _, old_count, * = *result[[__FILE__, line]]
      expect(old_count).to be == 1
    end

    it 'should acquire allocated memsize' do
      line = __LINE__ + 2
      result = ObjectSpace::AllocationTracer.trace do
        _ = 'x' * 1234 # danger
        GC.start
      end

      expect(result.length).to be >= 1
      size = result[[__FILE__, line]][-1]
      expect(size).to be > 1234 if size > 0
    end

    it 'can be paused and resumed' do
      line = __LINE__ + 2
      result = ObjectSpace::AllocationTracer.trace do
        Object.new
        ObjectSpace::AllocationTracer.pause
        Object.new # ignore tracing
        ObjectSpace::AllocationTracer.resume
        Object.new
      end

      expect(result.length).to be 2
      expect(result[[__FILE__, line    ]]).to eq [1, 0, 0, 0, 0, 0]
      expect(result[[__FILE__, line + 4]]).to eq [1, 0, 0, 0, 0, 0]
    end

    it 'can be get middle result' do
      middle_result = nil
      line = __LINE__ + 2
      result = ObjectSpace::AllocationTracer.trace do
        Object.new
        middle_result = ObjectSpace::AllocationTracer.result
        Object.new
      end

      expect(result.length).to be 2
      expect(result[[__FILE__, line    ]]).to eq [1, 0, 0, 0, 0, 0]
      expect(result[[__FILE__, line + 2]]).to eq [1, 0, 0, 0, 0, 0]

      expect(middle_result.length).to be 1
      expect(middle_result[[__FILE__, line    ]]).to eq [1, 0, 0, 0, 0, 0]
    end

    describe 'stop when not started yet' do
      it 'should raise RuntimeError' do
        expect do
          ObjectSpace::AllocationTracer.stop
        end.to raise_error(RuntimeError)
      end
    end

    describe 'pause when not started yet' do
      it 'should raise RuntimeError' do
        expect do
          ObjectSpace::AllocationTracer.pause
        end.to raise_error(RuntimeError)
      end
    end

    describe 'resume when not started yet' do
      it 'should raise RuntimeError' do
        expect do
          ObjectSpace::AllocationTracer.resume
        end.to raise_error(RuntimeError)
      end
    end

    describe 'when starting recursively' do
      it 'should raise RuntimeError' do
        expect do
          ObjectSpace::AllocationTracer.trace{
            ObjectSpace::AllocationTracer.trace{}
          }
        end.to raise_error(RuntimeError)
      end
    end

    describe 'with different setup' do
      it 'should work with type' do
        line = __LINE__ + 3
        ObjectSpace::AllocationTracer.setup(%i(path line type))
        result = ObjectSpace::AllocationTracer.trace do
          _a = [Object.new]
          _b = {Object.new => 'foo'}
        end

        expect(result.length).to be 5
        expect(result[[__FILE__, line, :T_OBJECT]]).to eq [1, 0, 0, 0, 0, 0]
        expect(result[[__FILE__, line, :T_ARRAY]]).to eq [1, 0, 0, 0, 0, 0]
        # expect(result[[__FILE__, line + 1, :T_HASH]]).to eq [1, 0, 0, 0, 0]
        expect(result[[__FILE__, line + 1, :T_OBJECT]]).to eq [1, 0, 0, 0, 0, 0]
        expect(result[[__FILE__, line + 1, :T_STRING]]).to eq [1, 0, 0, 0, 0, 0]
      end

      it 'should work with class' do
        line = __LINE__ + 3
        ObjectSpace::AllocationTracer.setup(%i(path line class))
        result = ObjectSpace::AllocationTracer.trace do
          _a = [Object.new]
          _b = {Object.new => 'foo'}
        end

        expect(result.length).to be 5
        expect(result[[__FILE__, line, Object]]).to eq [1, 0, 0, 0, 0, 0]
        expect(result[[__FILE__, line, Array]]).to eq [1, 0, 0, 0, 0, 0]
        # expect(result[[__FILE__, line + 1, Hash]]).to eq [1, 0, 0, 0, 0, 0]
        expect(result[[__FILE__, line + 1, Object]]).to eq [1, 0, 0, 0, 0, 0]
        expect(result[[__FILE__, line + 1, String]]).to eq [1, 0, 0, 0, 0, 0]
      end

      it 'should have correct headers' do
        ObjectSpace::AllocationTracer.setup(%i(path line))
        expect(ObjectSpace::AllocationTracer.header).to eq [:path, :line, :count, :old_count, :total_age, :min_age, :max_age, :total_memsize]
        ObjectSpace::AllocationTracer.setup(%i(path line class))
        expect(ObjectSpace::AllocationTracer.header).to eq [:path, :line, :class, :count, :old_count, :total_age, :min_age, :max_age, :total_memsize]
        ObjectSpace::AllocationTracer.setup(%i(path line type class))
        expect(ObjectSpace::AllocationTracer.header).to eq [:path, :line, :type, :class, :count, :old_count, :total_age, :min_age, :max_age, :total_memsize]
      end

      it 'should set default setup' do
        ObjectSpace::AllocationTracer.setup()
        expect(ObjectSpace::AllocationTracer.header).to eq [:path, :line, :count, :old_count, :total_age, :min_age, :max_age, :total_memsize]
      end
    end
  end

  describe 'collect lifetime_table' do
    before do
      ObjectSpace::AllocationTracer.lifetime_table_setup true
    end

    after do
      ObjectSpace::AllocationTracer.lifetime_table_setup false
    end

    it 'should make lifetime table' do
      ObjectSpace::AllocationTracer.trace do
        100000.times{
          Object.new
          ''
        }
      end
      table = ObjectSpace::AllocationTracer.lifetime_table

      expect(table[:T_OBJECT].inject(&:+)).to be >= 10_000
      expect(table[:T_STRING].inject(&:+)).to be >= 10_000
      expect(table[:T_NONE]).to be nil
    end

    it 'should return nil when ObjectSpace::AllocationTracer.lifetime_table_setup is false' do
      ObjectSpace::AllocationTracer.lifetime_table_setup false

      ObjectSpace::AllocationTracer.trace do
        100000.times{
          Object.new
          ''
        }
      end

      table = ObjectSpace::AllocationTracer.lifetime_table

      expect(table).to be nil
    end

    it 'should return nil getting it twice' do
      ObjectSpace::AllocationTracer.trace do
        100000.times{
          Object.new
          ''
        }
      end

      table = ObjectSpace::AllocationTracer.lifetime_table
      table = ObjectSpace::AllocationTracer.lifetime_table

      expect(table).to be nil
    end
  end

  describe 'ObjectSpace::AllocationTracer.collect_lifetime_table' do
    it 'should collect lifetime table' do
      table = ObjectSpace::AllocationTracer.collect_lifetime_table do
        100000.times{
          Object.new
          ''
        }
      end

      expect(table[:T_OBJECT].inject(&:+)).to be >= 10_000
      expect(table[:T_STRING].inject(&:+)).to be >= 10_000
      expect(table[:T_NONE]).to be nil
    end
  end

  describe 'ObjectSpace::AllocationTracer.allocated_count_table' do
    it 'should return a Hash object' do
      h = ObjectSpace::AllocationTracer.allocated_count_table
      expect(h[:T_NONE]).to be 0
    end
  end

  describe 'ObjectSpace::AllocationTracer.freed_count_table' do
    it 'should return a Hash object' do
      h = ObjectSpace::AllocationTracer.freed_count_table
      expect(h[:T_NONE]).to be 0
    end
  end
end
