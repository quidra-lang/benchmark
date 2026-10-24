words = %w[listen stone night silent notes apple thing enlist earth onset heart tones]
groups = words.group_by { |word| word.chars.sort.join }
groups.each_value { |group| puts group.join(' ') }
