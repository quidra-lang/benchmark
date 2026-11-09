class PikeVM
  attr_reader :steps

  def initialize(program, groups, flags, text)
    @program, @groups, @flags, @text = program, groups, flags, text
    @steps = 0
  end

  def add(list, marks, p, c, q)
    return if marks[p]
    marks[p] = true
    @steps += 1
    op, a, b = @program[p]
    case op
    when :jmp then add(list, marks, a, c, q)
    when :split
      add(list, marks, a, c, q)
      add(list, marks, b, c, q)
    when :save
      copy = c.dup
      copy[a] = q
      add(list, marks, p + 1, copy, q)
    when :assert
      add(list, marks, p + 1, c, q) if Charset.assert?(a, @text, q, @flags)
    else list << [p, c.dup]
    end
  end

  def search(start, full = false)
    found = nil
    list, marks, q = [], {}, start
    loop do
      add(list, marks, 0, Array.new(2 * @groups + 2), q) if !found && (!full || q == start)
      following, next_marks = [], {}
      list.each do |p, c|
        @steps += 1
        if @program[p][0] == :match
          if !full || q == @text.length
            found = c
            break
          end
        elsif Charset.consume?(@program[p], @text, q, @flags)
          add(following, next_marks, p + 1, c, q + 1)
        end
      end
      break if q == @text.length || (following.empty? && (found || full))
      list, marks = following, next_marks
      q += 1
    end
    found
  end
end
