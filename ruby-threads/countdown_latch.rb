require 'atomic'
require 'thread'

class CountdownLatch
  def initialize(count)
    @counter = Atomic.new(count)
    @queue   = ConditionVariable.new
    @mutex   = Mutex.new
  end

  def count_down
    while(true)
      c = @counter.value
      return if c < 1
      if @counter.compare_and_swap(c,c-1)
        @mutex.synchronize { @queue.broadcast } if c == 1
        break
      end
    end
  end

  def await
    if @counter.value > 0
      @mutex.synchronize do
        @queue.wait(@mutex) if @counter.value > 0
      end
    end    
  end
end
