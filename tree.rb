# A general-purpose library for implementing tree structures with arbitrary branching
# The arbitrary branching makes this something like the GoF "Composite Pattern"...
# To add application-specific functionality, subclass Tree::Node

# Written by Alex Dowad (alexinbeijing@gmail.com)
# The original version of this file lives on the Internet at https://github.com/alexdowad/showcase/blob/master/tree.rb
# Please copy, use, modify, and enjoy it freely, but keep this notice!
# If you modify, add "# Hacked by ..." below the above name(s)

# Our trees are immutable, BUT we provide mutable "views" of trees
# You can directly traverse the immutable trees downwards, or iterate over children of a node
# With a mutable view, you can also traverse upwards/right/left
# Get a mutable view of a tree with node.mutable
# After modifying, get back a new, immutable tree (rooted at the node which was used to create the mutable view) with view.immutable

# (Note: #immutable uses #dup to copy nodes as needed. So if you store application-specific data in
#   nodes that needs to be copied, you must override #dup!)

# Mutable views proxy to the tree being viewed, so you can call other, application-specific node methods on them
# Immutable tree nodes define equality/hash code recursively based on their contents,
#   but mutable views define equality/hash code by object identity (the default for Ruby)

# Nodes can either be "branch" or "leaf" nodes -- "branches" can have children, but "leaves" cannot

#################################

# Example usage:

# class MyLeaf < Tree::Node
#   leaf_node
# end
# class MyBranch < Tree::Node
# end

# branch,leaf1,leaf2 = MyBranch.new,MyLeaf.new,MyLeaf.new
# view = branch.mutable
# view.add_child(leaf1)
# view.immutable

module Tree
  class Node
    def initialize(*children)
      raise "#{self.class} can't have child nodes" if self.class.leaf?
      @__children__ = children.freeze
    end

    def children
      @__children__
    end
    def first_child
      @__children__.first
    end
    def last_child
      @__children__.last
    end
    def descendants(&block)
      return enum_for(:descendants) if not block_given?
      children do |node|
        yield node
        if node.respond_to? :descendants
          node.descendants(&block)
        end
      end
    end

    def hash
      @hash ||= @__children__.map(&:hash).hash ^ self.class.hash
    end
    def eql?(other)
      return true if equal?(other)
      return false if self.class != other.class
      @__children__.eql?(other.children)
    end
    def ==(other)
      return true if equal?(other)
      return false if self.class != other.class
      @__children__ == other.children
    end

    def self.inherited(cls)
      cls.class_eval do
        @__leaf__ = false
        def self.leaf_node; @__leaf__ = true; end
        def self.leaf?;     @__leaf__; end
        def self.branch?;  !@__leaf__; end
      end
    end
  end

class MutableNode
  def initialize(path, node)
    @path, @node, @prev, @next, @changed = path, node, nil, nil, false
  end

  def node
    @node
  end
  def next
    @next
  end
  def previous
    @prev
  end
  alias :prev :previous
  def parent
    @path.last
  end
  def root
    root = parent
    root = root.parent while root.parent
    root
  end
  def first_child
    @first_child ||= begin
      path_up = @path.dup << self
      cs = @node.children.map { |n| MutableNode.new(path_up, n) }
      cs.each_with_index { |c,i| c.instance_eval { @prev = cs[i-1]; @next = cs[i+1] }}
      @last_child = cs.last
      cs.first
    end
  end
  def last_child
    @last_child || (__first_child__; @last_child)
  end

  def children
    return enum_for(:children) if not block_given?
    current = first_child
    (yield current; current = current.next) while current
  end
  def ancestors
    return enum_for(:ancestors) if not block_given?
    current = self.parent
    (yield current; current = current.parent) while current
  end
  def siblings(&block)
    return enum_for(:siblings) if not block_given?
    preceding(&block)
    following(&block)
  end
  def preceding
    return enum_for(:preceding) if not block_given?
    current = self.prev
    (yield current; current = current.prev) while current
  end  
  def following
    return enum_for(:following) if not block_given?
    current = self.next
    (yield current; current = current.next) while current
  end
  def descendants(&block)
    return enum_for(:descendants) if not block_given?
    children do |node|
      yield node
      if node.respond_to? :descendants
        node.descendants(&block)
      end
    end
  end

  def insert_next(node)
    node = node.node if node.is_a?(MutableNode)
    raise "Can't add #{node.class} after a node with no parent" if parent.nil?
    new_node  = MutableNode.new(@path, node)
    this_node = self
    new_node.instance_eval { @prev = this_node; @next = this_node.next }
    @next.instance_eval    { @prev = new_node } if @next
    parent.instance_eval   { @last_child = new_node } if parent.last_child.equal?(self)
    @next = new_node
    changed!
  end
  def insert_previous(node)
    node = node.node if node.is_a?(MutableNode)
    raise "Can't add #{node.class} after an node with no parent" if parent.nil?
    new_node  = MutableNode.new(@path, node)
    this_node = self
    new_node.instance_eval { @next = this_node; @prev = this_node.prev }
    @prev.instance_eval    { @next = new_node } if @prev
    parent.instance_eval   { @first_child = new_node } if parent.first_child.equal?(self)
    @prev = new_node
    changed!
  end
  def replace_with(node)
    node = node.node if node.is_a?(MutableNode)
    raise "#{node.class} can't replace an node with no parent" if parent.nil?    
    @node = node
    @first_child = @last_child = nil
    changed!
  end
  def remove
    raise "Can't remove root node" if parent.nil?
    this_node = self
    next.instance_eval { @prev = this_node.prev }
    prev.instance_eval { @next = this_node.next }
    parent.instance_eval { @first_child = this_node.next } if parent.first_child.equal?(self)
    parent.instance_eval { @last_child  = this_node.prev } if parent.last_child.equal?(self)
    changed!
  end

  def add_child(node)
    node = node.node if node.is_a?(MutableNode)
    if last_node
      last_node.insert_next(node)
    else
      @first_child = @last_child = MutableNode.new(@path.dup << self, node)
      changed!
    end
  end

  def reject_children!
    node = @first_child
    while node
      next_node = node.next
      node.remove if yield node
      node = next_node
    end
  end
  def reject_descendants!(&block)
    node = @first_child
    while node
      next_node = node.next
      if yield node
        node.remove 
      elsif node.respond_to? :reject_descendants!
        node.reject_descendants!(&block)
      end
      node = next_node
    end
  end

  def immutable
    root.__tree__
  end

  protected
  
  def __immutable__
    if @changed
      @node = @node.dup
      @node.instance_eval { @__children__ = children.map(&:__tree__) }
      @changed = false
    end
    @node
  end

  private

  def changed!
    @changed = false
    parent.changed! if parent
  end
end
end