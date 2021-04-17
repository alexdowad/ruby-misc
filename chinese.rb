# -*- coding: utf-8 -*-
# For a description of intended usage, run this file without any command-line arguments

require 'set'

# Many Chinese text-processing tasks require a dictionary
# (for example, converting between characters and Pinyin, converting between simplified and traditional characters, etc)
# We use the freely-available CEDict dictionary
# Generally, the dictionary will require some pre-processing for most tasks, but the exact type of pre-processing
#   needed can be different
# To increase performance, we do any needed pre-processing lazily

module CEDict
  # delay preparing dictionary data until it is needed
  class Promise
    def initialize(&closure)
      @value,@closure = nil,closure
    end
    def __value__
      @value ||= @closure.call
    end
    def method_missing(m,*a,&b)
      __value__.__send__(m,*a,&b)
    end
  end

  CEDICT = Promise.new do
    # read all the Chinese words from CEDict into a big array
    data = File.open(File.join(File.dirname(__FILE__), 'cedict.utf8'),'r',:encoding => 'utf-8') { |f| f.read }
    data.scan(/^([^ ]*) ([^ ]*) \[([^\]]*)\] \/(.*)\//).map { |m| m[3] = m[3].split('/'); m }
  end

  WORD_LIST = Promise.new do
    # second field is simplified characters
    CEDICT.map { |line| line[1] }.sort_by! { |word| -word.length }
  end

  CHARACTERS_TO_PINYIN = Promise.new do
    hash = {}
    CEDICT.each do |line|
      hash[line[0]] ||= line[2]
      hash[line[1]] ||= line[2]
    end
    hash
  end
  CHARACTERS_TO_ENGLISH = Promise.new do
    hash = {}
    CEDICT.each do |line|
      hash[line[0]] ||= line[3]
      hash[line[1]] ||= line[3]
    end
    hash
  end
  PINYIN_TO_DICT_ENTRY = Promise.new do
    hash = Hash.new { |h,k| h[k] = [] }
    CEDICT.each do |line|
      hash[line[2]] << [line[1], line[0], line[3]] # simplified, traditional, English definition
    end
    hash
  end
  
  SIMPLIFIED_TO_TRADITIONAL = Promise.new do
    hash = {}
    CEDICT.each do |line|
      hash[line[1]] = line[0]
    end
    hash
  end
  TRADITIONAL_TO_SIMPLIFIED = Promise.new do
    hash = {}
    CEDICT.each do |line|
      hash[line[0]] = line[1]
    end
    hash
  end
end

module Pinyin
  INITIALS = %w{b c ch d f h j k l m n p q r s sh t w x y z zh}
  FINALS   = %w{a ai an ang ao e ei en eng i ia ian iang iao ie in ing iong iu o ong ou u ua uai uan uang ue ui un uo}

  # This includes many syllables which are not valid Hanyu Pinyin, such as "shiong", etc
  # If necessary, I may add a "stop list" later
  ALL_SYLLABLES = INITIALS.product(FINALS).map(&:join) + %w{er lü lüe lün nü nüe}

  SYLLABLE_REGEX = Regexp.union(*ALL_SYLLABLES)
  SYLLABLE_TONE_REGEX = /#{SYLLABLE_REGEX}[1-5]/

  TONE_MARKS = { 1 => "\u0772", 2 => "\u0769", 3 => "\u0780", 4 => "\u0768" }
end

class Integer
  # both of the following methods assume this integer is a Unicode code point
  def is_chinese_character?
    ((self >= 0x2E80 && self <= 0x2FCF) || # radicals
     (self >= 0x31C0 && self <= 0x31EF) || # strokes
     (self >= 0x3200 && self <= 0x4DBF) || # CJK letters/months, "compatibility" chars, extension
     (self >= 0x4E00 && self <= 0x9FFF) || # most CJK chars here
     (self >= 0xF900 && self <= 0xFAFF))   # another "compatibility" range
  end
  def is_chinese_punctuation?
    # I thought Chinese punctuation should be code points 0x3000-0x303F, but double quotes are coming up as 0x201c
    #   and 0x201d!
    # I am also finding 0xff0c, 0xff1a, 0xff1f, etc. used
    (self >= 0x3000 && self <= 0x303F) || 
    (self >= 0xFF0C && self <= 0xFF1F) ||
     self == 0x201C ||
     self == 0x201D 
  end
end

