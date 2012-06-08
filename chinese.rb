require 'set'

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
    data = File.open('cedict.utf8','r',:encoding => 'utf-8') { |f| f.read }
    data.scan(/^([^ ]*) ([^ ]*) \[([^\]]*)\] \/([^\/]*)\//).map { |m| m.to_a }
  end

  WORD_LIST = Promise.new do
    # second field is simplified characters
    CEDICT.map { |line| line[1] }.sort_by! { |word| -word.length }
  end

  CHARACTERS_TO_PINYIN = Promise.new do
    hash = {}
    CEDICT.each do |line|
      hash[line[0]] = line[2]
      hash[line[1]] = line[2]
    end
    hash
  end
  CHARACTERS_TO_ENGLISH = Promise.new do
    hash = {}
    CEDICT.each do |line|
      hash[line[0]] = line[3]
      hash[line[1]] = line[3]
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

class String
  include CEDict

  SUPPORTED_CHINESE_ENCODINGS = [Encoding::UTF_8, Encoding::GBK, Encoding::BIG5]

  # guess the encoding of a binary string which contains Chinese text
  # we may need to measure the frequency of common words like 'de'
  def as_chinese_text
    SUPPORTED_CHINESE_ENCODINGS.each do |encoding|
      begin
        self.force_encoding(encoding)
        return self if self.valid_encoding?
      rescue
      end
    end
    raise "Couldn't guess correct string encoding"
  end

  # iterator for chinese characters
  def chinese_characters
    raise "Can't find Chinese characters for encoding: #{encoding}" unless SUPPORTED_CHINESE_ENCODINGS.include?(encoding)
    return enum_for(:characters) if not block_given?
    codes = codepoints
    # note: in Unicode, CJK punctuation is 0x3000-0x303F
    chars do |c|
      i = codes.next
      if ((i >= 0x2E80 && i <= 0x2FCF) || # radicals
          (i >= 0x31C0 && i <= 0x31EF) || # strokes
          (i >= 0x3200 && i <= 0x4DBF) || # CJK letters/months, "compatibility" chars, extension
          (i >= 0x4E00 && i <= 0x9FFF) || # most CJK chars here
          (i >= 0xF900 && i <= 0xFAFF))   # another "compatibility" range
        yield c
      end
    end
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
    raise "Can't find Chinese words for encoding: #{encoding}" unless SUPPORTED_ENCODINGS.include?(encoding)
    return enum_for(:chinese_words) if not block_given?
    self.scan(WORD_REGEXP.__value__) { |w| yield w }
  end

  # when calling this method, must pass a block to calculate the replacement
  def replace_chinese_words!
    self.gsub!(WORD_REGEXP.__value__) { |word| yield word }
  end
end

if __FILE__ == $0
  include Chinese
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
      puts "You must specify an input text file, or '-' to read from standard input."
      usage
    elsif not File.exists?(file)
      puts "The input file you specified, #{file}, doesn't exist."
      usage
    else
      File.open(file,'r',:encoding => 'utf-8') { |f| f.read }
    end
  end
  def usage
    puts "Usage: ruby chinese.rb <command> <input file>"
    puts "Commands:"
    puts "  wordfreq    -- print statistics on Chinese word frequencies in the given file"
    puts "  charfreq    -- print statistics on Chinese character frequencies in the file"
    puts "  transcribe  -- insert Pinyin after each Chinese word"
    puts "  simplified  -- convert traditional characters to simplified"
    puts "  traditional -- convert simplified characters to traditional"
    puts "  threeline   -- print Pinyin and English below each Chinese word"
    puts
    puts "A non-ambiguous prefix can be used in place of any command. For example, 'tra' can be used instead of 'traditional'."
    puts "Output will be printed to the console. You can redirect it to a file like this: >file_name_here.txt"
    exit
  end

  $commands = {
    'charfreq' => lambda {
      count = histogram(progress_counter(read_text_file.chinese_characters))
      total = count.values.reduce(0,&:+)
    
      cum = rank; rank = 0
      print_table(%w{Character Rank Frequency Cumulative},
                  [10, 8, 10, 10],
                  count.sort_by { |v| -v }.map { |k,v| pct = v.to_f/total; [k, rank += 1, pct, cum += pct] })
    },
    'wordfreq' => lambda {
      count = histogram(progress_counter(read_text_file.chinese_words))
      total = count.values.reduce(0,&:+)

      cum = 0; rank = 0
      print_table(%w{Word Rank Frequency Cumulative},
                  [8, 8, 10, 10],
                  count.sort_by { |k,v| -v }.map { |k,v| pct = v.to_f/total; [k, rank += 1, pct, cum += pct] })
    },
    'transcribe' => lambda {
      puts read_text_file.replace_chinese_words! { |word| CHARACTERS_TO_PINYIN.key?(word) ? "#{word} [#{PINYIN[word]}]" : word }
    },
    'simplified' => lambda {
      puts read_text_file.replace_chinese_words! { |word| TRADITIONAL_TO_SIMPLIFIED[word] || word }
    },
    'traditional' => lambda {
      puts read_text_file.replace_chinese_words! { |word| SIMPLIFIED_TO_TRADITIONAL[word] || word }
    },
    'threeline' => lambda {
      words = read_text_file.chinese_words
      line1,line2,line3 = "","",""
      words.each do |word|
        english,pinyin = CHARACTERS_TO_ENGLISH[word],CHARACTERS_TO_PINYIN[word]
        width = [word.length,english.length,pinyin.length].max
        if (width + line1.width >= 80)
          puts line1;  puts line2;  puts line3;
          line1.clear; line2.clear; line3.clear;
        end
        line1 << word.center(width) << " "
        line2 << pinyin.center(width) << " "
        line3 << english.center(width) << " "
      end
      unless line1.empty?
        puts line1; puts line2; puts line3
      end      
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

