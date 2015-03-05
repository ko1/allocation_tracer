require "allocation_tracer/version"
require "allocation_tracer/allocation_tracer"

module ObjectSpace::AllocationTracer

  def self.output_lifetime_table table
    out = (file = ENV['RUBY_ALLOCATION_TRACER_LIFETIME_OUT']) ? open(File.expand_path(file), 'w') : STDOUT
    max_lines = table.inject(0){|r, (type, lines)| r < lines.size ? lines.size : r}
    out.puts "type\t" + (0...max_lines).to_a.join("\t")
    table.each{|type, line|
      out.puts "#{type}\t#{line.join("\t")}"
    }
  end

  def self.collect_lifetime_table
    ObjectSpace::AllocationTracer.lifetime_table_setup true

    if block_given?
      begin
        ObjectSpace::AllocationTracer.trace do
          yield
        end
        result = ObjectSpace::AllocationTracer.lifetime_table
        output_lifetime_table(result)
      ensure
        ObjectSpace::AllocationTracer.lifetime_table_setup false
      end
    else
      ObjectSpace::AllocationTracer.trace
    end
  end

  def self.collect_lifetime_table_stop
    ObjectSpace::AllocationTracer.stop
    result = ObjectSpace::AllocationTracer.lifetime_table
    ObjectSpace::AllocationTracer.lifetime_table_setup false
    output_lifetime_table(result)
    result
  end
end
