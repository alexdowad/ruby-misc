# 2 thread-safe stack implementations
# Written by Alex Dowad
# Bug fixes contributed by Alex Kliuchnikau and Remus Rusanu

# Usage:
# stack.push(1)
# stack.peek    => 1 (1 is not removed from stack)
# stack.pop     => 1 (now 1 is removed from stack)

require 'rubygems' # for compatibility with MRI 1.8, JRuby
require 'thread'
require 'atomic'   # atomic gem must be installed

# The easy one first
class ThreadSafeStack
  def initialize
    @s,@m = [],Mutex.new
  end
  def push(value)
    @m.synchronize { @s.push(value) }
  end
  def pop
    @m.synchronize { @s.pop }
  end
  def peek
    @m.synchronize { @s.last }
  end
end

# a non-locking version which uses compare-and-swap to update stack
class ConcurrentStack
  Node = Struct.new(:value,:next)

  def initialize
    @top = Atomic.new(nil)
  end
  def push(value)
    node = Node.new(value,nil)
    @top.update { |current| node.next = current; node }
  end
  def pop
    node = nil
    @top.update do |current|
      node = current
      return if node.nil?
      node.next
    end
    node.value
  end
  def peek
    node = @top.value
    return if node.nil?
    node.value
  end
end

# Test driver
if __FILE__ == $0
  require 'benchmark'
  ITERATIONS_PER_TEST = 1000000
  QUEUE,MUTEX = ConditionVariable.new,Mutex.new

  def wait_for_signal
    MUTEX.synchronize { QUEUE.wait(MUTEX) }
  end
  def send_signal
    MUTEX.synchronize { QUEUE.broadcast }
  end

  def test(klass)
    test_with_threads(klass,1)
    test_with_threads(klass,5)
    test_with_threads(klass,25)
  end

  def test_with_threads(klass,n_threads)
    stack = klass.new
    iterations = ITERATIONS_PER_TEST / n_threads
    puts "Testing #{klass} with #{n_threads} thread#{'s' if n_threads>1}, iterating #{iterations}x each"

    threads = n_threads.times.collect do
                Thread.new do
                  wait_for_signal
                  iterations.times do
                    stack.push(rand(100))
                    stack.peek
                    stack.pop
                  end
                end
              end
    n_gc = GC.count if GC.respond_to? :count
    sleep(0.05)

    result = Benchmark.measure do
      send_signal
      threads.each { |t| t.join }
    end
    puts result
    puts "Garbage collector ran #{GC.count - n_gc} times" if GC.respond_to? :count
  end

  test(ThreadSafeStack)
  test(ConcurrentStack)
end