class String
  include CEDict

  SUPPORTED_CHINESE_ENCODINGS = [Encoding::UTF_8, Encoding::GBK, Encoding::BIG5]

  # guess the encoding of a binary string which contains Chinese text
  # we may need to measure the frequency of common words like 'de'
  def to_chinese_text!
    possible = SUPPORTED_CHINESE_ENCODINGS.select do |encoding|
      begin
        self.force_encoding(encoding)
        self.valid_encoding?
      rescue
        false
      end
    end
    raise "Couldn't guess correct string encoding" if possible.empty?
    if possible.one?
      self.force_encoding(possible.first)
      return self
    end

    # if there is more than 1 possible encoding,
    #   guess the one which has the highest frequency of 的
    best_guess = possible.max_by do |encoding|
      self.force_encoding(encoding)
      look_for = "的".encode(encoding)
      self.chars.count { |c| c == look_for }.tap { |x| puts "found #{x} for #{encoding}" }
    end
    self.force_encoding(best_guess)
    self
  end

  # iterator for chinese characters
  def chinese_characters
    raise "Can't find Chinese characters for encoding: #{encoding}" unless encoding == Encoding::UTF_8
    return enum_for(:chinese_characters) if not block_given?
    codes = codepoints.to_enum
    chars do |c|
      yield c if codes.next.is_chinese_character?
    end
  end

  # when printing in a monospaced font, Chinese characters and punctuation appear at double the width of
  #   alphanumeric and other characters
  def print_width
    raise "Can't calculate print width for encoding: #{encoding}" unless encoding == Encoding::UTF_8
    codepoints.reduce(0) do |result,code|
      result + ((code.is_chinese_character? || code.is_chinese_punctuation?) ? 2 : 1)
    end
  end

  # take the extra width of Chinese characters and punctuation into account when centering a string in a 
  #   fixed-width field...
  def center(width)
    spaces_needed = width - self.print_width
    left_side     = spaces_needed / 2
    right_side    = spaces_needed - left_side
    (" " * left_side) << self << (" " * right_side)
  end

  # unlike English, Chinese words are not usually separated by spaces
  # so it is non-trivial to determine where each word begins and ends
  # we use a simple "greedy" approach which repeatedly takes off the biggest bite
  #   which is a Chinese word in our dictionary
  # in some cases this splits words incorrectly, but usually the accuracy is >99%
  # we could achieve higher accuracy by:
  # - using a more complete dictionary (but CEDict is the best one I know right now)
  # - using something like a hidden Markov model to find the most likely points to split each sentence
  #   (it would have to consider an entire sentence at a time)
  #   (to do this, I would need a training corpus. I think the Longman Chinese Corpus would do the trick,
  #      since it has all the words pre-split. But I don't know if it was split manually or by computer.
  #      If by computer, it might be inaccurate itself and thus a poor candidate for training.)
  WORD_REGEXP = Promise.new { Regexp.union(*WORD_LIST.__value__) }
  def chinese_words
    raise "Can't find Chinese words for encoding: #{encoding}" unless encoding == Encoding::UTF_8
    return enum_for(:chinese_words) if not block_given?
    self.scan(WORD_REGEXP.__value__) { |w| yield w }
  end

  # when both Chinese words and intervening punctuation, etc. are needed...
  # each "chunk" returned by this iterator will either be 1) a Chinese word or 2) a non-Chinese-word char
  CHUNK_WORD_REGEXP = Promise.new { Regexp.union(WORD_REGEXP.__value__, /./) }
  def chunk_chinese_words
    raise "Can't find Chinese words for encoding: #{encoding}" unless encoding == Encoding::UTF_8
    return enum_for(:chunk_chinese_words) if not block_given?
    self.scan(CHUNK_WORD_REGEXP.__value__) { |w| yield w }    
  end

  # when calling this method, must pass a block to calculate the replacement
  def replace_chinese_words!
    self.gsub!(WORD_REGEXP.__value__) { |word| yield word }
  end
end

