# Ruby read-write lock implementation
# Allows any number of concurrent readers, but only one concurrent writer
# (And if the "write" lock is taken, any readers who come along will have to wait)

# If readers are already active when a writer comes along, the writer will wait for
#   all the readers to finish before going ahead
# But any additional readers who come when the writer is already waiting, will also
#   wait (so writers are not starved)

# Written by Alex Dowad
# Bug fixes contributed by Alex Kliuchunikau
# Thanks to Doug Lea for java.util.concurrent.ReentrantReadWriteLock (used for inspiration)

# Usage:
# lock = ReadWriteLock.new
# lock.with_read_lock  { data.retrieve }
# lock.with_write_lock { data.modify! }

# Implementation note: A goal for this implementation is to make the "main" (uncontended)
#   path for readers lock-free
# Only if there is reader-writer or writer-writer contention, should locks be used

require 'atomic'
require 'thread'

class ReadWriteLock
  def initialize
    @counter      = Atomic.new(0)         # single integer which represents lock state
                                          # 0 = free
                                          # +1 each concurrently running reader
                                          # +(1 << 16) for each waiting OR running writer
                                          # so @counter >= (1 << 16) means at least one writer is waiting/running
                                          # and (@counter & ((1 << 16)-1)) > 0 means at least one reader is running
    @reader_q     = ConditionVariable.new # queue for waiting readers
    @reader_mutex = Mutex.new             # to protect reader queue
    @writer_q     = ConditionVariable.new # queue for waiting writers
    @writer_mutex = Mutex.new             # to protect writer queue
  end

  WRITER_INCREMENT = 1 << 16              # must be a power of 2!
  MAX_READERS      = WRITER_INCREMENT - 1

  def with_read_lock
    while(true)
      c = @counter.value
      raise "Too many reader threads!" if (c & MAX_READERS) == MAX_READERS
      if c >= WRITER_INCREMENT
        @reader_mutex.synchronize do 
          @reader_q.wait(@reader_mutex) if @counter.value >= WRITER_INCREMENT
        end
      else
        break if @counter.compare_and_swap(c,c+1)
      end
    end

    yield

    while(true)
      c = @counter.value
      if @counter.compare_and_swap(c,c-1)
        if c >= WRITER_INCREMENT && (c & MAX_READERS) == 1
          @writer_mutex.synchronize { @writer_q.signal }     
        end
        break
      end
    end
  end

  def with_write_lock(&b)
    while(true)
      c = @counter.value
      if @counter.compare_and_swap(c,c+WRITER_INCREMENT)
        @writer_mutex.synchronize do
          @writer_q.wait(@writer_mutex) if (@counter.value & MAX_READERS) > 0
        end
        break
      end
    end

    yield

    while(true)
      c = @counter.value
      if @counter.compare_and_swap(c,c-WRITER_INCREMENT)
        if c-WRITER_INCREMENT >= WRITER_INCREMENT
          @writer_mutex.synchronize { @writer_q.signal }
        else
          @reader_mutex.synchronize { @reader_q.broadcast }
        end
        break
      end
    end
  end
end

if __FILE__ == $0

# for performance comparison with ReadWriteLock
class SimpleMutex
  def initialize; @mutex = Mutex.new; end
  def with_read_lock
    @mutex.synchronize { yield }
  end
  alias :with_write_lock :with_read_lock
end
# for seeing whether my correctness test is doing anything...
# and for seeing how great the overhead of the test is
# (apart from the cost of locking)
class FreeAndEasy
  def with_read_lock
    yield # thread safety is for the birds... I prefer to live dangerously
  end
  alias :with_write_lock :with_read_lock
end

require 'benchmark'
  
def test(lock, n_readers=20, n_writers=20, reader_iterations=50, writer_iterations=50, reader_sleep=0.001, writer_sleep=0.001)
  puts "Testing #{lock.class} with #{n_readers} readers and #{n_writers} writers. Readers iterate #{reader_iterations} times, sleeping #{reader_sleep}s each time, writers iterate #{writer_iterations} times, sleeping #{writer_sleep}s each time"
  mutex = Mutex.new
  bad   = false
  data  = 0

  result = Benchmark.measure do
    readers = n_readers.times.collect do
                Thread.new do
                  reader_iterations.times do
                    lock.with_read_lock do
                      mutex.synchronize { bad = true } if (data % 2) != 0
                      sleep(reader_sleep)
                      mutex.synchronize { bad = true } if (data % 2) != 0
                    end
                  end
                end
              end
    writers = n_writers.times.collect do
                Thread.new do
                  writer_iterations.times do
                    lock.with_write_lock do
                      value = data
                      data  = value+1
                      sleep(writer_sleep)
                      data  = value+1
                    end
                  end
                end
              end

    readers.each { |t| t.join }
    writers.each { |t| t.join }
    puts "BAD!!! Readers+writers overlapped!" if mutex.synchronize { bad }
    puts "BAD!!! Writers overlapped!" if data != (n_writers * writer_iterations * 2)
  end
  puts result
end

test(ReadWriteLock.new)
test(SimpleMutex.new)
test(FreeAndEasy.new)
end
