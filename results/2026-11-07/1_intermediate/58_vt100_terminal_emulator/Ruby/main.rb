class Terminal
  FLAGS = %w[bold dim italic underline blink reverse hidden strike]
  INITIAL = {'IRM'=>false, 'LNM'=>false, 'DECCKM'=>false, 'DECSCNM'=>false,
             'DECOM'=>false, 'DECAWM'=>true, 'DECTCEM'=>true, 'DECKPAM'=>false, 'BRACKETED'=>false}
  ANSI = {4=>'IRM', 20=>'LNM'}
  DEC = {1=>'DECCKM', 5=>'DECSCNM', 6=>'DECOM', 7=>'DECAWM', 25=>'DECTCEM', 2004=>'BRACKETED'}
  DEFAULT = [0, 'default', 'default'].freeze

  def initialize(width, height)
    @w, @h = width, height
    @bytes = @printed = @sequences = @bell = @replies = @dumps = 0
    @ignored = {'unsupported'=>0, 'malformed'=>0, 'canceled'=>0, 'invalid'=>0}
    reset
  end

  def blank_row
    Array.new(@w) { [' ', DEFAULT] }
  end

  def blank_screen
    Array.new(@h) { blank_row }
  end

  def reset
    @screens = [blank_screen, blank_screen]
    @screen = 0
    @row = @col = @top = 1
    @bottom = @h
    @pending = false
    @attrs = DEFAULT.dup
    @g0 = @g1 = @gl = 0
    @modes = INITIAL.dup
    @shape = 1
    @tabs = (9..@w).step(8).to_a
    @saves = [nil, nil]
    @scrollback = []
    @title = @last = nil
    parser_start('ground')
  end

  def parser_start(state)
    @parser = state
    @private = @params = @intermediate = @osc = ''
  end

  def grid
    @screens[@screen]
  end

  def row_text(cells)
    cells.map(&:first).join.rstrip
  end

  def scroll(up, count = 1)
    count.times do
      if up
        removed = grid.delete_at(@top - 1)
        grid.insert(@bottom - 1, blank_row)
        if @screen == 0 && @top == 1
          @scrollback << row_text(removed)
          @scrollback.shift if @scrollback.size > 100
        end
      else
        grid.delete_at(@bottom - 1)
        grid.insert(@top - 1, blank_row)
      end
    end
  end

  def line_feed
    if @row == @bottom
      scroll(true)
    elsif @row < @h
      @row += 1
    end
  end

  def reverse_feed
    if @row == @top
      scroll(false)
    elsif @row > 1
      @row -= 1
    end
  end

  def tab(reverse = false)
    @col = if reverse
             @tabs.select { |stop| stop < @col }.max || 1
           else
             @tabs.select { |stop| stop > @col }.min || @w
           end
  end

  def address(value)
    @modes['DECOM'] ? [@top + value - 1, @bottom].min : [value, @h].min
  end

  def home
    @row, @col = address(1), 1
  end

  def save
    @saves[@screen] = [@row, @col, @attrs.dup, @modes['DECOM'], @g0, @g1, @gl]
  end

  def restore
    saved = @saves[@screen]
    if saved
      @row, @col, attrs, @modes['DECOM'], @g0, @g1, @gl = saved
      @attrs = attrs.dup
    else
      @row = @col = 1
      @attrs = DEFAULT.dup
      @modes['DECOM'] = false
      @g0 = @g1 = @gl = 0
    end
    @pending = false
  end

  def write(char)
    @printed += 1
    @last = char
    if @pending
      @pending = false
      @col = 1
      line_feed
    end
    cells = grid[@row - 1]
    if @modes['IRM']
      cells.insert(@col - 1, [' ', DEFAULT])
      cells.pop
    end
    cells[@col - 1] = [char, @attrs.dup]
    if @col < @w
      @col += 1
    elsif @modes['DECAWM']
      @pending = true
    end
  end

  def print_char(char)
    if (@gl == 0 ? @g0 : @g1) == 1
      char = {'`'=>'*', 'a'=>'#', 'j'=>'+', 'k'=>'+', 'l'=>'+', 'm'=>'+', 'n'=>'+',
              't'=>'+', 'u'=>'+', 'v'=>'+', 'w'=>'+', 'q'=>'-', 'x'=>'|', '~'=>'o'}.fetch(char, char)
    end
    write(char)
  end

  def control(code)
    @pending = false if [8, 9, 10, 11, 12, 13].include?(code)
    case code
    when 7 then @bell += 1
    when 8 then @col = [@col - 1, 1].max
    when 9 then tab
    when 10, 11, 12
      line_feed
      @col = 1 if @modes['LNM']
    when 13 then @col = 1
    when 14 then @gl = 1
    when 15 then @gl = 0
    end
  end

  def escape(key)
    known = ['7', '8', 'D', 'E', 'M', 'H', 'c', '=', '>', '\\', '(0', '(B', ')0', ')B', '#8']
    return 'unsupported' unless known.include?(key)
    @pending = false if ['D', 'E', 'M', 'c', '#8'].include?(key)
    case key
    when '7' then save
    when '8' then restore
    when 'D' then line_feed
    when 'E' then @col = 1; line_feed
    when 'M' then reverse_feed
    when 'H' then @tabs = (@tabs + [@col]).uniq.sort
    when 'c' then reset
    when '=' then @modes['DECKPAM'] = true
    when '>' then @modes['DECKPAM'] = false
    when '(0' then @g0 = 1
    when '(B' then @g0 = 0
    when ')0' then @g1 = 1
    when ')B' then @g1 = 0
    when '#8'
      @screens[@screen] = Array.new(@h) { Array.new(@w) { ['E', DEFAULT] } }
      @top, @bottom = 1, @h
      @modes['DECOM'] = false
      @row = @col = 1
    end
    nil
  end

  def palette(number)
    colors = %w[black red green yellow blue magenta cyan white]
    return colors[number] if number < 8
    return 'bright-' + colors[number - 8] if number < 16
    number.to_s
  end

  def sgr(params)
    params = [0] if params.empty?
    attrs = @attrs.dup
    on = {1=>0, 2=>1, 3=>2, 4=>3, 5=>4, 7=>5, 8=>6, 9=>7}
    off = {23=>2, 24=>3, 25=>4, 27=>5, 28=>6, 29=>7}
    i = 0
    while i < params.size
      value = params[i]
      if value == 0
        attrs = DEFAULT.dup
      elsif on.key?(value)
        attrs[0] |= 1 << on[value]
      elsif value == 22
        attrs[0] &= ~3
      elsif off.key?(value)
        attrs[0] &= ~(1 << off[value])
      elsif (30..37).cover?(value)
        attrs[1] = palette(value - 30)
      elsif (90..97).cover?(value)
        attrs[1] = palette(value - 82)
      elsif (40..47).cover?(value)
        attrs[2] = palette(value - 40)
      elsif (100..107).cover?(value)
        attrs[2] = palette(value - 92)
      elsif value == 39 || value == 49
        attrs[value == 39 ? 1 : 2] = 'default'
      elsif value == 38 || value == 48
        color = nil
        if params[i + 1] == 5 && i + 2 < params.size && params[i + 2] <= 255
          color = palette(params[i + 2])
          i += 2
        elsif params[i + 1] == 2 && i + 4 < params.size && params[i + 2, 3].all? { |v| v <= 255 }
          color = format('#%02x%02x%02x', *params[i + 2, 3])
          i += 4
        end
        return 'unsupported' unless color
        attrs[value == 38 ? 1 : 2] = color
      else
        return 'unsupported'
      end
      i += 1
    end
    @attrs = attrs
    nil
  end

  def modes(key, params)
    params = [0] if params.empty?
    private_mode = key.start_with?('?')
    allowed = private_mode ? [1, 5, 6, 7, 25, 47, 1047, 1048, 1049, 2004] : [4, 20]
    return 'unsupported' unless params.all? { |p| allowed.include?(p) }
    setting = key.end_with?('h')
    params.each do |p|
      if !private_mode
        @modes[ANSI[p]] = setting
      elsif p == 6
        @pending = false
        @modes['DECOM'] = setting
        home
      elsif [47, 1047, 1049].include?(p)
        @pending = false
        target = setting ? 1 : 0
        next if @screen == target
        save if setting && p == 1049
        @screens[1] = blank_screen if !setting && p == 1047
        @screen = target
        @screens[1] = blank_screen if setting && p == 1049
        restore if !setting && p == 1049
      elsif p == 1048
        setting ? save : restore
      else
        @pending = false if p == 7 && !setting
        @modes[DEC[p]] = setting
      end
    end
    nil
  end

  def erase(row, first, last)
    (first..last).each { |column| grid[row - 1][column - 1] = [' ', DEFAULT] }
  end

  def reply(text)
    @replies += 1
    puts 'REPLY ' + text
  end

  def csi(final)
    fields = @params.empty? ? [] : @params.split(';', -1)
    return 'invalid' if fields.size > 16
    params = fields.map do |field|
      value = 0
      field.each_byte { |byte| value = [9999, value * 10 + byte - 48].min }
      value
    end
    p1, p2 = params[0] || 0, params[1] || 0
    n = [p1, 1].max
    key = @private + @intermediate + final
    known = ['A','B','e','C','a','D','E','F','G','`','H','f','d','I','Z','J','K','X','@','P','L','M','S','T','b','g','m','h','l','?h','?l',' q','r','s','u','!p','n','?n','c','>c','t','$p','?$p']
    return 'unsupported' unless known.include?(key)
    bad = (key == 'J' && p1 > 3) || (key == 'K' && p1 > 2) ||
          (key == 'g' && ![0, 3].include?(p1)) || (key == ' q' && p1 > 6) ||
          (key == 'n' && ![5, 6].include?(p1)) || (key == '?n' && p1 != 6) ||
          (['c', '>c'].include?(key) && p1 != 0) || (key == 't' && p1 != 18)
    return 'unsupported' if bad
    return sgr(params) if key == 'm'
    return modes(key, params) if ['h','l','?h','?l'].include?(key)
    if key == 'r'
      top = p1 == 0 ? 1 : p1
      bottom = [p2 == 0 ? @h : p2, @h].min
      return 'invalid' if top >= bottom
      @pending = false
      @top, @bottom = top, bottom
      home
      return nil
    end
    @pending = false if ['A','B','C','D','E','F','G','H','I','J','K','L','M','P','S','T','X','Z','`','a','d','e','f','@','!p'].include?(key)
    case key
    when 'A','F'
      @row = [@row - n, @row >= @top ? @top : 1].max
      @col = 1 if key == 'F'
    when 'B','e','E'
      @row = [@row + n, @row <= @bottom ? @bottom : @h].min
      @col = 1 if key == 'E'
    when 'C','a' then @col = [@col + n, @w].min
    when 'D' then @col = [@col - n, 1].max
    when 'G','`' then @col = [n, @w].min
    when 'H','f' then @row, @col = address(n), [[p2, 1].max, @w].min
    when 'd' then @row = address(n)
    when 'I','Z' then n.times { tab(key == 'Z') }
    when 'J'
      if p1 == 3
        @scrollback.clear
      else
        @h.times do |r|
          (1..@w).each do |c|
            position = r * @w + c
            cursor = (@row - 1) * @w + @col
            erase(r + 1, c, c) if p1 == 2 || (p1 == 0 && position >= cursor) || (p1 == 1 && position <= cursor)
          end
        end
      end
    when 'K' then erase(@row, p1 == 0 ? @col : 1, p1 == 1 ? @col : @w)
    when 'X' then erase(@row, @col, [@col + n - 1, @w].min)
    when '@','P'
      cells = grid[@row - 1]
      k = [n, @w - @col + 1].min
      if key == '@'
        cells.insert(@col - 1, *Array.new(k) { [' ', DEFAULT] })
        cells.slice!(@w..-1)
      else
        cells.slice!(@col - 1, k)
        k.times { cells << [' ', DEFAULT] }
      end
    when 'L','M'
      if @row.between?(@top, @bottom)
        k = [n, @bottom - @row + 1].min
        k.times do
          if key == 'L'
            grid.delete_at(@bottom - 1)
            grid.insert(@row - 1, blank_row)
          else
            grid.delete_at(@row - 1)
            grid.insert(@bottom - 1, blank_row)
          end
        end
        @col = 1
      end
    when 'S','T' then scroll(key == 'S', [n, @bottom - @top + 1].min)
    when 'b' then n.times { write(@last) } unless @last.nil?
    when 'g' then p1 == 3 ? @tabs.clear : @tabs.delete(@col)
    when ' q' then @shape = n
    when 's' then save
    when 'u' then restore
    when '!p'
      %w[IRM DECCKM DECOM DECAWM DECTCEM DECKPAM].each { |mode| @modes[mode] = INITIAL[mode] }
      @top, @bottom = 1, @h
      @attrs = DEFAULT.dup
      @g0 = @g1 = @gl = 0
      @saves[@screen] = nil
    when 'n'
      r = @modes['DECOM'] ? [@row - @top + 1, 1].max : @row
      reply(p1 == 5 ? '^[[0n' : "^[[#{r};#{@col}R")
    when '?n'
      r = @modes['DECOM'] ? [@row - @top + 1, 1].max : @row
      reply("^[[?#{r};#{@col};1R")
    when 'c' then reply('^[[?1;2c')
    when '>c' then reply('^[[>0;95;0c')
    when 't' then reply("^[[8;#{@h};#{@w}t")
    when '$p','?$p'
      mode = key == '$p' ? ANSI[p1] : DEC[p1]
      status = mode ? (@modes[mode] ? 1 : 2) : 0
      status = @screen == 1 ? 1 : 2 if key == '?$p' && [47, 1047, 1049].include?(p1)
      reply("^[[#{key == '?$p' ? '?' : ''}#{p1};#{status}$y")
    end
    nil
  end

  def finish_sequence(reason)
    if reason
      @ignored[reason] += 1
    else
      @sequences += 1
    end
  end

  def execute_osc
    if @osc.start_with?('0;', '2;')
      @title = @osc[2..]
      finish_sequence(nil)
    else
      finish_sequence('unsupported')
    end
  end

  def byte(code)
    @bytes += 1
    if code == 27
      if @parser == 'osc'
        execute_osc
      elsif @parser != 'ground'
        @ignored['canceled'] += 1
      end
      parser_start('escape')
      return
    end
    if code == 24 || code == 26
      if @parser != 'ground'
        @ignored['canceled'] += 1
        @parser = 'ground'
      end
      return
    end
    if code < 32
      if @parser == 'osc'
        if code == 7
          execute_osc
          @parser = 'ground'
        end
      else
        control(code)
      end
      return
    end
    char = code.chr
    intermediate = code.between?(32, 47)
    final = code >= 64
    case @parser
    when 'ground' then print_char(char)
    when 'escape'
      if intermediate
        @intermediate += char
        @parser = 'escape intermediate'
      elsif char == '['
        @parser = 'entry'
      elsif char == ']'
        @parser = 'osc'
      else
        finish_sequence(escape(@intermediate + char))
        @parser = 'ground'
      end
    when 'escape intermediate'
      if intermediate
        @intermediate += char
      else
        finish_sequence(escape(@intermediate + char))
        @parser = 'ground'
      end
    when 'entry','param'
      if @parser == 'entry' && code.between?(60, 63)
        @private = char
        @parser = 'param'
      elsif code.between?(48, 57) || char == ';'
        @params += char
        @parser = 'param'
      elsif intermediate
        @intermediate += char
        @parser = 'csi intermediate'
      elsif final
        finish_sequence(csi(char))
        @parser = 'ground'
      else
        @parser = 'ignore'
      end
    when 'csi intermediate'
      if intermediate
        @intermediate += char
      elsif final
        finish_sequence(csi(char))
        @parser = 'ground'
      else
        @parser = 'ignore'
      end
    when 'ignore'
      if final
        @ignored['malformed'] += 1
        @parser = 'ground'
      end
    when 'osc' then @osc += char
    end
  end

  def dump(label)
    puts "#{label} #{@screen == 0 ? 'main' : 'alt'} cursor #{@row},#{@col} scrollback #{@scrollback.size}#{@pending ? ' pending' : ''}"
    grid.each { |cells| puts '|' + row_text(cells) }
  end

  def key(name)
    arrows = {'UP'=>'A','DOWN'=>'B','RIGHT'=>'C','LEFT'=>'D','HOME'=>'H','END'=>'F'}
    fixed = {'INSERT'=>'^[[2~','DELETE'=>'^[[3~','PAGEUP'=>'^[[5~','PAGEDOWN'=>'^[[6~',
             'F1'=>'^[OP','F2'=>'^[OQ','F3'=>'^[OR','F4'=>'^[OS','F5'=>'^[[15~','F6'=>'^[[17~',
             'F7'=>'^[[18~','F8'=>'^[[19~','F9'=>'^[[20~','F10'=>'^[[21~','F11'=>'^[[23~','F12'=>'^[[24~',
             'TAB'=>'^I','BACKSPACE'=>'^?','ESCAPE'=>'^['}
    enter = @modes['LNM'] ? '^M^J' : '^M'
    text = if arrows.key?(name)
             (@modes['DECCKM'] ? '^[O' : '^[[') + arrows[name]
           elsif name == 'ENTER'
             enter
           elsif name == 'KPENTER'
             @modes['DECKPAM'] ? '^[OM' : enter
           elsif name.match?(/\AKP\d\z/)
             @modes['DECKPAM'] ? '^[O' + (112 + name[2].to_i).chr : name[2]
           else fixed[name]
           end
    puts "KEY #{name} #{text}"
  end

  def finish
    @ignored['canceled'] += 1 if @parser != 'ground'
    dump('FINAL')
    puts @title.nil? ? 'TITLE none' : "TITLE \"#{@title}\""
    modes = INITIAL.filter_map { |name, initial| "#{name}=#{@modes[name] ? 'on' : 'off'}" if @modes[name] != initial }
    modes << 'G0=graphics' if @g0 == 1
    modes << 'G1=graphics' if @g1 == 1
    modes << 'GL=G1' if @gl == 1
    modes << "CURSOR=#{@shape}" if @shape != 1
    puts 'MODES ' + (modes.empty? ? 'default' : modes.join(' '))
    puts "REGION #{@top}-#{@bottom}"
    puts 'TABS ' + (@tabs.empty? ? 'none' : @tabs.sort.join(','))
    puts "SCROLLBACK #{@scrollback.size}"
    @scrollback.last(5).each { |line| puts '|' + line }
    runs = []
    grid.each_with_index do |cells, r|
      c = 0
      while c < @w
        attrs = cells[c][1]
        last = c
        last += 1 while last + 1 < @w && cells[last + 1][1] == attrs
        if attrs != DEFAULT
          names = FLAGS.each_with_index.filter_map { |name, i| name if attrs[0] & (1 << i) != 0 }
          names << "fg=#{attrs[1]}" if attrs[1] != 'default'
          names << "bg=#{attrs[2]}" if attrs[2] != 'default'
          runs << "row #{r + 1} col #{c + 1}-#{last + 1} #{names.join(' ')}"
        end
        c = last + 1
      end
    end
    puts "ATTRS #{runs.size}"
    puts runs
    puts "BELL #{@bell}", "REPLIES #{@replies}", "STATS bytes=#{@bytes} printed=#{@printed} sequences=#{@sequences}"
    puts "IGNORED #{@ignored.values.sum} " + @ignored.map { |name, value| "#{name}=#{value}" }.join(' ')
  end

  def line(text)
    if text == '%%END'
      finish
    elsif text == '%%DUMP'
      @dumps += 1
      dump("DUMP #{@dumps}")
    elsif text.start_with?('%%KEY ')
      key(text[6..])
    elsif text.start_with?('%%PASTE ')
      pasted = text[8..].gsub('^', '^^')
      pasted = '^[[200~' + pasted + '^[[201~' if @modes['BRACKETED']
      puts 'PASTE ' + pasted
    else
      codes = {'@'=>0,'G'=>7,'H'=>8,'I'=>9,'J'=>10,'K'=>11,'L'=>12,'M'=>13,'N'=>14,'O'=>15,'X'=>24,'Z'=>26,'['=>27,'^'=>94}
      i = 0
      while i < text.size
        if text[i] == '^'
          byte(codes[text[i + 1]])
          i += 2
        else
          byte(text.getbyte(i))
          i += 1
        end
      end
    end
  end
end

width, height = STDIN.gets.split.map(&:to_i)
terminal = Terminal.new(width, height)
STDIN.each_line { |line| terminal.line(line.chomp) }
