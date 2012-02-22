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

  ['dup','clone'].each do |method|
    class_eval <<DEF
    def #{method}
      super.instance_eval do
        @buckets.map! { |h| h.dup }
        @locks = STRIPINESS.times.collect { ReadWriteLock.new }
        self
      end
    end
DEF
  end

  def hash
    result = 0
    0.upto(STRIPINESS-1) do |i|
      result ^= @locks[i].with_read_lock { @buckets[i].hash }
    end
    result
  end

  def [](k);    read_hash(k)   { |h| h[k] }; end
  def []=(k,v); modify_hash(k) { |h| h[k] = v }; end
  alias :store :[]=
  
  def key?(k);       read_hash(k) { |h| h.key? k };       end
  def value?(k);     read_hash(k) { |h| h.value? k };     end
  def fetch(k);      read_hash(k) { |h| h.fetch(k) };     end
  def member?(k);    read_hash(k) { |h| h.member? k };    end
  def include?(k);   read_hash(k) { |h| h.include? k };   end
  def has_key?(k);   read_hash(k) { |h| h.has_key? k };   end
  def has_value?(k); read_hash(k) { |h| h.has_value? k }; end

  ['key','assoc','rassoc'] do |method|
    class_eval <<DEF
    def #{method}(x)
      read_each_hash do |h|
        if result = h.#{method}(x)
          return result
        end
      end
      false  
    end
DEF
  end

  def empty?
    read_each_hash { |h| return false if not h.empty? }
    true
  end

  # Benchmark these iterators and compare performance with the implementation
  #   used by 'select' and 'reject':

  ['each','each_key','each_value','each_pair'].each do |method|
    class_eval <<DEF
    def #{method}
      return to_enum(:#{method}) if not block_given?

      # This could easily be implemented with read_each_hash
      # But we do *not* want to continuously hold the lock for a bucket while 
      #   we iterate over every key-value pair in it
      # (Thus shutting all other threads out)
      # Especially because the block we yield to could be slow
      #   (Or even transfer control to a different fiber!)
      0.upto(STRIPINESS-1) do |i|
        iterator = @locks[i].with_read_lock { @buckets[i].#{method} }
        loop do
          value = @locks[i].with_read_lock { iterator.next }
          yield value
        end
      end
    end
DEF
  end

  def size
    result = 0
    read_each_hash { |h| result += h.size }
    result
  end 
  alias :length :size

  def clear
    modify_each_hash { |h| h.clear }
  end

  ['to_a','flatten','keys','values'].each do |method|
    class_eval <<DEF
    def #{method}
      result = []
      read_each_hash { |h| result.concat(h.#{method}) }
      result
    end
DEF
  end

  def merge(other)
    self.dup.merge!(other)
  end
  def merge!(other)
    # should I just call merge! on each individual hash?
    # need performance benchmarking!
    other.each do |k,v|
      modify_hash(k) { |h| h[k] = v }
    end
  end

  def rehash
    modify_each_hash { |h| h.rehash }
  end
  def replace(other)
    clear
    other.each do |k,v|
      self[k] = v
    end
  end
  def invert
    # should this return a ConcurrentHash?
    result = {}
    read_each_hash do |h|
      h.each do |k,v|
        result[v] = k
      end
    end
    result
  end

  ['select','reject'].each do |method|
    class_eval <<DEF
    def #{method}(&block)
      self.dup.#{method}!(&block)
    end
    def #{method}!
      0.upto(STRIPINESS-1) do |i|
        lock = @locks[i]
        lock.acquire_write_lock
        @buckets[i].#{method}! do |k,v|
          lock.release_write_lock
          yield k,v
          lock.acquire_write_lock
        end
        lock.release_write_lock
      end   
    end
DEF
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
  def compare_by_identity?
    @locks[0].with_read_lock { @buckets[0].compare_by_identity? }
  end
  def compare_by_identity
    modify_each_hash { |h| h.compare_by_identity }
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
