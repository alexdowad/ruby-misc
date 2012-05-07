# Generic directed-graph implementation
# (To add application-specific functionality, override Graph and/or Node!)
# Written by Alex Dowad

# One idiosyncratic feature is that the vectors going outward from each node are ordered
#   (they are a list, not a set)
# (The parser-generator application which this was originally written for required it)

# We keep track of the vectors going in to each node, not just going out
# So it is possible to trace both backward and forward paths through the graph
# Unlike the outgoing vectors, the incoming vectors are kept as a set, not a list
#   (they have no order)
# New connections can only be added to the "out" lists, not "in" sets
# However, connections can be removed from the "in" sets, and the changes will propagate
#   automatically to the "out" lists

# Example usage:
# g = Graph.new
# n1,n2 = 2.times.collect { Node.new(g) }
# n1.out << n2
# n1.forward.include? n2   (=> true)
# n2.out << n1
# n1.recursive?            (=> true)
# n1.out.include? n2       (=> true)
# n2.in.include?  n1       (=> true)
# n1.out.count             (=> 1)
# g.start = n1
# g.reachable_nodes.include? n2 (=> true)

# Note that the "out" lists and "in" sets are Enumerable
# Also note that each graph also has a "start node"
# When a graph is created, the start node is created along with it
# But you can set a different node to be the start node (as long as it is on the graph)

require 'alex/core'
require 'set'

#**************
# CLASS: Graph
#**************

class Graph
  include Enumerable # a graph is a collection of nodes
  attr_reader :start
  def initialize
    @nodes = Set.new
    @start = Node.new(self)

    # An important Graph method, "until_no_change", uses @changed
    # Every operation which adds or removes nodes, or changes the connections between them,
    #   must set @changed to true
    @changed = false
  end

  #*****************
  # PROPERTY SETTERS
  #*****************

  def start=(node)
    raise "Start node must be on graph!" if not @nodes.include? node
    @start = node
  end

  #***********
  # ITERATORS
  #***********

  def each(&b)
    return @nodes.to_enum if not block_given?
    @nodes.each(&b)
  end
  alias :nodes :each

  # nodes which do not have any outgoing connections
  def deadend_nodes
    return enum_for(:deadend_nodes) if not block_given?
    @nodes.each { |n| yield n if n.out.empty? }
  end
  alias :leaf_nodes :deadend_nodes

  # "infinite loops": sets of nodes which are all reachable from the others,
  #   but for which there is no "way out"
  def infinite_loops
    reachable_sets = @nodes.group_by(&:forward)
    reachable_sets.each do |reachable,nodes|
      yield reachable if reachable == nodes.to_set
    end
  end

  #***************
  # QUERY METHODS
  #***************

  # get number of nodes on graph
  def size
    @nodes.size
  end

  # get set of nodes which can be reached from start node
  def reachable_nodes
    recursive_set(@start) { |n| n.out }
  end

  #*********************
  # MODIFYING THE GRAPH
  #*********************

  def add(node)
    return if node.graph == self
    node.graph.remove(node) if not node.graph.nil?
    @nodes << node
    node.instance_exec(self) { |g| @graph = g }
    @changed = true
    self
  end
  alias :<< :add
  def add_all(nodes)
    nodes.each { |n| add(n) }
  end

  def remove(node)
    return if node.graph != self
    node.in.clear
    node.out.clear
    @nodes.delete(node)
    node.instance_eval { @graph = nil }
    @start = nil if @start == node
    @changed = true
    node
  end
  alias :delete :remove

  # make a copy of a node and add it to this graph
  # all the *outgoing* connections will be the same, but *not* incoming
  def duplicate(node)
    raise "Can't duplicate a node from another graph!" if node.graph != self
    new_node = node.dup
    @nodes << new_node
    @changed = true
    new_node.out.each { |n| new_node.out.send(:__connect__, n) }
    new_node.in.clear
    new_node
  end
  
  # remove nodes for which block returns true
  def reject!
    return enum_for(:reject!) if not block_given?
    each { |n| remove(n) if yield n }
    self
  end 
  # remove nodes for which block returns false
  def select!
    return enum_for(:select!) if not block_given?
    each { |n| remove(n) if not yield n }
    self
  end

  # keep executing the given block until the nodes/connections on the graph don't change
  def until_no_change
    begin @changed = false; yield; end while @changed
  end

  # remove nodes which are not reachable from the start node
  def trim_unreachable!
    to_keep = reachable_nodes
    select! { |n| to_keep.include? n }
  end
