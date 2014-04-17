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
      expect(result[[__FILE__, line]]).to eq [1, 0, 0, 0]
    end

    it 'should run twice' do
      line = __LINE__ + 2
      result = ObjectSpace::AllocationTracer.trace do
        Object.new
      end

      expect(result.length).to be >= 1
      expect(result[[__FILE__, line]]).to eq [1, 0, 0, 0]
    end
  end
end
