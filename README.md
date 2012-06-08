This is a library of interesting/useful code written by Alex Dowad, posted here both to share with other developers and for perusal by potential clients. Most of the code is written in Ruby 1.9. (Some may compatible with Ruby 1.8, but I didn't go out of my way to make it so.)

ALL code in this repository is free for anybody to copy, modify, and use in any program, without attribution to the author (ie. me). However, if you copy this code and post it on the Internet (with or without modifications), you must include a comment at the top of the file acknowledging me as the original author, and include a link to this GitHub repository. Make sure to test the code yourself -- I have tested it myself but can't guarantee there are no bugs.

If you notice anything which can be improved, please submit a PR; I'll credit you at the top of the relevant file.

Overview:

    /directed_graph.rb        -- a general-purpose directed graph manipulation library

    /ruby-core                -- general-purpose Ruby utilities, such as extensions to core classes
    /ruby-core/collections.rb -- extensions to Enumerable, Array, and Hash
    /ruby-core/kernel.rb      -- generally useful functions which don't have an obvious "home"
                                 so I put them in Kernel so they will be available everywhere

    /ruby-threads             -- utilities for Ruby multithreading
    /ruby-threads/threads.rb  -- custom extensions to Thread, Queue
                                 also a "synchronized wrapper" for any Ruby object which wraps all methods in Mutex#synchronized
                                 AND a general-purpose map-reduce implementation
    /ruby-threads/countdown_latch.rb -- various general-purpose synchronizers for threaded code
    /ruby-threads/cyclic_barrier.rb
    /ruby-threads/semaphore.rb
    /ruby-threads/read_write_lock.rb -- this one is especially useful

    /chinese.rb               -- utilities for working with Chinese text
                                 ALSO contains command-line driver to count word/character frequency for a Chinese text,
                                 add Pinyin transcription next to Chinese words, or convert between traditional/simplified
                                 characters
                                 must be accompanied by Chinese dictionary file "cedict.utf8"

    /rubber.rb                -- several interesting examples of Ruby metaprogramming