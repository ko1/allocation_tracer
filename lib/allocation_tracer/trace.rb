require 'allocation_tracer'

# ObjectSpace::AllocationTracer.setup(%i{path line})
ObjectSpace::AllocationTracer.trace

at_exit{
  results = ObjectSpace::AllocationTracer.stop

  puts ObjectSpace::AllocationTracer.header.join("\t")
  results.sort_by{|k, v| k}.each{|k, v|
    puts (k+v).join("\t")
  }
}


