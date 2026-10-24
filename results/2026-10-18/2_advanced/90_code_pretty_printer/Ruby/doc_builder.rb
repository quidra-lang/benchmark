module Docs
  LINE = {kind: :line}.freeze
  SOFTLINE = {kind: :softline}.freeze
  HARDLINE = {kind: :hardline}.freeze
  BREAK_PARENT = {kind: :break_parent}.freeze

  def cat(*entries)
    result = []
    append = lambda do |entry|
      if entry.is_a?(Array)
        entry.each { |part| append.call(part) }
      elsif entry && entry != ''
        if entry.is_a?(Hash) && entry[:kind] == :concat
          entry[:parts].each { |part| append.call(part) }
        elsif entry.is_a?(String) && result.last.is_a?(String)
          result[-1] = result.last + entry
        else
          result << entry
        end
      end
    end
    entries.each { |entry| append.call(entry) }
    return '' if result.empty?
    result.length == 1 ? result[0] : {kind: :concat, parts: result}
  end

  def group(child) = {kind: :group, child: child, forced: force_broken?(child)}
  def nest(amount, child) = {kind: :nest, amount: amount, child: child}
  def align(child) = {kind: :align, child: child}
  def suffix(value) = {kind: :suffix, text: value}
  def if_break(a, b) = {kind: :if_break, broken: a, flat: b}

  def force_broken?(doc)
    return false if doc.is_a?(String)
    return true if %i[hardline break_parent].include?(doc[:kind])
    children(doc).any? { |child| force_broken?(child) }
  end

  def children(doc)
    return [] if doc.is_a?(String)
    doc[:kind] == :concat ? doc[:parts] : (doc[:child] ? [doc[:child]] : [])
  end

  def groups(doc)
    return [] unless doc && !doc.is_a?(String)
    (doc[:kind] == :group ? [doc] : []) + children(doc).flat_map { |child| groups(child) }
  end
  module_function :cat, :group, :nest, :align, :suffix, :if_break, :force_broken?, :children, :groups
end
