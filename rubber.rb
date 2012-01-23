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

# This was originally made for ActiveRecord...
# With AR, you can have multiple in-memory objects which represent the
#   same DB record
# This allows all the objects which represent the same record to share
#   other, transient "instance variables"

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
