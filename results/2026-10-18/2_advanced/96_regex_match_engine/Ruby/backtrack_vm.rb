class BacktrackVM
  class TooManySteps < StandardError; end
  attr_reader :steps

  def initialize(program, groups, flags, text)
    @program, @groups, @flags, @text = program, groups, flags, text
    @steps = 0
  end

  def search(start, full = false)
    @full = full
    (full ? [0] : (start..@text.length)).each do |q|
      result = execute(0, q, Array.new(2 * @groups + 2), false)
      return result[0] if result
    end
    nil
  end

  def execute(initial_p, initial_q, captures, partial)
    stack = [[initial_p, initial_q, captures.dup, {}]]
    until stack.empty?
      p, q, c, visited = stack.pop
      loop do
        @steps += 1
        raise TooManySteps if @steps > 200_000
        op, a, b = @program[p]
        case op
        when :char, :any, :class
          break unless Charset.consume?(@program[p], @text, q, @flags)
          p += 1
          q += 1
          visited = {}
        when :split
          break if visited[p]
          visited[p] = true
          stack << [b, q, c.dup, visited.dup]
          p = a
        when :jmp then p = a
        when :save
          c[a] = q
          p += 1
        when :assert
          break unless Charset.assert?(a, @text, q, @flags)
          p += 1
        when :backref
          first, last = c[2 * a, 2]
          break unless first && last && first <= last
          length = last - first
          break unless q + length <= @text.length && (0...length).all? { |j| Charset.equal?(@text.getbyte(q + j), @text.getbyte(first + j), @flags) }
          q += length
          p += 1
          visited = {} if length.positive?
        when :look
          result = execute(p + 1, q, c, true)
          if a == :NOT
            break if result
          else
            break unless result
            c = result[0]
            if a == :ATOMIC
              visited = {} if result[1] > q
              q = result[1]
            end
          end
          p = b
        when :match
          return [c, q] if partial || !@full || q == @text.length
          break
        end
      end
    end
    nil
  end
end