end

#***************************
# CLASS: Node
# DESC:  One node on a graph
#***************************

class Node
  attr_reader :graph, :out, :in 
  def initialize(graph=nil,*children)
    @out,@in = Outgoing.new(self),Incoming.new(self)
    graph.add(self) if not graph.nil?
    @graph   = graph
    @out.add_all(children)
  end

  #***************
  # QUERY METHODS
  #***************

  def recursive?
    forward.include? self
  end
  def directly_recursive?
    @out.include? self
  end

  #*********************
  # SEARCHING THE GRAPH
  #*********************

  # set of nodes which can be reached by traversing forward connections
  def forward
    recursive_set(*@out) { |n| n.out }
  end
  # set of nodes which can be reached by traversing backward connections
  def backward
    recursive_set(*@in) { |n| n.in }
  end

  #*********************
  # MODIFYING THE GRAPH
  #*********************

  # merge this node with "node", removing the redundant node from graph
  # if this node and "node" are connected, the resulting node will not loop back to itself
  # BUT, if this node OR "node" already loops back to itself, the resulting node will too
  def merge_with(node)
    raise "Cannot merge a node with itself!" if node == self
    @in.delete(node)
    @out.delete(node)
    node.in.each do |n|
      n.out.map! { |o| o == node ? self : o }
    end
    @out.add_all(node.out)
    @graph.start = self if @graph.start == node
    @graph.remove(node)
  end

  # move all incoming connections to "node" instead
  # (except incoming connections directly *from* "node")
  # if this node is not reachable from "node", remove it from graph
  def replace_with(node) 
    raise "Cannot replace a node with itself!" if node == self
    @in.each do |i|
      i.out.map! { |n| n == self ? node : n } if i != node
    end
    @graph.start = node if @graph.start == self
    @graph.remove(self) if not node.forward.include? self
  end

  # make all incoming connections jump over this node
  # then remove it from the graph
  # (if this node loops back directly to itself, that will not affect the resulting graph)
  def inline
    @out.delete(self)
    @in.each do |n|
      i = 0
      while(i < n.out.length)
        n.out[i,1] = @out if n.out[i] == self
        i += 1
      end
    end
    @graph.remove(self)
  end
end

#********************************************************************************
# CLASS: Outgoing
# DESC:  Represents the outward-pointing connections from a Node
#        Array interface (except for some Array methods which don't make sense
#          in this context)
#        Changes are automatically propagated to the "in" sets of connected nodes
#********************************************************************************

