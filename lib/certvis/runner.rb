module Certvis
  # Runs a fixed-size pool of worker threads over a queue of sites.
  class Runner
    def initialize(checker:, threads: 2)
      @checker = checker
      @threads = [threads.to_i, 1].max
    end

    def run(entries)
      queue = Queue.new
      entries.each { |entry| queue << entry }

      results = []
      mutex = Mutex.new

      workers = Array.new(@threads) do
        Thread.new do
          loop do
            entry = begin
              queue.pop(true)
            rescue ThreadError
              nil
            end
            break unless entry

            result = @checker.check(entry.name, entry.host, entry.port)
            mutex.synchronize { results << result }
          end
        end
      end
      workers.each(&:join)

      results
    end
  end
end
