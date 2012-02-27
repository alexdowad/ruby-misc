# Alex's Ruby threading utilities

require 'thread'

# Wraps an object, synchronizes all method calls
# The wrapped object can also be set and read out
#   which means this can also be used as a thread-safe reference
#   (like a 'volatile' variable in Java)
class Synchronized
  def initialize(obj)
    @obj   = obj
    @mutex = Mutex.new
  end

  def set(val)
    @mutex.synchronize { @obj = val }
  end
  def get
    @mutex.synchronize { @obj }
  end

  def method_missing(method,*args,&block)
    result = @mutex.synchronize { @obj.send(method,*args,&block) }
    # some methods return "self" -- if so, return this wrapper
    result.object_id == @obj.object_id ? self : result
  end
end
def Synchronized(obj)
  Synchronized.new(obj)
end

# utilities for processing tasks in parallel using a pool of worker threads
# saves you from having to explicitly start and manage threads
module Enumerable
  N_WORKERS = 20
  JOB_QUEUE = Queue.new
  WORKERS   = N_WORKERS.times.collect do |n|
                t = Thread.new do
                  loop do
                    begin
                      job = JOB_QUEUE.pop
                      job.call
                    rescue Exception
                      # If an exception is thrown from inside a job,
                      # don't kill the worker thread
                      $stderr.puts "Exception from worker thread: #{$!}"
                    end
                  end
                end
              end.freeze

  # NAME: map_reduce
  # DESC: run over this collection, transforming each element in parallel, using "map_func"
  #       then reduce all the results, again in parallel, using "reduce_func"
  #       return the end result
  # ARGS: "map_func" must be a Proc which takes 1 argument, "reduce_func" must be a Proc which takes 2
  #       neither should use mutable global data, or if they do, it should be protected with a lock
  def map_reduce(map_func,reduce_func)
    result_q = []
    count    = 0 # number of results which must yet be reduced
    mutex    = Mutex.new
    wait     = ConditionVariable.new
    error    = nil

    self.each do |x|
      mutex.synchronize { count += 2 }
      JOB_QUEUE.push(lambda do
        mutex.synchronize do
          return if error
        end

        begin
          result = map_func.call(x)
        rescue Exception
          mutex.synchronize do
            error  = $!
            wait.broadcast
            return
          end
        end

        loop do
          other = mutex.synchronize do
            return if error
            count -= 1
            if result_q.empty?
              result_q.push(result)
              wait.broadcast if count <= 0
              return
            else
              result_q.pop
            end
          end

          begin
            result = reduce_func.call(result,other)
          rescue Exception
            mutex.synchronize do
              error = $!
              wait.broadcast
              return
            end
          end
        end
      end)
    end

    # wait until all the results have been reduced down to 1
    mutex.synchronize do
      count -= 1
      wait.wait(mutex) while count > 0 && error.nil?
      raise error if error
      result_q.pop
    end
  end

  def parallel_each(&block)
    raise "Must pass a block to parallel_each" if not block_given?
    self.each do |x|
      JOB_QUEUE.push(lambda do
        block.call(x)
      end)
    end
  end
end

class Queue
  # by analogy to Set[]
  def self.[](*items)
    q = Queue.new
    items.each { |i| q << i }
    q
  end

  def empty?
    self.length == 0
  end

  def to_a # will empty the queue!
    result = []
    result << pop while length > 0
    result
  end
end

class Thread
  def dead?
    not alive?
  end
end
