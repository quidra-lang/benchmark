class DictionaryTrie
  Node = Struct.new(:children, :terminal) do
    def initialize
      super({}, false)
    end
  end
  attr_reader :root, :nodes, :words

  def initialize
    @root = Node.new
    @nodes, @words = 1, 0
  end

  def add(word)
    node = root
    word.each_char do |letter|
      unless node.children.key?(letter)
        node.children[letter] = Node.new
        @nodes += 1
      end
      node = node.children[letter]
    end
    return false if node.terminal
    node.terminal = true
    @words += 1
    true
  end

  def prefix(word)
    node = root
    word.each_char do |letter|
      node = node.children[letter]
      return unless node
    end
    node
  end

  def include?(word)
    node = prefix(word)
    node && node.terminal
  end

  def anagrams(rack)
    counts = Hash.new(0).merge(rack.chars.tally)
    result = []
    visit = lambda do |node, word|
      result << word if node.terminal
      node.children.keys.sort.each do |letter|
        tile = counts[letter] > 0 ? letter : '?'
        next unless counts[tile] > 0
        counts[tile] -= 1
        visit.call(node.children[letter], word + letter)
        counts[tile] += 1
      end
    end
    visit.call(root, '')
    result
  end
end
