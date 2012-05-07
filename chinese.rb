require 'set'

class String
  # note: in Unicode, CJK punctuation is 0x3000-0x303F

  # read all the Chinese words from CEDict into a big array
  DICTIONARY = begin
    data = File.open('cedict.utf8','r',:encoding => 'utf-8') { |f| f.readlines }
    data.reject!  { |line| line =~ /^#/ }
    data.map!     { |line| line.split(' ')[1] } # second field is simplified characters
    data.sort_by! { |word| -word.length }
  end

  SUPPORTED_ENCODINGS = [Encoding::UTF_8]

  # iterator for chinese characters
  def chinese_characters
    raise "Can't find Chinese characters for encoding: #{encoding}" unless SUPPORTED_ENCODINGS.include?(encoding)
    return enum_for(:characters) if not block_given?
    codes = codepoints
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
  #   which is a Chinese words in our dictionary
  # in some cases this splits words incorrectly, but usually the accuracy is >99%
  # we could achieve higher accuracy by:
  # - using a more complete dictionary (but CEDict is the best one I know right now)
  # - using something like a hidden Markov model to find the most likely points to split each sentence
  #   (it would have to consider an entire sentence at a time)
  #   (to do this, I would need a training corpus. I think the Longman Chinese Corpus would do the trick,
  #      since it has all the words pre-split. But I don't know if it was split manually or by computer.
  #      If by computer, it might not be totally accurate itself and thus a poor candidate for training.)
  WORD_REGEXP = Regexp.union(*DICTIONARY)
  def chinese_words
    raise "Can't find Chinese words for encoding: #{encoding}" unless SUPPORTED_ENCODINGS.include?(encoding)
    return enum_for(:chinese_words) if not block_given?
    self.scan(WORD_REGEXP) { |w| yield w }
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
        str = unless c.is_a?(Float)
          c.to_s
        else
          "%0.#{w}f" % c
        end
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

  case action = ARGV.shift
  when 'charfreq', 'cf'
    file = ARGV.shift
    text = File.open(file,'r',:encoding => 'utf-8') { |f| f.read }
    count = histogram(progress_counter(text.chinese_characters))
    total = count.values.reduce(0,&:+)
    
    cum = rank; rank = 0
    print_table(%w{Character Rank Frequency Cumulative},
                [10, 8, 10, 10],
                count.sort_by { |v| -v }.map { |k,v| pct = v.to_f/total; [k, rank += 1, pct, cum += pct] }

  when 'wordfreq', 'wf'
    file = ARGV.shift
    text = File.open(file,'r',:encoding => 'utf-8') { |f| f.read }
    count = histogram(progress_counter(text.chinese_words))
    total = count.values.reduce(0,&:+)

    cum = 0; rank = 0
    print_table(%w{Word Rank Frequency Cumulative},
                [8, 8, 10, 10],
                count.sort_by { |k,v| -v }.map { |k,v| pct = v.to_f/total; [k, rank += 1, pct, cum += pct] })
  else
    puts "Unknown command: #{action}"
    puts "Usage:" 
    puts "ruby chinese.rb charfreq <input file>"
    puts "ruby chinese.rb wordfreq <input file>"
  end
end
