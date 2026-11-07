require 'fileutils'

module TreeIO
  def self.real(value, places)
    text = format("%.#{places}f", value)
    text == '-0.' + '0' * places ? text[1..] : text
  end
  def self.symbols(mask, count)
    (0...count).map { |taxon| (mask & (1 << taxon)).zero? ? '.' : '*' }.join
  end
  def self.child_order(rooted, names)
    minimum, children = {}, {}
    rooted.order.reverse_each do |node|
      if node < rooted.tree.size
        minimum[node], children[node] = names[node], []
      else
        children[node] = rooted.children[node].sort_by { |child| minimum[child] }
        minimum[node] = minimum[children[node].first]
      end
    end
    children
  end
  def self.newick(tree, names, outgroup, lengths: false, support: nil)
    rooted = tree.rooted(outgroup)
    children = child_order(rooted, names)
    render = lambda do |node|
      text = if node < tree.size
               names[node].dup
             else
               '(' + children[node].map { |child| render.call(child) }.join(',') + ')'
             end
      text += support.fetch(rooted.masks[node], 0).to_s if support && node >= tree.size && node != rooted.root
      text += ':' + real(tree.adjacent[node][rooted.parents[node]], 5) if lengths && node != rooted.root
      text
    end
    render.call(rooted.root) + ';'
  end
  def self.cladogram(tree, names, outgroup, support)
    rooted = tree.rooted(outgroup)
    children = child_order(rooted, names)
    lines = ['*']
    descend = lambda do |node, prefix|
      children[node].each_with_index do |child, index|
        last = index == children[node].size - 1
        label = child < tree.size ? names[child] : "[#{support.fetch(rooted.masks[child], 0)}]"
        lines << prefix + (last ? '`-- ' : '|-- ') + label
        descend.call(child, prefix + (last ? '    ' : '|   '))
      end
    end
    descend.call(rooted.root, '')
    lines
  end
  def self.write_lines(filename, lines)
    FileUtils.mkdir_p('output')
    File.write(File.join('output', filename), lines.join("\n") + "\n")
  end
end
