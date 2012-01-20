# Alex's extensions for Enumerable, Array, and Hash

module Enumerable

  #*******************************************************
  # ARRAY METHODS
  # Array has some useful methods which Enumerable doesn't
  # So let's even things up a bit
  #*******************************************************

  def empty?
    each { return false }; true
  end

  # Making Enumerable conform to Array interface...
  alias :index :find_index

  def last
    reverse_each { |e| return e }
  end

  # NOTE: "sample" will be slower on general Enumerables than on Arrays,
  #   because we have to make a pass over all the elements
  # ALSO NOTE: unlike Array#sample, the order of the elements in the
  #   returned array is not completely random (if n >= self.size, it's not
  #   random at all)
  def sample(n=nil)
    if n
      choice = []
      _n     = n.to_f
      each_with_index do |x,i|
        if rand < (_n/(i+1))
          if choice.size < n
            choice << x
          else
            choice[rand(n)] = x
          end
        end
      end
      choice
    else
      choice = nil
      each_with_index do |x,i|
        choice = x if rand(i+1) == 0
      end
      choice
    end
  end

  #*********************************
  # RAISING THE LEVEL OF ABSTRACTION
  # (more power, more consiseness)
  #*********************************

  # NAME: mappend
  # DESC: like map, but return value of block must be Enumerable (or nil)
  #       contents of all returned Enumerables will be appended into an Array
  #       (this replaces the common pattern of using an array variable to
  #          accumulate results)
  def mappend
    result = []
    self.each { |a| b = yield(a); b.each { |c| result << c } if b }
    result
  end

  # NAME: +
  # DESC: Make one Enumerable which iterates over the contents of two
  def +(enum)
    Enumerator.new do |y|
      self.each { |x| y.yield(x) }
      enum.each { |x| y.yield(x) }
    end
  end

  # NAME: -
  # DESC: Make an Enumerable which iterates over elements which are in the first, but not the second
  def -(enum)
    Enumerator.new do |y|
      set = enum.to_set
      self.each do |x|
        y.yield(x) if not set.include? x
      end
    end
  end

  # NAME: to_histogram
  # DESC: returns a Hash of number of occurrences of each item in the sequence
  # EXAMPLE: ['a','b','a','a','c'].to_histogram
  #          => { 'a' => 3, 'b' => 1, 'c' => 1 }
  def to_histogram
    result = Hash.new(0)
    each { |x| h[x] += 1 }
    result
  end

  # NAME: sum
  # DESC: add all the elements in the sequence together
  def sum
    if block_given?
      inject(0) { |a,b| a+(yield b) }
    else
      inject(0) { |a,b| a+b }
    end
  end

  # NAME: product
  # DESC: take the product of all the elements in the sequence
  def product
    if block_given?
      inject(1) { |a,b| a*(yield b) }
    else
      inject(1) { |a,b| a*b }
    end
  end

  # NAME: average
  # DESC: average all the elements in the sequence
  #       (all elements must be numeric)
  def average
    return nil if empty?
    sum = n = 0
    if block_given?
      each { |x| n += 1; sum += (yield x) }
    else
      each { |x| n += 1; sum += x }
    end
    sum.to_f / n
  end

  # NAME: second
  # DESC: return second item in this sequence
  def second
    s = false
    each { |e| s ? (return e) : (s = true) }
  end

  # NAME: find_indexes
  # DESC: return an array of indexes at which element occurs (or for which block returns true)
  def find_indexes(x=nil)
    result,i = [],0
    if(x)
      each { |e| result << i if e == x; i += 1 }
    else
      each { |e| result << i if yield e; i += 1 }
    end
    result
  end

  # NAME: all_equal?
  # DESC: are all the elements in this sequence equal?
  def all_equal?
    a = self.first
    all? { |b| a == b }
  end

  #**********************************************************************
  # LAZINESS
  # All the following methods return Enumerators which yield the same
  #   elements as the corresponding core method, but do so lazily
  # (They don't generate results until they are actually needed, and only
  #   generate as many as are needed)
  # "Lazy" methods like these enable the use of infinite sequences,
  #   and in some cases they can increase performance greatly
  #**********************************************************************  

  def lazy_select(&block)
    Enumerator.new do |y|
      self.each do |x|
        y.yield(x) if block.call(x)
      end
    end
  end
  def lazy_map(&block)
    Enumerator.new do |y|
      self.each do |x|
        y.yield(block.call(x))
      end
    end
  end
  def lazy_uniq
    Enumerator.new do |y|
      set = Set.new
      self.each do |x|
        y.yield(x) if set.add?(x)
      end
    end
  end
  def lazy_compact
    Enumerator.new do |y|
      self.each { |x| y.yield(x) if not x.nil? }
    end
  end

  #*************************************************
  # STRING METHODS
  # Add one useful method from String to Enumerable,
  # so we can use it on any Enumerable object
  #*************************************************

  # NAME: split
  # DESC: like String#split
  #       but can take a block, which will be used to decide if each
  #         element is a "splitter"
  def split(element=nil)
    result,current = [],[]
    if block_given?
      each do |e|
        if yield(e)
          result << current
          current = []
        else
          current << e
        end
      end
    else
      each do |e|
        if e == element
          result << current
          current = []
        else
          current << e
        end
      end
    end
    result << current if not current.empty?
    result
  end
end

class Array

  #*************************************************************************
  # ! METHODS
  # Array comes with a number of methods which have "!" and non-"!" versions
  # The ! versions modify the Array in place
  # Extend this pattern with one more ! method which is not built in
  #*************************************************************************

  def group_by!(&block)
    replace(group_by(&block).values)
  end

  #*****************************************************************************
  # SET METHODS
  # Array doesn't have a method to add a whole enumeration of elements at a time
  # Extend it with a method which comes from Set
  #*****************************************************************************

  def merge(enum)
    enum.each { |x| self << x }
    self
  end

  # And one more general utility method:

  # NAME: filter_out
  # DESC: like reject!, but returns the rejected elements, not the ones which were kept
  def filter_out
    result,i = [],0
    while(i < size)
      if yield(e = self.at(i))
        result << e
        delete_at(i)
      else
        i += 1
      end
    end
    result
  end
end

class Hash

  # NAME: reverse
  # DESC: similar to invert, but in resulting hash, values are ARRAYS of keys from the original hash
  #       so none of the original keys are discarded, even if they mapped to the same value
  def reverse
    keys.group_by { |x| self[x] }
  end
end