class Outgoing
  include Enumerable
  def initialize(node)
    @this   = node
    @others = []
  end

  #**********
  # ITERATORS
  #**********

  def each(&b)
    return @others.to_enum if not block_given?
    @others.each(&b)
  end

  #**************
  # QUERY METHODS
  #**************

  def [](a,b=nil)
    b ? @others[a,b] : @others[a]
  end
  def size
    @others.size
  end
  alias :length :size
  def empty?
    @others.empty?
  end
  def count(x=nil,&b)
    x ? @others.count(x,&b) : @others.count(&b)
  end

  def ==(other)
    @others == other.to_a
  end

  #***************
  # SET OPERATIONS
  #***************

  def &(nodes); @others & nodes; end
  def |(nodes); @others | nodes; end
  def -(nodes); @others - nodes; end

  #**************************
  # MODIFYING THE CONNECTIONS
  #**************************

  def <<(node)
    @others << node
    __connect__(node)
    self
  end
  def add_all(nodes)
    nodes.each { |n| self << n }
  end

  def pop
    node = @others.pop
    __disconnect__(node)
    node
  end
  def shift
    node = @others.shift
    __disconnect__(node)
    node
  end
  def unshift(node)
    @others.unshift(node)
    __connect__(node)
    self
  end

  def delete(node)
    return if not @others.delete(node)
    __disconnect__(node)    
    node
  end
  def delete_at(index)
    raise "Index #{index} out of bounds: should be 0-#{size-1}" if not (0...(@others.size)).include? index
    old = @others.delete_at(index)
    __disconnect__(old)
    old
  end

  def insert(*nodes)
    @others.insert(*nodes)
    nodes.each { |node| __connect__(node) }
  end

  # this one is a little complex, since we want to mimic all the functionality of Array#[]
  def []=(a,b,c=nil)
    if c
      raise "Index #{a} out of bounds: should be #{-size}-#{size-1}" if not (-size...size).include? a
      raise "Slice length #{b} cannot be negative" if b < 0
      old = @others[a,b]
      @others[a,b] = c.to_a
      old.each { |node| __disconnect__(node) }
      if c.respond_to? :each
        c.each   { |node| __connect__(node) }
      else
        __connect__(c)
      end
      c
    elsif a.is_a? Range
      self[a.first,(a.last-a.first+1)] = b
    else
      size = @others.size
      raise "Index #{a} out of bounds: should be #{-size}-#{size}" if not (-size..size).include? a
      raise "Only Nodes may be stored in Node.out!" if not b.is_a? Node
      return if @others[a] == b
      old = @others[a]
      @others[a] = b
      __disconnect__(old) if not old.nil?
      __connect__(b)
      b
    end
  end

  def clear
    pop while(@others.size > 0)
    self
  end

  def uniq!
    changed = @others.uniq!
    # all the nodes which appeared in @others before are still there, so no need to propagate changes to in sets
    @graph.instance_eval { @changed = true } if changed
  end

  def map!
    return enum_for(:map!) if not block_given?
    i = 0
    while(i < @others.size)
      self[i] = yield(@others[i])
      i += 1
    end
    self
  end
  def reject!
    return enum_for(:reject!) if not block_given?
    i = 0
    changed = false
    while(i < @others.size)
      if yield(@others[i])
        changed = true
        delete_at(i)
      else
        i += 1
      end
    end
    changed ? self : nil
  end

  private
  # these two are used to keep consistency with the "in" sets of connected nodes
  def __connect__(node)
    raise "Cannot connect to a node which is not on the same graph!" if node.graph != @this.graph
    node.in.instance_exec(@this) { |n| @others << n }
    @graph.instance_eval { @changed = true }
  end
  def __disconnect__(node)
    node.in.delete(@this) if not @others.include? node
    @graph.instance_eval { @changed = true }
  end
end

#************************************************
# CLASS: DeadEndNode
# DESC:  A node which cannot point to other nodes
#        (But others can point to it)
#************************************************

class DeadEndNode < Node
  def initialize(graph=nil)
    @out,@in = NoConnections.new(self),Incoming.new(self)
    graph.add(self) if not graph.nil?
    @graph   = graph
  end
end
class NoConnections < Outgoing # used exclusively by DeadEndNode
  def initialize(node)
    super
  end

  def <<(node)
    raise "No outward connections can originate from this node!"
  end
  alias :unshift :<<
  def insert(*nodes)
    raise "No outward connections can originate from this node!"
  end
  def []=(a,b,c=nil)
    raise "No outward connections can originate from this node!"
  end
end

#**************************************************************
# NAME: SinglePathNode
# DESC: A node which can only point to one other node (at most)
#**************************************************************

class SinglePathNode < Node
  def initialize(graph=nil,child=nil)
    @out,@in = OneConnection.new(self),Incoming.new(self)
    graph.add(self) if not graph.nil?
    @graph   = graph
    out << child if not child.nil?
  end
end
class OneConnection < Outgoing # used exclusively by SinglePathNode
  def initialize(node)
    super
  end

  def <<(node)
    raise "Only one connection can originate from this node!" if size > 0
    super
  end
  alias :unshift :<<
  def insert(*nodes)
    raise "Only one connection can originate from this node!" if size + nodes.size > 1
    super
  end
  def []=(a,b,c=nil)
    if c && c.respond_to?(:each) && c.size > 1
      raise "Only one connection can originate from this node!"
    end
    super   
  end
end

#******************************************************************************************
# CLASS: Incoming
# DESC:  Represents the inward-pointing connections entering a node
#        Set interface (except for some Set methods which don't make sense in this context)
#        Connections can be removed, but not added ("out" lists must be used for that)
#        Changes are automatically propagated to the "out" lists of the connected nodes
#******************************************************************************************

