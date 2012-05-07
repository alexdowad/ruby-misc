This is a library of interesting/useful code written by Alex Dowad, posted here both to share with other developers and for perusal by potential clients. Most of the code is written in Ruby 1.9. (Some may compatible with Ruby 1.8, but I didn't go out of my way to make it so.)

Overview:

    /directed_graph.rb        -- a general-purpose directed graph manipulation library

    /ruby-core                -- general-purpose Ruby utilities, such as extensions to core classes
    /ruby-core/collections.rb -- extensions to Enumerable, Array, and Hash
    /ruby-core/kernel.rb      -- generally useful functions which don't have an obvious "home"
                                 so I put them in Kernel so they will be available everywhere

    /ruby-threads             -- utilities for Ruby multithreading
    /ruby-threads/threads.rb  -- custom extensions to Thread, Queue
                                 also a generic "synchronized wrapper" for any Ruby object
                                 which wraps all method calls in Mutex#synchronized
                                 AND a general-purpose map-reduce implementation
    /ruby-threads/countdown_latch.rb -- various general-purpose synchronizers for threaded code
    /ruby-threads/cyclic_barrier.rb
    /ruby-threads/semaphore.rb
    /ruby-threads/read_write_lock.rb -- this one is especially useful

    /chinese.rb               -- utilities for working with Chinese text
                                 ALSO contains command-line driver to count word/character frequency
                                 for a Chinese text
    /rubber.rb                -- several interesting examples of Ruby metaprogramming