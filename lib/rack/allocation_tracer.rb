#
# Rack middleware
#

require 'allocation_tracer'

module Rack
  module AllocationTracerMiddleware
    def self.new *args
      TotalTracer.new *args
    end

    class Tracer
      def initialize app
        @app = app
        @sort_order = (0..7).to_a
      end

      def allocation_trace_page result, env
        if /\As=(\d+)/ =~ env["QUERY_STRING"]
          top = $1.to_i
          @sort_order.unshift top if @sort_order.delete top
        end

        table = result.map{|(file, line, klass), (count, oldcount, total_age, min_age, max_age, memsize)|
          ["#{Rack::Utils.escape_html(file)}:#{'%04d' % line}",
            Rack::Utils.escape_html(klass ? klass.name : '<internal>'),
            count, oldcount, total_age / Float(count), min_age, max_age, memsize]
        }

        begin
          table = table.sort_by{|vs|
            ary = @sort_order.map{|i| Numeric === vs[i] ? -vs[i] : vs[i]}
          }
        rescue
          ts = []
          table.each{|*cols|
            cols.each.with_index{|c, i|
              h = (ts[i] ||= Hash.new(0))
              h[c.class] += 1
            }
          }
          return "<pre>Sorting error\n" + Rack::Utils.escape_html(h.inspect) + "</pre>"
        end

        headers = %w(path class count old_count average_age min_age max_age memsize).map.with_index{|e, i|
          "<th><a href='./?s=#{i}'>#{e}</a></th>"
        }.join("\n")
        header = "<tr>#{headers}</tr>"
        body = table.map{|cols|
          "<tr>" + cols.map{|c| "<td>#{c}</td>"}.join("\n") + "</tr>"
        }.join("\n")
        "<table>#{header}#{body}</table>"
      end

      def count_table_page count_table
        text = count_table.map{|k, v| "%-10s\t%8d" % [k, v]}.join("\n")
        "<pre>#{text}</pre>"
      end

      def allocated_count_table_page
        count_table_page ObjectSpace::AllocationTracer.allocated_count_table
      end

      def freed_count_table_page
        count_table_page ObjectSpace::AllocationTracer.freed_count_table
      end

      def lifetime_table_page
        table = []
        max_age = 0
        ObjectSpace::AllocationTracer.lifetime_table.each{|type, ages|
          max_age = [max_age, ages.size - 1].max
          table << [type, *ages]
        }
        headers = ['type', *(0..max_age)].map{|e| "<th>#{e}</th>"}.join("\n")
        body =  table.map{|cols|
          "<tr>" + cols.map{|c| "<td>#{c}</td>"}.join("\n") + "</tr>"
        }.join("\n")
        "<table border='1'><tr>#{headers}</tr>\n#{body}</table>"
      end

      def call env
        if /\A\/allocation_tracer\// =~ env["PATH_INFO"]
          result = ObjectSpace::AllocationTracer.result
          ObjectSpace::AllocationTracer.pause

          begin
            html = case env["PATH_INFO"]
                   when /lifetime_table/
                     lifetime_table_page
                   when /allocated_count_table/
                     allocated_count_table_page
                   when /freed_count_table/
                     freed_count_table_page
                   else
                     allocation_trace_page result, env
                   end
            #
            [200, {"Content-Type" => "text/html"}, [html]]
          ensure
            ObjectSpace::AllocationTracer.resume
          end
        else
          @app.call env
        end
      end
    end

    class TotalTracer < Tracer
      def initialize *args
        super
        ObjectSpace::AllocationTracer.setup %i(path line class)
        ObjectSpace::AllocationTracer.lifetime_table_setup true
        ObjectSpace::AllocationTracer.start
      end
    end
  end
end
