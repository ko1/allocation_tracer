require "allocation_tracer/version"
require "allocation_tracer/allocation_tracer"

module ObjectSpace::AllocationTracer
  def self.collect_lifetime_talbe
    ObjectSpace::AllocationTracer.lifetime_table_setup true

    if block_given?
      begin
        ObjectSpace::AllocationTracer.trace do
          yield
        end
        ObjectSpace::AllocationTracer.lifetime_table
      ensure
        ObjectSpace::AllocationTracer.lifetime_table_setup false
      end
    else
      ObjectSpace::AllocationTracer.trace
    end
  end

  def self.collect_lifetime_talbe_stop
    ObjectSpace::AllocationTracer.stop
    result = ObjectSpace::AllocationTracer.lifetime_table
    ObjectSpace::AllocationTracer.lifetime_table_setup false
    result
  end
end
