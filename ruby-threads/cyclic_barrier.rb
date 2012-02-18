require 'thread'

class CyclicBarrier
  def initialize(n_threads)
    @n_threads = n_threads
    @counter   = 0
    @queue     = ConditionVariable.new
    @mutex     = Mutex.new
  end

  def await
    @mutex.synchronize do
      @counter += 1
      if @counter >= n_threads
        @counter = 0
        @queue.broadcast
      else
        @queue.wait(@mutex)
      end
    end
  end
end
