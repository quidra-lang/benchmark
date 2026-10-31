paragraph =
  'Good software is written for people first and for machines second. ' \
  'A clear program explains its purpose through careful names, small functions and honest tests. ' \
  'When a team agrees on shared rules for internationalization, documentation and code review, ' \
  'every newcomer can read the code quickly, change it safely and ship new improvements ' \
  'with confidence instead of fear, week after week.'
width = 30
lines = []
line = []
letters = 0
paragraph.split(' ').each do |word|
  if !line.empty? && letters + line.length + word.length > width
    lines << line
    line = []
    letters = 0
  end
  line << word
  letters += word.length
end
lines << line
lines.each_with_index do |words, index|
  if index == lines.length - 1 || words.length == 1
    text = words.join(' ').ljust(width)
  else
    base, extra = (width - words.sum(&:length)).divmod(words.length - 1)
    text = words[0]
    words.drop(1).each_with_index do |word, gap|
      text += ' ' * (base + (gap < extra ? 1 : 0)) + word
    end
  end
  puts "|#{text}|"
end
