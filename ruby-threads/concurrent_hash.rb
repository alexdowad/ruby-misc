load 'read_write_lock.rb'

# A highly-concurrent version of Hash
# Uses lock striping
# Still haven't implemented all the methods of Hash
# Also have to make sure that behavior as far as return values,
#   optional blocks, etc. exactly matches the Hash interface

class ConcurrentHash
  include Enumerable

  STRIPINESS = 16

  def initialize(*args,&block)
    @buckets = STRIPINESS.times.collect { Hash.new(*args,&block) }
    @locks   = STRIPINESS.times.collect { ReadWriteLock.new }
  end

  def [](k);    read_hash(k)   { |h| h[k] }; end
  def []=(k,v); modify_hash(k) { |h| h[k] = v }; end
  
  def key?(k);      read_hash(k) { |h| h.key? k };       end
  def value?(k);    read_hash(k) { |h| h.value? k };     end
  def member?(k);   read_hash(k) { |h| h.member? k };    end
  def include?(k);  read_hash(k) { |h| h.include? k };   end
  def has_key?(k);  read_hash(k) { |h| h.has_key? k };   end
  def has_value?(k);read_hash(k) { |h| h.has_value? k }; end

  def key(v)
    read_each_hash do |h|
      if key = h.key(v)
        return key
      end
    end
    false  
  end
  def rassoc(v)
    read_each_hash do |h|
      if pair = h.rassoc(v)
        return pair
      end
    end
    nil
  end

  def empty?
    read_each_hash { |h| return true if h.empty? }
    false
  end

  def each
    return to_enum if not block_given?

    # This could easily be implemented with read_each_hash
    # But we do *not* want to continuously hold the lock for a bucket while 
    #   we iterate over every key-value pair in it
    # (Thus shutting all other threads out)
    # Especially because the block we yield to could be slow
    #   (Or even transfer control to a different fiber!)
    0.upto(STRIPINESS-1) do |i|
      iterator = @locks[i].with_read_lock { @buckets[i].each }
      loop do
        value = @locks[i].with_read_lock { iterator.next }
        yield value
      end
    end
  end

  def size
    result = 0
    read_each_hash { |h| result += h.size }
    result
  end 
  alias :length :size

  def to_a
    result = []
    read_each_hash { |h| result.concat(h.to_a) }
    result
  end
  def keys
    result = []
    read_each_hash { |h| result.concat(h.keys) }
    result
  end
  def values
    result = []
    read_each_hash { |h| result.concat(h.values) }
    result
  end

  def delete(key)
    modify_each_hash { |h| h.delete(key) }
  end
  def delete_if(&block)
    modify_each_hash { |h| h.delete_if(&block) }
  end
  def keep_if(&block)
    modify_each_hash { |h| h.keep_if(&block) }
  end

  def shift
    # should we take the read lock first to check if empty,
    #   then only take the write lock when we find the bucket to shift from?
    modify_each_hash { |h| return h.shift if not h.empty? }
    nil
  end

  def default
    @locks[0].with_read_lock { @buckets[0].default }    
  end
  def default=(value)
    modify_each_hash { |h| h.default = value }
  end
  def default_proc
    @locks[0].with_read_lock { @buckets[0].default_proc }    
  end
  def default_proc=(value)
    modify_each_hash { |h| h.default_proc = value }
  end

  private
  def read_hash(key)
    i = key.hash % STRIPINESS
    @locks[i].with_read_lock { yield @buckets[i] }
  end
  def modify_hash(key)
    i = key.hash % STRIPINESS
    @locks[i].with_write_lock { yield @buckets[i] }
  end

  def read_each_hash
    0.upto(STRIPINESS-1) do |i|
      @locks[i].with_read_lock { yield @buckets[i] }
    end
  end
  def modify_each_hash
    0.upto(STRIPINESS-1) do |i|
      @locks[i].with_write_lock { yield @buckets[i] }
    end
  end
end
