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
        'x' * 1234 # danger
        GC.start
      end

      expect(result.length).to be >= 1
      size = result[[__FILE__, line]][-1]
      expect(size).to be > 1234 if size > 0
    end

    describe 'with different setup' do
      it 'should work with type' do
        line = __LINE__ + 3
        ObjectSpace::AllocationTracer.setup(%i(path line type))
        result = ObjectSpace::AllocationTracer.trace do
          a = [Object.new]
          b = {Object.new => 'foo'}
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
          a = [Object.new]
          b = {Object.new => 'foo'}
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
end
