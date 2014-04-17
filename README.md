# ObjectSpace::AllocationTracer

This module allows to trace object allocation.

This feature is similar to https://github.com/SamSaffron/memory_profiler 
and https://github.com/srawlins/allocation_stats. But this feature 
focused on `age' of objects.

This gem was separated from gc_tracer.gem.

## Installation

Add this line to your application's Gemfile:

    gem 'allocation_tracer'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install allocation_tracer

## Usage

### Allocation tracing

You can trace allocation and aggregate information. Information includes:

    count - how many objects are created.
    total_age - total age of objects which created here
    max_age - age of longest living object created here
    min_age - age of shortest living object created here

Age of Object can be calculated by this formula: [current GC count] - [birth time GC count]

For example:

```ruby
require 'allocation_tracer'
require 'pp'

pp ObjectSpace::AllocationTracer.trace{
  50_000.times{|i|
    i.to_s
    i.to_s
    i.to_s
  }
}
```

will show

```
{["test.rb", 6]=>[50000, 44290, 0, 6],
 ["test.rb", 7]=>[50000, 44289, 0, 5],
 ["test.rb", 8]=>[50000, 44295, 0, 6]}
```

In this case, 50,000 objects are created at `test.rb:6'. 44,290 is total 
age of objects created at this line. Average age of object created at 
this line is 50000/44290 = 0.8858. 0 is minimum age and 6 is maximum age.

You can also specify `type' in GC::Tracer.setup_allocation_tracing() to 
specify what should be keys to aggregate like that.

```ruby
require 'allocation_tracer'
require 'pp'

ObjectSpace::AllocationTracer.setup(%i{path line type})

result = ObjectSpace::AllocationTracer.trace do
  50_000.times{|i|
    a = [i.to_s]
    b = {i.to_s => nil}
    c = (i.to_s .. i.to_s)
  }
end

pp result
```

and you will get:

```
{["test.rb", 8, :T_STRING]=>[50000, 49067, 0, 17],
 ["test.rb", 8, :T_ARRAY]=>[50000, 49053, 0, 17],
 ["test.rb", 9, :T_STRING]=>[100000, 98146, 0, 17],
 ["test.rb", 9, :T_HASH]=>[50000, 49111, 0, 17],
 ["test.rb", 10, :T_STRING]=>[100000, 98267, 0, 17],
 ["test.rb", 10, :T_STRUCT]=>[50000, 49126, 0, 17]}
```

Interestingly, you can not see array creations in a middle of block:

```ruby
require 'allocation_tracer'
require 'pp'

ObjectSpace::AllocationTracer.setup(%i{path line type})

result = ObjectSpace::AllocationTracer.trace do
  50_000.times{|i|
    [i.to_s]
    nil
  }
end

pp result
```

and it prints:

```
{["test.rb", 8, :T_STRING]=>[50000, 38322, 0, 2]}
```

There are only string creation. This is because unused array creation is 
ommitted by optimizer.

Simply you can require `allocation_tracer/trace' to start allocation 
tracer and output the aggregated information into stdot at the end of 
program.

```ruby
require 'allocation_tracer/trace'

# Run your program here
50_000.times{|i|
  i.to_s
  i.to_s
  i.to_s
}
```

and you will see:

```
path    line    count   total_age       max_age min_age
.../lib/ruby/2.2.0/rubygems/core_ext/kernel_require.rb 55      18      23      1       6
.../lib/allocation_tracer/trace.rb       6       2       12      6       6
test.rb 0       1       0       0       0
test.rb 5       50000   41645   0       4
test.rb 6       50000   41648   0       5
test.rb 7       50000   41650   0       5
```

(tab separated colums)

## Contributing

1. Fork it ( http://github.com/<my-github-username>/allocation_tracer/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Author

Koichi Sasada from Heroku, Inc.

