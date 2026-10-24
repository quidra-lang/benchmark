require_relative 'doc_builder'

module Printer
  def self.fits?(remaining, first, stack)
    return false if remaining < 0
    check, cursor = [first], stack.length - 1
    loop do
      if check.empty?
        return true if cursor < 0
        check << stack[cursor]
        cursor -= 1
      end
      indent, mode, doc = check.pop
      if doc.is_a?(String)
        remaining -= doc.length
      else
        case doc[:kind]
        when :if_break then remaining -= doc[mode == :break ? :broken : :flat].length
        when :line
          return true if mode == :break
          remaining -= 1
        when :softline then return true if mode == :break
        when :hardline then return true
        when :concat then doc[:parts].reverse_each { |part| check << [indent, mode, part] }
        when :group then check << [indent, doc[:forced] ? :break : mode, doc[:child]]
        when :nest, :align then check << [indent, mode, doc[:child]]
        end
      end
      return false if remaining < 0
    end
  end

  def self.layout(document, profile)
    lines, current, pending = [], +'', []
    width, column = profile[:width], profile[:comment_column]
    finalize = lambda do
      value = current.rstrip
      unless pending.empty?
        comment = pending.join(' ')
        if column > 0 && value.length < column - 1 && column - 1 + comment.length <= width
          value += ' ' * (column - 1 - value.length) + comment
        else
          value += ' ' + comment
        end
      end
      pending.clear
      lines << value
    end
    stack = [[0, :break, document]]
    until stack.empty?
      indent, mode, doc = stack.pop
      if doc.is_a?(String)
        current << doc
        next
      end
      case doc[:kind]
      when :if_break then current << doc[mode == :break ? :broken : :flat]
      when :line, :softline, :hardline
        if doc[:kind] == :hardline || mode == :break
          finalize.call
          current = ' ' * indent
        elsif doc[:kind] == :line
          current << ' '
        end
      when :suffix then pending << doc[:text]
      when :concat then doc[:parts].reverse_each { |part| stack << [indent, mode, part] }
      when :nest then stack << [indent + doc[:amount], mode, doc[:child]]
      when :align then stack << [current.length, mode, doc[:child]]
      when :group
        selected = if mode == :flat
                     :flat
                   elsif doc[:forced]
                     :forced
                   elsif fits?(width - current.length, [indent, :flat, doc[:child]], stack)
                     :flat
                   else
                     :break
                   end
        doc[:mode] = selected
        stack << [indent, selected == :flat ? :flat : :break, doc[:child]]
      end
    end
    finalize.call
    lines
  end
end
