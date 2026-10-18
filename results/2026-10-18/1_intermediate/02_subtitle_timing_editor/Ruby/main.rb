class Invalid < StandardError
end

class Editor
  ARITIES = {
    "LIST" => [0], "VALIDATE" => [0], "SEARCH" => [1], "AT" => [1],
    "GAPS" => [1], "STATS" => [0], "PRINT" => [0], "TOVTT" => [0],
    "TOASS" => [0], "FRAMES" => [1], "SHIFT" => [1], "SHIFTFROM" => [2],
    "SCALE" => [2], "SYNC" => [4], "SNAP" => [1], "FIXOVERLAP" => [1],
    "EXTEND" => [1], "TIME" => [3], "SORT" => [0], "RENUMBER" => [0],
    "MERGE" => [1], "SPLIT" => [1], "INSERT" => [4], "DELETE" => [1, 2],
    "TEXT" => [2], "BALANCE" => [0], "STRIP" => [0], "CLEANHI" => [0],
    "REPLACE" => [1], "UNDO" => [0]
  }.freeze
  MODIFYING = %w[SHIFT SHIFTFROM SCALE SYNC SNAP FIXOVERLAP EXTEND TIME SORT
                 RENUMBER MERGE SPLIT INSERT DELETE TEXT BALANCE STRIP CLEANHI REPLACE].freeze
  FORMATS = %w[<i> </i> <b> </b> <u> </u>].freeze

  def initialize
    @cues = []
    @history = []
  end

  def bad
    raise Invalid, "bad arguments"
  end

  def integer(value, minimum = 0, maximum = 999_999_999)
    bad unless value.match?(/\A\d{1,9}\z/)
    result = value.to_i
    bad unless result.between?(minimum, maximum)
    result
  end

  def signed(value)
    bad unless value.match?(/\A-?\d{1,9}\z/)
    value.to_i
  end

  def parse_time(value)
    bad unless value.match?(/\A\d{2}:[0-5]\d:[0-5]\d,\d{3}\z/)
    value[0, 2].to_i * 3_600_000 + value[3, 2].to_i * 60_000 +
      value[6, 2].to_i * 1000 + value[9, 3].to_i
  end

  def fps(value)
    parts = value.split("/", -1)
    bad if parts.length > 2
    [integer(parts[0], 1, 100_000), parts.length == 2 ? integer(parts[1], 1, 100_000) : 1]
  end

  def text_lines(value)
    parts = value.split("|", -1)
    bad if parts.empty? || parts.any?(&:empty?)
    parts
  end

  def rounded(a, b)
    if b.negative?
      a = -a
      b = -b
    end
    (2 * a + b).div(2 * b)
  end

  def srt(time)
    format("%02d:%02d:%02d,%03d", time.div(3_600_000), time.div(60_000) % 60,
           time.div(1000) % 60, time % 1000)
  end

  def ass(time)
    c = (time + 5).div(10)
    format("%d:%02d:%02d.%02d", c.div(360_000), c.div(6000) % 60, c.div(100) % 60, c % 100)
  end

  def decimal(value)
    format("%d.%02d", value.div(100), value % 100)
  end

  def chars(cue)
    cue[:text].sum(&:length)
  end

  def dialogue?(cue)
    cue[:text].any? { |line| line.start_with?("- ") }
  end

  def words(lines)
    lines.join(" ").split(" ")
  end

  def wrap(lines, width)
    result = []
    words(lines).each do |word|
      if !result.empty? && result[-1].length + 1 + word.length <= width
        result[-1] += " " + word
      else
        result << word
      end
    end
    result
  end

  def markup(line)
    result = []
    p = 0
    while p < line.length
      tag = FORMATS.find { |item| line[p, item.length] == item }
      if tag
        result << { kind: :format, text: tag, digit: 0 }
        p += tag.length
        next
      end
      font = nil
      if line[p, 7] == "</font>"
        font = "</font>"
      elsif line[p, 5] == "<font" && [" ", ">"].include?(line[p + 5])
        ending = line.index(">", p + 5)
        font = line[p..ending] if ending
      end
      if font
        result << { kind: :font, text: font, digit: 0 }
        p += font.length
        next
      end
      position = /\A\{\\an([1-9])\}/.match(line[p..])
      if position
        result << { kind: :position, text: position[0], digit: position[1].to_i }
        p += position[0].length
      else
        result << { kind: :char, text: line[p], digit: 0 }
        p += 1
      end
    end
    result
  end

  def listing(cue, position)
    "#{position} #{cue[:index]} #{srt(cue[:start])} #{srt(cue[:end])} " + cue[:text].join("|")
  end

  def load(lines)
    blocks = []
    current = []
    (lines + [""]).each do |line|
      if !line.empty?
        current << line
      elsif !current.empty?
        blocks << current
        current = []
      end
    end
    output = []
    blocks.each_with_index do |block, i|
      reason = nil
      if !block[0].match?(/\A\d{1,6}\z/)
        reason = "index"
      elsif block.length < 2 ||
            !block[1].match?(/\A\d{2}:[0-5]\d:[0-5]\d,\d{3} --> \d{2}:[0-5]\d:[0-5]\d,\d{3}\z/)
        reason = "time"
      elsif block.length < 3
        reason = "no text"
      end
      if reason
        output << "BAD CUE #{i + 1}: #{reason}"
      else
        @cues << {
          index: block[0].to_i, start: parse_time(block[1][0, 12]),
          end: parse_time(block[1][17, 12]), text: block[2..]
        }
      end
    end
    output << "LOAD cues=#{@cues.length} bad=#{blocks.length - @cues.length}"
    output
  end

  def execute(line)
    name = line.split(" ", 2)[0]
    raise Invalid, "unknown command" unless ARITIES.key?(name)

    fixed = { "SEARCH" => 0, "INSERT" => 3, "TEXT" => 1, "REPLACE" => 0 }
    if fixed.key?(name)
      bad if line.length <= name.length
      args = []
      p = name.length + 1
      fixed[name].times do
        following = line.index(" ", p)
        bad unless following
        args << line[p...following]
        p = following + 1
      end
      args << line[p..]
    else
      args = line.split(" ")[1..]
    end
    bad unless ARITIES[name].include?(args.length)

    values = []
    texts = []
    rate = [1, 1]
    old = ""
    replacement = ""
    positions = []
    position = lambda do |value|
      p = integer(value, 1)
      positions << p
      p
    end
    case name
    when "AT"
      values << parse_time(args[0])
    when "GAPS", "FIXOVERLAP", "MERGE"
      values << integer(args[0], 0, 60_000)
    when "EXTEND"
      values << integer(args[0], 1, 60_000)
    when "SPLIT"
      values << integer(args[0], 10, 80)
    when "SHIFT"
      values << signed(args[0])
    when "SHIFTFROM"
      values = [position.call(args[0]), signed(args[1])]
    when "SCALE"
      values = args.map { |arg| integer(arg, 1, 100_000) }
    when "SYNC"
      values = [position.call(args[0]), parse_time(args[1]), position.call(args[2]), parse_time(args[3])]
    when "TIME", "INSERT"
      values = [position.call(args[0]), parse_time(args[1]), parse_time(args[2])]
      texts = text_lines(args[3]) if name == "INSERT"
    when "DELETE"
      values = args.map { |arg| position.call(arg) }
      bad if values.length == 2 && values[1] < values[0]
    when "TEXT"
      values = [position.call(args[0])]
      texts = text_lines(args[1])
    when "FRAMES", "SNAP"
      rate = fps(args[0])
    when "REPLACE"
      parts = args[0].split("|", -1)
      bad unless parts.length == 2 && parts.none?(&:empty?)
      old, replacement = parts
    end
    positions.each do |p|
      limit = @cues.length + (name == "INSERT" ? 1 : 0)
      raise Invalid, "no cue #{p}" if p > limit
    end
    if name == "SYNC" && @cues[values[0] - 1][:start] == @cues[values[2] - 1][:start]
      raise Invalid, "sync points coincide"
    end
    if name == "UNDO"
      record = @history.pop
      raise Invalid, "nothing to undo" unless record
      @cues = record[:cues]
      return ["UNDO command=#{record[:name]}"]
    end
    if MODIFYING.include?(name)
      snapshot = @cues.map { |cue| cue.merge(text: cue[:text].dup) }
      @history << { name: name, cues: snapshot }
    end
    process(name, args, values, texts, rate, old, replacement)
  end

  def process(name, args, v, texts, rate, old, replacement)
    output = []
    n = @cues.length
    case name
    when "LIST", "AT"
      @cues.each_with_index do |cue, i|
        if name == "LIST" || (cue[:start] <= v[0] && v[0] < cue[:end])
          output << listing(cue, i + 1)
        end
      end
      output << "AT active=#{output.length}" if name == "AT"
    when "VALIDATE"
      @cues.each_with_index do |cue, i|
        p = i + 1
        prefix = "cue #{p}: "
        d = cue[:end] - cue[:start]
        output << prefix + "index #{cue[:index]} (expected #{p})" if cue[:index] != p
        output << prefix + "end not after start" if d <= 0
        if i.positive? && cue[:start] < @cues[i - 1][:end]
          output << prefix + "overlaps previous by #{@cues[i - 1][:end] - cue[:start]} ms"
        end
        if d.between?(1, 699)
          output << prefix + "too short (#{d} ms)"
        elsif d > 7000
          output << prefix + "too long (#{d} ms)"
        end
        cue[:text].each_with_index do |text, j|
          output << prefix + "line #{j + 1} too long (#{text.length} chars)" if text.length > 42
        end
        output << prefix + "too many lines (#{cue[:text].length})" if cue[:text].length >= 3
        c = chars(cue)
        if d.positive? && c * 1000 > 21 * d
          output << prefix + "too fast (#{decimal((c * 100_000).div(d))} cps)"
        end
      end
      output << "VALIDATE problems=#{output.length}"
    when "SEARCH"
      @cues.each_with_index do |cue, i|
        match = cue[:text].find { |text| text.include?(args[0]) }
        output << "#{i + 1} #{srt(cue[:start])} #{match}" if match
      end
      output << "SEARCH found=#{output.length}"
    when "GAPS"
      (0...n - 1).each do |i|
        gap = @cues[i + 1][:start] - @cues[i][:end]
        output << "#{i + 1} #{i + 2} #{gap}" if gap < v[0]
      end
      output << "GAPS count=#{output.length}"
    when "STATS"
      output << "STATS cues=#{n}"
      if n.positive?
        durations = @cues.map { |cue| [0, cue[:end] - cue[:start]].max }
        total = durations.sum
        c = @cues.each_with_index.sum { |cue, i| durations[i].positive? ? chars(cue) : 0 }
        output << "duration total=#{srt(total)} mean=#{srt(total.div(n))}"
        output << "speed " + (total.positive? ? decimal((c * 100_000).div(total)) : "-")
        maximum = durations.max
        output << "longest cue=#{durations.index(maximum) + 1} duration=#{srt(maximum)}"
        if n == 1
          output << "gap none"
        else
          gaps = @cues.drop(1).each_with_index.map { |cue, i| cue[:start] - @cues[i][:end] }
          maximum_gap = gaps.max
          output << "gap cue=#{gaps.index(maximum_gap) + 1} ms=#{maximum_gap}"
        end
      end
    when "PRINT"
      @cues.each do |cue|
        output.concat([cue[:index].to_s, "#{srt(cue[:start])} --> #{srt(cue[:end])}", *cue[:text], ""])
      end
    when "TOVTT"
      output.concat(["WEBVTT", ""])
      escapes = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;" }
      @cues.each do |cue|
        digit = 0
        converted = cue[:text].map do |line|
          result = +""
          markup(line).each do |token|
            digit = token[:digit] if token[:kind] == :position && digit.zero?
            if token[:kind] == :format
              result << token[:text]
            elsif token[:kind] == :char
              result << escapes.fetch(token[:text], token[:text])
            end
          end
          result.strip
        end.reject(&:empty?)
        next if converted.empty?

        settings = digit >= 7 ? " line:0" : digit >= 4 ? " line:50%" : ""
        settings += " align:start" if [1, 4, 7].include?(digit)
        settings += " align:end" if [3, 6, 9].include?(digit)
        timing = "#{srt(cue[:start]).tr(',', '.')} --> #{srt(cue[:end]).tr(',', '.')}#{settings}"
        output.concat([cue[:index].to_s, timing, *converted, ""])
      end
    when "TOASS"
      output.concat(["[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"])
      tags = {
        "<i>" => "{\\i1}", "</i>" => "{\\i0}", "<b>" => "{\\b1}",
        "</b>" => "{\\b0}", "<u>" => "{\\u1}", "</u>" => "{\\u0}"
      }
      @cues.each do |cue|
        converted = cue[:text].map do |line|
          markup(line).map do |token|
            if token[:kind] == :format
              tags[token[:text]]
            elsif token[:kind] == :font
              ""
            else
              token[:text]
            end
          end.join
        end
        output << "Dialogue: 0,#{ass(cue[:start])},#{ass(cue[:end])},Default,,0,0,0,," + converted.join("\\N")
      end
    when "FRAMES"
      @cues.each_with_index do |cue, i|
        frames = [cue[:start], cue[:end]].map { |t| (t * rate[0]).div(1000 * rate[1]) }
        output << "#{i + 1} #{frames[0]} #{frames[1]}"
      end
    when "SHIFT", "SHIFTFROM", "SCALE", "SYNC", "SNAP"
      clamped = 0
      changed = 0
      first = name == "SHIFTFROM" ? v[0] - 1 : 0
      shift = name == "SHIFTFROM" ? v[1] : v[0]
      s1 = name == "SYNC" ? @cues[v[0] - 1][:start] : 0
      s2 = name == "SYNC" ? @cues[v[2] - 1][:start] : 0
      (first...n).each do |i|
        cue = @cues[i]
        was_clamped = false
        %i[start end].each do |key|
          t = cue[key]
          result = case name
                   when "SHIFT", "SHIFTFROM"
                     t + shift
                   when "SCALE"
                     rounded(t * v[0], v[1])
                   when "SYNC"
                     den = s2 - s1
                     rounded(v[1] * den + (t - s1) * (v[3] - v[1]), den)
                   else
                     frame = rounded(t * rate[0], 1000 * rate[1])
                     rounded(frame * 1000 * rate[1], rate[0])
                   end
          if result.negative?
            was_clamped = true
            result = 0
          end
          changed += 1 if result != t
          cue[key] = result
        end
        clamped += 1 if was_clamped
      end
      output << if name == "SNAP"
                  "SNAP changed=#{changed}"
                elsif name == "SCALE"
                  "SCALE cues=#{n}"
                else
                  "#{name} cues=#{n - first} clamped=#{clamped}"
                end
    when "FIXOVERLAP"
      fixed = 0
      failed = 0
      (0...n - 1).each do |i|
        cue = @cues[i]
        limit = @cues[i + 1][:start] - v[0]
        next unless cue[:end] > limit
        if limit > cue[:start]
          cue[:end] = limit
          fixed += 1
        else
          failed += 1
          output << "cue #{i + 1}: cannot fix"
        end
      end
      output << "FIXOVERLAP fixed=#{fixed} failed=#{failed}"
    when "EXTEND"
      extended = 0
      @cues.each_with_index do |cue, i|
        next unless cue[:end] - cue[:start] < v[0]
        candidate = cue[:start] + v[0]
        candidate = [candidate, @cues[i + 1][:start]].min if i + 1 < n
        if candidate > cue[:end]
          cue[:end] = candidate
          extended += 1
        end
      end
      short = @cues.count { |cue| cue[:end] - cue[:start] < v[0] }
      output << "EXTEND extended=#{extended} short=#{short}"
    when "TIME"
      @cues[v[0] - 1][:start] = v[1]
      @cues[v[0] - 1][:end] = v[2]
      output << "TIME cue=#{v[0]}"
    when "SORT"
      sorted = @cues.each_with_index.sort_by { |cue, i| [cue[:start], cue[:end], i] }
      moved = sorted.each_with_index.count { |(_, old_position), i| old_position != i }
      @cues = sorted.map(&:first)
      output << "SORT moved=#{moved}"
    when "RENUMBER"
      changed = 0
      @cues.each_with_index do |cue, i|
        if cue[:index] != i + 1
          cue[:index] = i + 1
          changed += 1
        end
      end
      output << "RENUMBER changed=#{changed}"
    when "MERGE"
      merged = []
      joins = 0
      @cues.each do |cue|
        previous = merged[-1]
        lines = previous ? wrap(previous[:text] + cue[:text], 42) : []
        if previous && cue[:start] - previous[:end] < v[0] &&
           !dialogue?(previous) && !dialogue?(cue) && lines.length <= 2
          previous[:end] = [previous[:end], cue[:end]].max
          previous[:text] = lines
          joins += 1
        else
          merged << cue
        end
      end
      @cues = merged
      output << "MERGE merged=#{joins} cues=#{merged.length}"
    when "SPLIT"
      result = []
      split = 0
      @cues.each do |cue|
        duration = cue[:end] - cue[:start]
        if duration <= 0 || dialogue?(cue)
          result << cue
          next
        end
        lines = wrap(cue[:text], v[0])
        if lines.length <= 2
          cue[:text] = lines
          result << cue
          next
        end
        split += 1
        parts = lines.each_slice(2).to_a
        counts = parts.map { |part| part.sum(&:length) }
        total = counts.sum
        times = counts.map { |c| (duration * c).div(total) }
        order = counts.each_index.sort_by { |i| [-(duration * counts[i] % total), i] }
        (duration - times.sum).times { |i| times[order[i]] += 1 }
        start = cue[:start]
        parts.each_with_index do |text, i|
          result << { index: cue[:index], start: start, end: start + times[i], text: text }
          start += times[i]
        end
      end
      @cues = result
      output << "SPLIT split=#{split} cues=#{result.length}"
    when "INSERT"
      @cues.insert(v[0] - 1, { index: v[0], start: v[1], end: v[2], text: texts })
      output << "INSERT cue=#{v[0]} cues=#{@cues.length}"
    when "DELETE"
      count = (v[1] || v[0]) - v[0] + 1
      @cues.slice!(v[0] - 1, count)
      output << "DELETE removed=#{count} cues=#{@cues.length}"
    when "TEXT"
      @cues[v[0] - 1][:text] = texts
      output << "TEXT cue=#{v[0]} lines=#{texts.length}"
    when "BALANCE"
      changed = 0
      skipped = 0
      dialogues = 0
      @cues.each do |cue|
        if dialogue?(cue)
          dialogues += 1
          next
        end
        all = words(cue[:text])
        joined = all.join(" ")
        best = joined.length <= 42 ? [joined] : nil
        unless best
          (1...all.length).each do |j|
            candidate = [all.take(j).join(" "), all.drop(j).join(" ")]
            next if candidate.any? { |text| text.length > 42 }
            key = [(candidate[0].length - candidate[1].length).abs, candidate[0].length]
            best_key = best && [(best[0].length - best[1].length).abs, best[0].length]
            best = candidate if best.nil? || (key <=> best_key).negative?
          end
        end
        if best.nil?
          skipped += 1
        elsif best != cue[:text]
          cue[:text] = best
          changed += 1
        end
      end
      output << "BALANCE changed=#{changed} skipped=#{skipped} dialogue=#{dialogues}"
    when "STRIP", "CLEANHI"
      tags = 0
      segments = 0
      labels = 0
      deleted_lines = 0
      result = []
      @cues.each do |cue|
        lines = []
        cue[:text].each do |original|
          line = +""
          if name == "STRIP"
            markup(original).each do |token|
              if token[:kind] == :char
                line << token[:text]
              else
                tags += 1
              end
            end
            line = line.strip
          else
            p = 0
            while p < original.length
              close = original[p] == "[" ? "]" : original[p] == "(" ? ")" : nil
              ending = close && original.index(close, p + 1)
              if ending
                segments += 1
                p = ending + 1
              else
                line << original[p]
                p += 1
              end
            end
            line = line.gsub(/ +/, " ").strip
            prefix = line.start_with?("- ") ? "- " : ""
            body = line[prefix.length..]
            colon = body.index(":")
            if colon && body[0...colon].match?(/\A[A-Z][A-Z0-9 ]*\z/)
              labels += 1
              line = (prefix + body[colon + 1..]).gsub(/ +/, " ").strip
            end
          end
          if line.empty? || (name == "CLEANHI" && line == "-")
            deleted_lines += 1
          else
            lines << line
          end
        end
        unless lines.empty?
          cue[:text] = lines
          result << cue
        end
      end
      @cues = result
      suffix = " removed_lines=#{deleted_lines} removed_cues=#{n - result.length}"
      output << if name == "STRIP"
                  "STRIP tags=#{tags}" + suffix
                else
                  "CLEANHI segments=#{segments} labels=#{labels}" + suffix
                end
    when "REPLACE"
      count = 0
      changed = 0
      @cues.each do |cue|
        matches = 0
        cue[:text] = cue[:text].map do |line|
          parts = line.split(old, -1)
          matches += parts.length - 1
          parts.join(replacement)
        end
        count += matches
        changed += 1 if matches.positive?
      end
      output << "REPLACE count=#{count} cues=#{changed}"
    end
    output
  end
end

lines = STDIN.read.split("\n", -1)
terminator = lines.index("###")
editor = Editor.new
output = editor.load(lines.take(terminator))
count = lines[terminator + 1].to_i
count.times do |i|
  begin
    output.concat(editor.execute(lines[terminator + 2 + i]))
  rescue Invalid => error
    output << "ERROR " + error.message
  end
end
STDOUT.write(output.join("\n") + "\n")
