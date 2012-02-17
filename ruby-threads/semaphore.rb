# Ruby counting semaphore implementation
# Each semaphore maintains a fixed number of "permits"
# Threads can both acquire and release permits
# If a thread tries to acquire a permit when none are available,
#   it will block until one is released

# This can be used for limiting the number of threads which can access
#   a given resource to a fixed number

# Usage:
# semaphore.with_permit { use_resource }
# ...or:
# semaphore.acquire
# use_resource
# semaphore.release

# Note that if a thread which never acquired a permit "releases" one,
#   this will permanently increase the number of permits available
# If this is your intention, use "add_permit" to make that clear

require 'atomic' # must install 'atomic' gem
require 'thread'

class Semaphore
  def initialize(permits)
    @counter   = Atomic.new(permits) # semaphore state
                                     # = (available permits) - (threads waiting)
    @queue     = ConditionVariable.new
    @mutex     = Mutex.new
  end

  def with_permit
    acquire
    yield
    release
  end

  def acquire
    while(true)
      c = @available.value
      if @available.compare_and_set(c,c-1)
        if c <= 0
          @mutex.synchronize { @queue.wait if @available.value <= 0 }
        end
        break
      end
    end
  end

  def release
    while(true)
      c = @available.value
      if @available.compare_and_set(c,c+1)
        if c < 0
          @mutex.synchronize { @queue.signal(@mutex) }
        end
        break
      end
    end
  end
  alias :add_permit :release

  def try_acquire
    c = @available.value
    @available.compare_and_set(c,c-1)
  end

  def to_s
    c = @available.value
    status = if c > 0
      " #{c} permits free"
    else
      " #{c} threads waiting"
    end
    "#<Semaphore:#{object_id.to_s(16)}#{status}>"
  end
end