if __FILE__ == $0

  def histogram(enum)
    count = Hash.new(0)
    enum.each { |x| count[x] += 1 }
    count
  end

  def print_table(headings, col_widths, data)
    puts headings.zip(col_widths).map { |h,w| h.ljust(w) }.join
    data.each do |cells|
      puts cells.zip(col_widths).map { |c,w|
        str = c.is_a?(Float) ? ("%0.#{w}f" % c) : c.to_s

        if c.is_a?(Float) && str.length >= w
          whole,fractional = str.split('.')
          if whole.length+1 >= w
            str = whole.to_s
          else
            str = "#{whole}.#{fractional.to_s[0...(w - whole.to_s.length - 2)]}"
          end
        end
        str.ljust(w)
      }.join
    end
  end

  # wrap an enumerator so that a period is printed for every 100
  #   elements which are iterated over
  def progress_counter(enum)
    Enumerator.new do |y|
      count = 0
      enum.each do |x|
        if (count += 1) == 100
          count = 0
          STDERR.print '.' # STDOUT could be redirected, so we print to STDERR
        end
        y.yield(x)
      end
    end
  end

  def read_text_file
    file = ARGV.shift
    if file == "-"
      $stdin.read
    elsif file.nil? or file.empty?
      STDERR.puts "You must specify an input text file, or '-' to read from standard input."
      usage
    elsif not File.exists?(file)
      STDERR.puts "The input file you specified, #{file}, doesn't exist."
      usage
    else
      binary = File.open(file,'r',:encoding => 'binary', &:read)
      binary.to_chinese_text!.encode!(Encoding::UTF_8)
    end
  end

  def usage
    STDERR.puts "Usage: ruby chinese.rb <command> <input file>"
    STDERR.puts "Commands:"
    STDERR.puts "  wordfreq    -- print statistics on Chinese word frequencies in the given file"
    STDERR.puts "  charfreq    -- print statistics on Chinese character frequencies in the file"
    STDERR.puts "  transcribe  -- insert Pinyin after each Chinese word"
    STDERR.puts "  simplified  -- convert traditional characters to simplified"
    STDERR.puts "  traditional -- convert simplified characters to traditional"
    STDERR.puts "  threeline   -- print Pinyin and English below each Chinese word"
    STDERR.puts "  lookup      -- look up words in the dictionary by Pinyin or characters"
    STDERR.puts "  toutf8      -- convert a Chinese text file to UTF-8 encoding"
    STDERR.puts
    STDERR.puts "A non-ambiguous prefix can be used in place of any command. For example, 'tra' can be used instead of 'traditional'."
    STDERR.puts "Output will be printed to the console. You can redirect it to a file like this: >file_name_here.txt"
    exit
  end

  $commands = {
    'charfreq' => lambda {
      count = histogram(progress_counter(read_text_file.chinese_characters))
      total = count.values.reduce(0,&:+)
    
      cum = rank = 0
      print_table(%w{Character Rank Frequency Cumulative},
                  [10, 8, 10, 10],
                  count.sort_by { |k,v| -v }.map { |k,v| pct = v.to_f/total; [k, rank += 1, pct, cum += pct] })
    },
    'wordfreq' => lambda {
      count = histogram(progress_counter(read_text_file.chinese_words))
      total = count.values.reduce(0,&:+)

      cum = rank = 0
      print_table(%w{Word Rank Frequency Cumulative},
                  [8, 8, 10, 10],
                  count.sort_by { |k,v| -v }.map { |k,v| pct = v.to_f/total; [k, rank += 1, pct, cum += pct] })
    },
    'transcribe' => lambda {
      puts read_text_file.replace_chinese_words! { |word| CEDict::CHARACTERS_TO_PINYIN.key?(word) ? "#{word} [#{CEDict::CHARACTERS_TO_PINYIN[word]}]" : word }
    },
    'simplified' => lambda {
      puts read_text_file.replace_chinese_words! { |word| CEDict::TRADITIONAL_TO_SIMPLIFIED[word] || word }
    },
    'traditional' => lambda {
      puts read_text_file.replace_chinese_words! { |word| CEDict::SIMPLIFIED_TO_TRADITIONAL[word] || word }
    },
    'lookup' => lambda {
      puts "Enter Pinyin, with or without a tone number, to look up a word. Enter a blank line to exit"
      lookup = lambda { |query, print_query=false|
        defs = CEDict::PINYIN_TO_DICT_ENTRY[query]
        return if defs.empty?
        puts defs.map { |d|
          s = print_query ? query + "\n" : ""
          if d[0] != d[1]
            s += "Simplified: #{d[0]}\nTraditional: #{d[1]}\n"
          else
            s += "Character: #{d[0]}\n"
          end
          s + "English: #{d[2]}"
        }.join("\n\n")
      }
      loop do
        print ">> "
        query = gets.chomp
        exit if query.empty?
        if query =~ /\d$/
          lookup[query]
        else
          1.upto(5) do |n|
            lookup[query + n.to_s, true]
          end
        end
      end
    },
    'threeline' => lambda {
      chunks = read_text_file.chunk_chinese_words
      line1,line2,line3 = "","",""
      chunks.each do |chunk|
        english,pinyin = CEDict::CHARACTERS_TO_ENGLISH[chunk],CEDict::CHARACTERS_TO_PINYIN[chunk]

        unless english && pinyin
          line1 << chunk << " "
          line2 << (" " * (chunk.print_width + 1))
          line3 << (" " * (chunk.print_width + 1))
          next
        end

        pinyin.gsub!(' ','')
        # CEDict contains lengthy explanations in brackets for some words, but we don't want those explanations
        english.gsub!(/\([^)]*\)/,'')
        english.strip!

        width  = [chunk.print_width,english.print_width,pinyin.print_width].max
        if (width + line1.length >= 80)
          puts line1;  puts line2;  puts line3;  puts
          line1.clear; line2.clear; line3.clear;
        end
        line1 << chunk.center(width) << " "
        line2 << pinyin.center(width) << " "
        line3 << english.center(width) << " "
      end
      unless line1.empty?
        puts line1; puts line2; puts line3
      end      
    },
    'toutf8' => lambda {
      print read_text_file
    }
  }

  if (command = ARGV.shift).nil?
    puts "You must specify a command."
    usage
  end

  matching = $commands.keys.select { |c| c.start_with? command }

  if matching.size == 1
    $commands[matching.first].call
  elsif matching.size > 1
    puts "\"#{command}\" is ambiguous. Did you mean one of the following?"
    puts matching.join(', ')
  else
    puts "Unknown command: #{command}"
    usage
  end
end