class Incoming
  include Enumerable
  def initialize(node)
    @this   = node
    @others = Set.new
  end

  #**********
  # ITERATORS
  #**********

  def each(&b)
    return @others.to_enum if not block_given?
    @others.each(&b)
  end

  #**************
  # QUERY METHODS
  #**************

  def size
    @others.size
  end
  alias :length :size
  def empty?
    @others.empty?
  end

  #***************
  # SET OPERATIONS
  #***************
 
  def &(nodes); @others & nodes; end
  def |(nodes); @others | nodes; end
  def -(nodes); @others - nodes; end
  def ^(nodes); @others ^ nodes; end

  #**************************
  # MODIFYING THE CONNECTIONS
  #**************************

  def delete(node)
    return self if not @others.delete?(node)
    node.out.delete(@this)
    self
  end
  def delete?(node)
    return nil if not @others.delete?(node)
    node.out.delete(@this)
    self
  end  

  def subtract(nodes)
    nodes.each { |n| delete(n) }
    self
  end

  def reject!
    return enum_for(:reject!) if not block_given?
    changed = false
    each do |n|
      if(yield n)
        @others.delete(n)
        n.out.delete(@this)
        changed = true
      end
    end
    changed ? self : nil
  end
  def clear
    each { |n| delete(n) }
    self
  end
end


#********************
# COPYING THE GRAPH
#********************

class Graph
  # make a deep copy of this graph (using "dup" to copy the individual nodes)
  def dup
    graph = super   # shallow copy (points to original nodes)
    nodes = Set.new # to keep copied nodes in
    table = {}      # to keep track of which copied nodes correspond to which original nodes

    # copy all the nodes
    @nodes.each { |n| nodes << (table[n] = n.dup) }
    # make copied nodes point to copied graph
    nodes.each { |n| n.instance_exec { @graph = graph } }
    # make copied graph point to set of copied nodes, not original nodes
    # and make start node for copied graph point to copied start node
    graph.instance_exec(@start) { |s| @nodes = nodes; @start = table[s] if not s.nil? }
    # remove links between copied nodes and original nodes
    nodes.each do |node|
      node.out.clear
      node.in.clear
    end
    # add new links
    @nodes.each do |node| 
      node.out.each do |n|
        table[node].out << table[n]
      end
    end

    graph
  end
end

class Node
  def dup # FIXME: should duplicated node be added to graph???
    node = super
    node.instance_exec(self) do |n|
      @out = n.out.dup
      @in  = n.in.dup
    end
    node.out.instance_eval { @this = node; @others = @others.dup }
    node.in.instance_eval  { @this = node; @others = @others.dup }
    node
  end
end

#********************
# SEARCHING THE GRAPH
#********************

