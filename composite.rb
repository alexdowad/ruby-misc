# A general-purpose library for implementing the "Composite pattern" --
#   in other words, a tree with an arbitrary level of branching from each internal node
# The tree can be traversed both upwards and downwards, as well as from one sibling
#   to the preceding or following siblings
# Nodes can either be "branch" or "leaf" nodes -- "branches" can have children,
#   but "leaves" cannot

# Example usage:

# class MyLeaf
#   include Composite::Leaf
# end
# class MyBranch
#   include Composite::Branch
#   can_contain MyLeaf, AnotherNodeType # other types of child nodes cannot be added as children
#                                       # if 'can_contain' is omitted, any node type can be added as child
# end

# node1,node2,node3 = MyBranch.new,MyLeaf.new,MyLeaf.new
# node1.add(node2)
# node1.children.include?(node2) # => true
# node1.children.include?(node3) # => false
# node3.add_after(node2)
# node1.children.include?(node3) # => true
# node1.descendants.to_a         # => [node2, node3]
# node2.following.to_a           # => [node3]
# node3.preceding.to_a           # => [node2]
# node1.remove(node3)
# node2.replace_with(node3)

require 'set'

module Composite
module Node
  
  def next;     @__next__   end
  def previous; @__prev__   end
  def parent;   @__parent__ end
  alias :prev :previous

  # Modifying the tree structure

  def add_before(node)
    raise "Can't add #{self} before a node with no parent" if node.parent.nil?
    raise "#{node.parent.class} cannot contain nodes of type #{self.class}" unless node.parent.can_contain?(self.class)
    raise "Can't add an node before itself" if node == self
    raise "#{self} cannot be its own ancestor" if node.ancestors.include? self

    @__parent__.remove(self) if @__parent__
    @__parent__ = node.parent
    @__parent__.first_child = self if @__parent__.first_child == node
    @__next__ = node
    @__prev__ = node.prev
    node.prev = self
    @__prev__.next = self if @__prev__
  end
  def add_after(node)
    raise "Can't add #{self} after an node with no parent" if node.parent.nil?
    raise "#{node.parent.class} cannot contain nodes of type #{self.class}" if (not node.parent.can_contain?(self.class))
    raise "Can't add an node after itself" if node == self
    raise "#{self} cannot be its own ancestor" if node.ancestors.include? self

    @__parent__.remove(self) if @__parent__
    @__parent__ = node.parent
    @__parent__.last_child = self if @__parent__.last_child == node
    @__prev__ = node
    @__next__ = node.next
    node.next = self
    @__next__.prev = self if @__next__
  end
  def replace_with(node)
    raise "Can't replace an node with itself" if node == self
    raise "Can't replace #{self} with its own ancestor" if ancestors.include? node
    raise "#{node} can't replace an node with no parent" if @__parent__.nil?    

    node.parent.remove(node) if node.parent
    node.parent = @__parent__
    @__parent__.first_child = node if @__parent__.first_child == self
    @__parent__.last_child  = node if @__parent__.last_child  == self
    node.next = @__next__
    node.prev = @__prev__
    @__next__.prev = node if @__next__
    @__prev__.next = node if @__prev__
    @__next__ = @__prev__ = @__parent__ = nil
  end

  # Iterators

  def ancestors
    return enum_for(:ancestors) if not block_given?
    node = self
    while (node = node.parent)
      yield node 
    end
  end
  def siblings
    return enum_for(:siblings) if not block_given?
    parent.children { |node| yield node if node != self }
  end
  def preceding
    return enum_for(:preceding) if not block_given?
    node = self
    while (node = node.prev)
      yield node
    end
  end  
  def following
    return enum_for(:following) if not block_given?
    node = self
    while (node = node.next)
      yield node
    end
  end

  # Query methods

  def before?(node)
    following.include?(node)
  end
  def after?(node)
    preceding.include?(node)
  end

  protected 
  def next=(node)        @__next__   = node end
  def previous=(node)    @__prev__   = node end
  def parent=(node)      @__parent__ = node end
  def first_child=(node) @__first__  = node end
  def last_child=(node)  @__last__   = node end
  alias :prev= :previous=
end
end

# Branch, or internal nodes

module Composite::Branch
  include Composite::Node

  def first_child; @__first__; end
  def last_child;  @__last__;  end

  def add(child)
    raise "#{self.class} cannot contain nodes of type #{child.class}" if not can_contain?(child)
    raise "Can't add #{self} to itself" if child == self
    raise "#{child} cannot be added to its own descendant" if ancestors.include? child

    child.parent.remove(child) if child.parent
    if @__last__
      child.add_after(@__last__)
    else
      @__first__ = @__last__  = child
      child.parent = self
    end 
  end
  def remove(child)
    raise "#{child.inspect} is not a child of #{self.inspect}" if child.parent != self
    @__first__ = child.next if @__first__ == child
    @__last__  = child.prev if @__last__  == child
    child.prev.next = child.next if child.prev
    child.next.prev = child.prev if child.next
    child.parent = child.next = child.prev = nil
  end

  def children
    return enum_for(:children) if not block_given?
    node = @__first__
    while node
      yield node
      node = node.next
    end
  end
  def descendants
    return enum_for(:descendants) if not block_given?
    children do |node|
      yield node
      if node.respond_to? :descendants
        node.descendants { |desc| yield desc }
      end
    end
  end

  def reject_children!
    node = @__first__
    while node
      next_node = node.next
      remove(node) if yield node
      node = next_node
    end
  end
  def reject_descendants!(&block)
    node = @__first__
    while node
      next_node = node.next
      if yield node
        remove(node) 
      elsif node.respond_to? :reject_descendants!
        node.reject_descendants!(&block)
      end
      node = next_node
    end
  end

  private
  def self.included(klass)
    klass.class_eval do
      def self.can_contain?(klass)
        (not defined?(@__can_contain__)) || @__can_contain__.include?(klass)
      end
      def can_contain?(klass)
        self.class.can_contain?(klass)
      end

      private
      def self.can_contain(*classes)
        (@__can_contain__ ||= Set.new).merge(classes)
      end
    end
  end
end

# Leaf nodes

module Composite::Leaf
  include Composite::Node
  undef_method :first_child=, :last_child=
end
