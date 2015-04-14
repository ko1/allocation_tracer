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
           klass ? klass.name : '<internal>',
           count, oldcount, total_age / Float(count), min_age, max_age, memsize]
        }.sort_by{|vs|
          ary = @sort_order.map{|i| Numeric === vs[i] ? -vs[i] : vs[i]}
        }

        headers = %w(path class count old_count average_age max_age min_age memsize).map.with_index{|e, i|
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

      def call env
        if /\A\/allocation_tracer\// =~ env["PATH_INFO"]
          result = ObjectSpace::AllocationTracer.result
          ObjectSpace::AllocationTracer.pause

          p env["PATH_INFO"]
          case env["PATH_INFO"]
          when /lifetime_table/
            raise "Unsupported: lifetime_table"
          when /allocated_count_table/
            text = allocated_count_table_page
          when /freed_count_table/
            text = freed_count_table_page
          else
            text = allocation_trace_page result, env
          end

          begin
            [200, {"Content-Type" => "text/html"}, [text]]
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
        ObjectSpace::AllocationTracer.start
      end
    end
  end
end