class Node

  # METHOD:  search
  # DESC:    does a depth-first search from a given node
  #          (keeping track of already-searched nodes, to avoid infinite loops)
  # RETURNS: set of found nodes
  # USAGE:
  # found = graph.search do
  #   follow   { |n| ... }
  #   kill     { |n| ... }
  #   find     { |n| ... }
  #   continue { |n| ... }
  # end

  # The "follow" block should return a node or list of nodes; these are the connections which
  #   we should follow from this node
  # If it returns nil, then this node will be taken to be a "dead end"

  # The other 3 blocks should return boolean values
  # "find"     : is this one of the nodes we are looking for?
  # "continue" : if so, should we continue searching forward from this node?
  # "kill"     : should we stop searching forward from this node?
  # (if both "continue" and "kill" return true, then "kill" will win out: the current search
  #   path will end)

  # All of these parameters have default values. By default...
  # - All connections in the "out" lists will be followed
  # - "find" is true for all nodes
  # - "continue" and "kill" are false for all nodes
  # (To make "search" do anything useful, at least one of these defaults must be overridden)

  def search(&block)
    follow,kill,find,continue = SearchParams.process(&block)

    visited,found = Set.new,Set.new
    search  = lambda do |node|
      next if not visited.add? node # if we have already visited this node, return immediately
      if find[node]   # check if this is one of the nodes we are looking for
        found << node 
        next if not continue[node]  # should we keep searching forward after finding a node?
      end
      next if kill[node]            # if this node meets our "kill" criteria, this search path ends here
      [*follow[node]].each do |n|
        search[n]                   # otherwise, search paths from this node which meet our "follow" criteria
      end
    end

    search[self]
    found
  end

  # METHOD: search_backward
  # DESC:   like "search", but follows backward connections by default
  def search_backward(&block)
    search do
      follow { |n| n.in }
      instance_eval(&block)
    end
  end

  # METHOD:  find_paths
  # DESC:    like "search", but returns paths rather than nodes
  # RETURNS: an array of paths, each of which leads to a node in the "find" set
  #          each path is an array of nodes, each leading to the next
  #          the node which we start from will *not* appear at the beginning of each array,
  #            but the "destination" node will appear at the end of each array
  #          paths which loop will not be returned (so number of paths will always be finite)
  def find_paths(&block)
    follow,kill,find,continue = SearchParams.process(&block)

    paths,path = [],[]
    search = lambda do |node|
      if    find[node]
        paths << path.dup
        next if not continue[node]
      end
      next if kill[node]
      [*follow[node]].each do |n|
        next if path.include? n
        path.push(n)
        search[n]
        path.pop
      end
    end

    [*follow[self]].each do |n| 
       path.push(n)
       search[n] 
       path.pop
    end

    paths
  end

  # METHOD: find_paths_backward
  # DESC:   like "find_paths", but follows backward connections by default
  def find_paths_backward(&block)
    find_paths do
      follow { |n| n.in }
      instance_eval(&block)
    end    
  end

  # METHOD: paths_to
  # DESC:   find paths from this node to "node"
  #         if "node" == self, return recursive paths through the graph back to self
  def paths_to(node)
    find_paths do
      find { |n| n == node }
    end
  end

  # used by search methods
  SearchParams = Object.new
  class << SearchParams
    def process(&block)
      @follow = @kill = @find = @continue = nil
      instance_eval(&block)
      @follow   ||= lambda { |n| n.out }
      @kill     ||= lambda { |n| false }
      @find     ||= lambda { |n| true }
      @continue ||= lambda { |n| false }
      return @follow,@kill,@find,@continue
    end
    
    def follow(&block);   @follow   = block; end
    def kill(&block);     @kill     = block; end
    def find(&block);     @find     = block; end
    def continue(&block); @continue = block; end
  end
end

#********************
# TEXT REPRESENTATION
#********************

# When creating input data for an automated test suite, it is useful to be able to
#   write out the structure of a graph in text form

# Usage:
# graph = Graph(File.read(filename))

# Example of accepted format:
#
# START: NodeClass1(arg1)    # arbitrary Ruby code can appear after the colon
# A,B: NodeClass2(arg2,arg3) #   and up until the next newline
# START -> A                 # the node called 'START' will be the start node
# A -> B -> A

