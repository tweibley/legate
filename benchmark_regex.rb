require 'benchmark'

RESULT_REGEX = /\[Result from step \d+\]|\[Result from previous step\]/i.freeze
str = "[Result from step 1]"

n = 1_000_000

Benchmark.bmbm do |x|
  x.report("recompiled") do
    n.times { str.match?(/\[Result from step \d+\]|\[Result from previous step\]/i) }
  end

  x.report("constant") do
    n.times { str.match?(RESULT_REGEX) }
  end
end
