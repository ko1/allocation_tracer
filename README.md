# ObjectSpace::AllocationTracer

This module allows to trace object allocation.

This feature is similar to https://github.com/SamSaffron/memory_profiler 
and https://github.com/srawlins/allocation_stats. But this feature 
focused on `age' of objects.

This gem was separated from gc_tracer.gem.

[![Build Status](https://travis-ci.org/ko1/allocation_tracer.svg?branch=master)](https://travis-ci.org/ko1/allocation_tracer)

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

* count - how many objects are created.
* total_age - total age of objects which created here
* max_age - age of longest living object created here
* min_age - age of shortest living object created here

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
{["test.rb", 6]=>[50000, 0, 47440, 0, 1, 0],
 ["test.rb", 7]=>[50000, 4, 47452, 0, 6, 0],
 ["test.rb", 8]=>[50000, 7, 47456, 0, 6, 0]}
```

In this case, 
* 50,000 objects are created at `test.rb:6' and
  * 5 old objects created.
  * 44,290 is total age of objects created at this line (average age of object created at this line is 44290/50000 = 0.8858).
  * 0 is minimum age
  * 6 is maximum age.

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
{["test.rb", 8, :T_STRING]=>[50000, 15, 49165, 0, 16, 0],
 ["test.rb", 8, :T_ARRAY]=>[50000, 12, 49134, 0, 16, 0],
 ["test.rb", 9, :T_STRING]=>[100000, 27, 98263, 0, 16, 0],
 ["test.rb", 9, :T_HASH]=>[50000, 16, 49147, 0, 16, 8998848],
 ["test.rb", 10, :T_STRING]=>[100000, 36, 98322, 0, 16, 0],
 ["test.rb", 10, :T_STRUCT]=>[50000, 16, 49147, 0, 16, 0]}
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
{["test.rb", 8, :T_STRING]=>[25015, 5, 16299, 0, 2, 0]}
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
path    line    count   old_count       total_age       min_age max_age total_memsize
...rubygems/core_ext/kernel_require.rb 55     18       1       23      1       6       358
...lib/allocation_tracer/lib/allocation_tracer/trace.rb       6       2      012      6       6       0
test.rb 0       1       0       0       0       0       0
test.rb 5       50000   4       41492   0       5       0
test.rb 6       50000   3       41490   0       5       0
test.rb 7       50000   7       41497   0       5       0
```

(tab separated colums)

### Total Allocations / Free

Allocation tracer collects the total number of allocations and frees during the
`trace` block.  After the block finishes executing, you can examine the total
number of allocations / frees per object type like this:

```ruby
require 'allocation_tracer'

ObjectSpace::AllocationTracer.trace do
  1000.times {
    ["foo", {}]
  }
end
p allocated: ObjectSpace::AllocationTracer.allocated_count_table
p freed: ObjectSpace::AllocationTracer.freed_count_table
```

The output of the script will look like this:

```
{:allocated=>{:T_NONE=>0, :T_OBJECT=>0, :T_CLASS=>0, :T_MODULE=>0, :T_FLOAT=>0, :T_STRING=>1000, :T_REGEXP=>0, :T_ARRAY=>1000, :T_HASH=>1000, :T_STRUCT=>0, :T_BIGNUM=>0, :T_FILE=>0, :T_DATA=>0, :T_MATCH=>0, :T_COMPLEX=>0, :T_RATIONAL=>0, :unknown=>0, :T_NIL=>0, :T_TRUE=>0, :T_FALSE=>0, :T_SYMBOL=>0, :T_FIXNUM=>0, :T_UNDEF=>0, :T_NODE=>0, :T_ICLASS=>0, :T_ZOMBIE=>0}}
{:freed=>{:T_NONE=>0, :T_OBJECT=>0, :T_CLASS=>0, :T_MODULE=>0, :T_FLOAT=>0, :T_STRING=>1871, :T_REGEXP=>41, :T_ARRAY=>226, :T_HASH=>7, :T_STRUCT=>41, :T_BIGNUM=>0, :T_FILE=>50, :T_DATA=>25, :T_MATCH=>47, :T_COMPLEX=>0, :T_RATIONAL=>0, :unknown=>0, :T_NIL=>0, :T_TRUE=>0, :T_FALSE=>0, :T_SYMBOL=>0, :T_FIXNUM=>0, :T_UNDEF=>0, :T_NODE=>932, :T_ICLASS=>0, :T_ZOMBIE=>0}}
```

### Lifetime table

You can collect lifetime statistics with 
ObjectSpace::AllocationTracer.lifetime_table method.

```ruby
require 'pp'
require 'allocation_tracer'

ObjectSpace::AllocationTracer.lifetime_table_setup true
result = ObjectSpace::AllocationTracer.trace do
  100000.times{
    Object.new
    ''
  }
end
pp ObjectSpace::AllocationTracer.lifetime_table
```

will show

```
{:T_OBJECT=>[3434, 96563, 0, 0, 1, 0, 0, 2],
 :T_STRING=>[3435, 96556, 2, 1, 1, 1, 1, 1, 2]}
```

This output means that the age of 3434 T_OBJECT objects are 0, 96563 
objects are 1 and 2 objects are 7. Also the age of 3435 T_STRING 
objects are 0, 96556 objects are 1 and so on.

Note that these numbers includes living objects and dead objects.  For 
dead objects, age means lifetime. For living objects, age means 
current age.

## Rack middleware

You can use AllocationTracer via rack middleware.

```ruby
require 'rack'
require 'sinatra'
require 'rack/allocation_tracer'

use Rack::AllocationTracerMiddleware

get '/' do
  'foo'
end
```

When you access to `http://host/allocation_tracer/` then you can see a table of allocation tracer.

You can access the following pages.

* http://host/allocation_tracer/
* http://host/allocation_tracer/allocated_count_table
* http://host/allocation_tracer/freed_count_table_page
* http://host/allocation_tracer/lifetime_table

The following pages are demonstration Rails app on Heroku environment.

* http://protected-journey-7206.herokuapp.com/allocation_tracer/
* http://protected-journey-7206.herokuapp.com/allocation_tracer/allocated_count_table
* http://protected-journey-7206.herokuapp.com/allocation_tracer/freed_count_table_page
* http://protected-journey-7206.herokuapp.com/allocation_tracer/lifetime_table

Source code of this demo app is https://github.com/ko1/tracer_demo_rails_app. You only need to modify like https://github.com/ko1/tracer_demo_rails_app/blob/master/config.ru to use it on Rails.

## Contributing

1. Fork it ( http://github.com/ko1/allocation_tracer/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Author

Koichi Sasada from Heroku, Inc.