def Graph(str)
  graph = Graph.new
  nodes = {}
  str.lines.each do |line|
    case line
    when /^\s*(\w+):(.*)$/
      name,code = $~[1,2]
      graph << (nodes[name] = eval(code))
    when /^\s*(\w+)\s*->\s*(\w+)((\s*->\s*\w+)*)\s*(#.*)?$/
      name1,name2,others = $~[1,3]
      [name1,name2].each do |name|
        raise "Undefined node: #{name} on line: #{line}" if not nodes.key? name
      end
      nodes[name1].out << nodes[name2]
      
      if others != ""
        # repeat on the part of this line which we have not processed yet
        line = name2+others
        redo
      end
    when /^\s*(#.*)?$/
      next
    else
      raise "Couldn't parse this line: #{line}"
    end
  end
  raise "No start node defined! There should be a node called START." if not nodes.key? 'START'
  graph.start = nodes['START']
  graph
end

#********************
# GRAPH VISUALIZATION
#********************

# When testing and debugging, it can be incredibly useful to get pictures of what
#   a graph looks like
# There is a free program called Graphviz which accepts a description of a graph, written in
#   a language called "DOT", and converts it into a .gif, .jpeg, .bmp, etc.
# To use the following code, Graphviz must be installed and on the system path

# Usage:
# graph.to_gif(:filename => "a.gif", :highlight => set_of_nodes, :title => "MY GRAPH")

require "tempfile"

class Graph
  def to_gif(options={})
    filename = options[:filename] || "graph.gif"
    filename += ".gif" if not filename.end_with?(".gif")
    message = nil
    Tempfile.open("graph") do |f|
      f.write(self.to_dot(options))
      f.flush
      message = `dot -Tgif #{f.path} -o "#{filename}"`
    end
    f.unlink
    message
  end

  def to_dot(options={})
    s = "digraph {\n"
    if options[:title]
      s += "graph [label=\"#{options[:title]}\"]\n"
    end
    if options[:highlight]
      options[:highlight].each do |node|
        s += "\"#{node.hash}\" [style=filled fillcolor=gold]\n"
      end
    end
    s += map(&:to_dot).join("\n")
    s + "}"
  end
end

class Node
  def to_dot
    # FIXME: escape double-quotes inside captions
    s = "\"#{hash}\" [label=\"#{caption}\" color=#{color}]\n"
    out.each_with_index { |n,i| s += "\"#{hash}\" -> \"#{n.hash}\" [label=\"#{i}\"]\n" }
    s
  end

  # Override the following methods to give distinctive appearance to different types of nodes
  def caption
    hash.to_s(16)
  end
  def color
    "black"
  end
end

#*******************
# GRAPH MINIMIZATION
#*******************

# Depending on what nodes represent, it may be possible to merge groups of equivalent nodes
# For example, if the nodes represent states of a state machine, some states may be equivalent
# Merging these states can simplify the state machine, and make it more compact

# This code assumes that 'equivalence' between nodes depends on outgoing connections, but
#   NOT incoming connections
# If all the outgoing connections from two nodes go to the same (or equivalent) nodes,
#   those two nodes are also considered equivalent
# (Therefore 'equivalence' is defined recursively)
# The *order* of outgoing connections is assumed to be meaningful; if it is not, then some
#   equivalent nodes may not be merged

# To make this code work, Node must be subclassed, and the subclasses must implement a method
#   called "signature". "signature" must return a data value (perhaps an array of values)
#   which represents all the data stored *inside* the node. If the values returned by "signature"
#   are equal, and outgoing connections are also the same, then a set of nodes are equivalent
#   and can be merged.

# (The algorithm used is very similar to Hopcroft's classic algorithm for DFA minimization.
#  However, this algorithm will probably not scale as well to very large graphs.
#  If this later needs to be used on huge graphs, the algorithm may need to be adjusted.)

class Graph
  def minimize!
    groups   = nodes.group_by(&:signature).values
    n        = nodes.map { |n| n.out.size}.max
    worklist = groups.product((0...n).to_a)
    groups   = groups.to_set

    group    = {}
    groups.each do |g|
      g.each { |n| group[n] = g }
    end    
    inverse = n.times.map { Hash.new }
    populate_inverse = lambda do |to_process|
      to_process.each do |g|
        (0...n).each do |i|
          inverse[i][g] = Set.new
        end
        g.each do |n|
          n.in.each { |x| inverse[x.out.index(n)][g] << group[x] }
        end
      end
    end
    populate_inverse[groups]

    while(not worklist.empty?)
      splitter,i = worklist.pop
      inverse[i][splitter].each do |g|
        # This is the part which would have to change to be exactly the same as Hopcroft's algorithm
        # Instead of splitting into many groups, it should only split into 2
        # And then we can avoid adding some of the created groups back to the worklist
        split = g.group_by { |n| group[n.out[i]] }
        next if split.size == 1

        groups.delete(g)
        groups.add_all(split.values)
        split.values.each do |x|
          x.each { |n| group[n] = x }
        end        

        to_process = Set.new
        g.each { |n| n.out.each { |x| to_process << group[x] } }
        populate_inverse[to_process]
        populate_inverse[split.values]

        (0...n).each do |index|
          if(idx = worklist.index([g,index]))
            worklist[idx,1] = split.values.map { |x| [x,index] }
          else
            worklist.add_all(split.values.map { |x| [x,index] })
          end
        end
      end
    end
 
    keep = groups.to_h { |g| [g,g.first] }
    keep.values.each do |n|
      n.out.map! { |x| keep[group[x]] }
    end
    self.start = keep[group[self.start]]
    groups.each do |g|
      g.delete(keep[g])
      g.each { |n| remove(n) }
    end    
  end
end

class Node
  # default definition which will do for nodes which do not contain any special data
  def signature
    self.class
  end
end
