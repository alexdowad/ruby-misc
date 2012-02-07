# The name of this file refers to the way that highly dynamic languages
#   like Ruby can "bend like rubber" (through the use of metaprogramming
#   techniques)
# It is a collection of various fun and interesting things I have done
#   with Ruby using metaprogramming
# (I am planning to expand this over time)
#*********************************************************************

# Make object which fronts for two (or three, or four...)

class Tee
  def initialize(*objs); @objs = objs; end
  def method_missing(m,*args,&b)
    @objs.each { |o| o.__send__(m,*args,&b) }
  end
end

# With that, you can do things like:
# tee = Tee.new($stdout, File.new("log","w"))
# tee.puts "Hello world AND log file!"

#*********************************************************************

# This was made for ActiveRecord...
# With AR, you can have multiple in-memory objects which represent the
#   same DB record
# This allows all the objects which represent the same record to share
#   other, transient "instance variables"
# (Naturally, only AR objects within the same process will share the
#   values of these attributes)

require 'thread'

class Class
  def shared_attr(*attrs, options={})
    attrs.each do |attr|
      hash  = Hash.new(options[:default])
      mutex = Mutex.new
      define_method(attr) do
        mutex.synchronize { hash[self.id] }
      end
      define_method((attr.to_s+"=").to_sym) do |value|
        mutex.synchronize { hash[self.id] = value }
      end
    end
  end
end

#*********************************************************************

# Null object
# (Can be used to avoid nil checks)

class Null
  def to_s
    ""
  end
  def method_missing(method,*args)
    self
  end
end

#*********************************************************************

# "cached_method" -- create a method whose return value will be cached
#   for a given number of seconds
# If the same method is called on the same object after the cache has expired,
#   the method body will be executed again and the cache updated

# Example:

# class MyClass
#   # refresh users every 5 minutes
#   cached_method(:users,300) do
#     User.all
#   end
# end

class Class
  # create a method whose return value will be cached for "cache_for" seconds
  def cached_method(method,cache_for,&body)
    define_method("__#{method}__".to_sym) do |*a,&b|
      body.call(*a,&b)
    end
    class_eval(<<METHOD)
      def #{method}(*a,&b)
        unless @#{method}_cache && (@#{method}_expiry > Time.now)
          @#{method}_cache  = __#{method}__(*a,&b)
          @#{method}_expiry = Time.now + #{cache_for}
        end
        @#{method}_cache
      end
METHOD
  end
end

#*********************************************************************

# An implementation of the "Visitor pattern" for Ruby...
# (Compare to the verbose, bloated implementations you find in less 
#   powerful languages)

module Enumerable
  def accept_visitor(visitor)
    each do |elem|
      method = "visit#{elem.class}".to_sym
      elem.send(method,elem) if elem.respond_to? method
    end
  end
end

# Sample usage:
# Say you have a class hierarchy with Animal at the top, and 3 subclasses:
#   Cat, Dog, and Bird

# class CountAnimals
#   def initialize;   @cats = @dogs = @birds = 0; end
#   def visitCat(_);  @cats  += 1; end
#   def visitDog(_);  @dogs  += 1; end
#   def visitBird(_); @birds += 1; end
# end

# counter = CountAnimals.new
# animals.accept_visitor(counter)
