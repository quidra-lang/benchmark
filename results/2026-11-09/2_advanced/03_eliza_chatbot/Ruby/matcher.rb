module Matcher
  def self.wildcard?(element)
    element == '*' || element == '#' || element.start_with?('@')
  end

  def self.match(pattern, words, groups)
    memo = {}
    search = lambda do |element_index, word_index|
      key = [element_index, word_index]
      return memo[key] if memo.key?(key)
      if element_index == pattern.length
        return memo[key] = word_index == words.length ? [] : nil
      end

      element = pattern[element_index]
      if element == '*'
        (word_index..words.length).each do |ending|
          tail = search.call(element_index + 1, ending)
          return memo[key] = [words[word_index...ending]] + tail unless tail.nil?
        end
      elsif word_index < words.length
        accepts = if element == '#'
                    true
                  elsif element.start_with?('@')
                    groups[element[1..]]&.dig(:members)&.include?(words[word_index])
                  else
                    element == words[word_index]
                  end
        if accepts
          tail = search.call(element_index + 1, word_index + 1)
          unless tail.nil?
            return memo[key] = wildcard?(element) ? [[words[word_index]]] + tail : tail
          end
        end
      end
      memo[key] = nil
    end
    search.call(0, 0)
  end

  def self.element_covers?(left, right, groups)
    return right != '*' if left == '#'
    return left == right unless left.start_with?('@')

    members = groups.fetch(left[1..])[:members]
    if right.start_with?('@')
      groups.fetch(right[1..])[:members].subset?(members)
    else
      members.include?(right)
    end
  end

  def self.covers?(earlier, later, groups)
    memo = {}
    search = lambda do |left, right|
      key = [left, right]
      return memo[key] if memo.key?(key)
      return memo[key] = (right == later.length) if left == earlier.length

      if earlier[left] == '*'
        memo[key] = (right..later.length).any? { |ending| search.call(left + 1, ending) }
      else
        memo[key] = right < later.length && element_covers?(earlier[left], later[right], groups) &&
                    search.call(left + 1, right + 1)
      end
    end
    search.call(0, 0)
  end
end
