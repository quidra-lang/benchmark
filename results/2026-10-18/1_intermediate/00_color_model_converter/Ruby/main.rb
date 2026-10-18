class Invalid < StandardError
end

class ColorConverter
  BUILTIN_HEX = {
    'black' => '#000000', 'maroon' => '#800000', 'green' => '#008000', 'olive' => '#808000',
    'navy' => '#000080', 'purple' => '#800080', 'teal' => '#008080', 'silver' => '#C0C0C0',
    'gray' => '#808080', 'red' => '#FF0000', 'lime' => '#00FF00', 'yellow' => '#FFFF00',
    'blue' => '#0000FF', 'magenta' => '#FF00FF', 'cyan' => '#00FFFF', 'white' => '#FFFFFF',
    'orange' => '#FFA500', 'pink' => '#FFC0CB', 'brown' => '#A52A2A', 'gold' => '#FFD700',
    'coral' => '#FF7F50', 'salmon' => '#FA8072', 'violet' => '#EE82EE', 'indigo' => '#4B0082'
  }.freeze
  BUILTINS = BUILTIN_HEX.transform_values do |value|
    [1, 3, 5].map { |start| value[start, 2].to_i(16) }
  end.freeze

  BLEND_MODES = %w[
    MULTIPLY SCREEN OVERLAY HARDLIGHT SOFTLIGHT DARKEN LIGHTEN DIFFERENCE EXCLUSION
    ADD SUBTRACT COLORDODGE COLORBURN HUE SATURATION COLOR LUMINOSITY
  ].freeze
  SIMULATIONS = {
    'PROTANOPIA' => [[567, 433, 0], [558, 442, 0], [0, 242, 758]],
    'DEUTERANOPIA' => [[625, 375, 0], [700, 300, 0], [0, 300, 700]],
    'TRITANOPIA' => [[950, 50, 0], [0, 433, 567], [0, 475, 525]],
    'ACHROMATOPSIA' => [[299, 587, 114], [299, 587, 114], [299, 587, 114]]
  }.freeze
  ROTATIONS = {
    'COMPLEMENT' => [180], 'TRIADIC' => [120, 240],
    'TETRADIC' => [90, 180, 270], 'SPLITCOMP' => [150, 210]
  }.freeze
  FIXED_GROUPS = [
    ['LIST', 0],
    ['PARSE UNDEFINE HSL HSV HWB CMYK YCBCR YIQ RGB565 FROM565 ANSI FROMANSI WEBSAFE INVERT COMPLEMENT TRIADIC TETRADIC SPLITCOMP NEAREST DESCRIBE', 1],
    ['DEFINE GRAY TINTS SHADES TONES SIMULATE ROTATE LIGHTEN DARKEN SATURATE DESATURATE DISTANCE CONTRAST ACCESSIBLE RANDOM', 2],
    ['FROMHSL FROMHSV FROMHWB FROMYCBCR FROMYIQ MIX MIXHSL GRADIENT BLEND ANALOGOUS', 3],
    ['FROMCMYK ALPHA', 4]
  ].freeze
  ARITIES = FIXED_GROUPS.each_with_object({}) do |(names, count), arities|
    names.split.each { |name| arities[name] = [count, count] }
  end.merge(
    'BEST' => [2, 33], 'PALETTE' => [2, 33], 'KMEANS' => [2, 33],
    'SORT' => [1, 32], 'DITHER' => [1, 32]
  ).freeze

  def initialize
    @registered = {}
  end

  def validate(condition)
    raise Invalid unless condition
  end

  def integer(token, low, high)
    validate(token.match?(/\A-?\d{1,9}\z/))
    value = token.to_i
    validate(value.between?(low, high))
    value
  end

  def integers(tokens, ranges)
    tokens.each_with_index.map { |token, i| integer(token, *ranges[i]) }
  end

  def name_argument(token)
    validate(token.match?(/\A[a-z]{1,12}\z/))
    token
  end

  def keyword(token, choices)
    validate(choices.include?(token))
    token
  end

  def color_argument(token)
    if token.match?(/\A#[0-9a-fA-F]{6}\z/)
      return [1, 3, 5].map { |start| token[start, 2].to_i(16) }
    end
    if token.match?(/\A#[0-9a-fA-F]{3}\z/)
      return token[1..].chars.map { |digit| (digit * 2).to_i(16) }
    end
    match = token.match(/\Argb\((\d{1,3}),(\d{1,3}),(\d{1,3})\)\z/)
    if match
      color = match.captures.map(&:to_i)
      validate(color.all? { |component| component <= 255 })
      return color
    end
    color = BUILTINS[token] || @registered[token]
    validate(!color.nil?)
    color.dup
  end

  def table
    BUILTINS.to_a + @registered.to_a
  end

  def hex(color)
    '#' + color.map { |component| format('%02X', component) }.join
  end

  def round_exact(value)
    (value + Rational(1, 2)).floor
  end

  def round_ratio(numerator, denominator)
    (2 * numerator + denominator) / (2 * denominator)
  end

  def away_ratio(numerator, denominator)
    numerator.negative? ? -round_ratio(-numerator, denominator) : round_ratio(numerator, denominator)
  end

  def clamp(value)
    value.clamp(0, 255)
  end

  def distance(a, b)
    a.each_with_index.sum { |value, i| (value - b[i])**2 }
  end

  def hue(color)
    r, g, b = color
    maximum, minimum = color.max, color.min
    difference = maximum - minimum
    return 0 if difference.zero?
    if maximum == r
      value = Rational(60 * (g - b), difference)
      value += 360 if value.negative?
    elsif maximum == g
      value = Rational(60 * (b - r), difference) + 120
    else
      value = Rational(60 * (r - g), difference) + 240
    end
    round_exact(value) % 360
  end

  def hsl(color)
    maximum, minimum = color.max, color.min
    difference = maximum - minimum
    saturation = difference.zero? ? 0 : round_ratio(100 * difference, 255 - (maximum + minimum - 255).abs)
    [hue(color), saturation, round_ratio(100 * (maximum + minimum), 510)]
  end

  def base(h, chroma)
    sector, fraction = h.divmod(60)
    x = chroma * Rational(sector.even? ? fraction : 60 - fraction, 60)
    [
      [chroma, x, 0], [x, chroma, 0], [0, chroma, x],
      [0, x, chroma], [x, 0, chroma], [chroma, 0, x]
    ][sector]
  end

  def from_hsl(h, s, l)
    chroma = Rational((100 - (2 * l - 100).abs) * s, 10000)
    offset = Rational(l, 100) - chroma / 2
    base(h, chroma).map { |component| round_exact(255 * (component + offset)) }
  end

  def from_hsv(h, s, v)
    chroma = Rational(v * s, 10000)
    offset = Rational(v, 100) - chroma
    base(h, chroma).map { |component| round_exact(255 * (component + offset)) }
  end

  def from_hwb(h, w, k)
    return Array.new(3, round_ratio(255 * w, w + k)) if w + k >= 100
    base(h, Rational(1, 1)).map do |component|
      round_exact(255 * (component * Rational(100 - w - k, 100) + Rational(w, 100)))
    end
  end

  def model_values(command, color)
    r, g, b = color
    maximum, minimum = color.max, color.min
    case command
    when 'HSL'
      hsl(color)
    when 'HSV'
      saturation = maximum.zero? ? 0 : round_ratio(100 * (maximum - minimum), maximum)
      [hue(color), saturation, round_ratio(100 * maximum, 255)]
    when 'HWB'
      [hue(color), round_ratio(100 * minimum, 255), round_ratio(100 * (255 - maximum), 255)]
    when 'CMYK'
      return [0, 0, 0, 100] if maximum.zero?
      color.map { |component| round_ratio(100 * (maximum - component), maximum) } +
        [round_ratio(100 * (255 - maximum), 255)]
    when 'YCBCR'
      [
        clamp(round_ratio(299 * r + 587 * g + 114 * b, 1000)),
        clamp(round_ratio(128000 - 169 * r - 331 * g + 500 * b, 1000)),
        clamp(round_ratio(128000 + 500 * r - 419 * g - 81 * b, 1000))
      ]
    when 'YIQ'
      [
        round_ratio(299 * r + 587 * g + 114 * b, 1000),
        round_ratio(596 * r - 274 * g - 322 * b, 1000),
        round_ratio(211 * r - 523 * g + 312 * b, 1000)
      ]
    end
  end

  def model_text(command, color)
    values = model_values(command, color)
    body = if %w[HSL HSV HWB].include?(command)
             "#{values[0]},#{values[1]}%,#{values[2]}%"
           elsif command == 'CMYK'
             values.map { |value| "#{value}%" }.join(',')
           else
             values.join(',')
           end
    "#{command.downcase}(#{body})"
  end

  def ansi_color(code)
    return BUILTINS.values[code].dup if code <= 15
    return Array.new(3, 8 + 10 * (code - 232)) if code >= 232
    levels = [0, 95, 135, 175, 215, 255]
    value = code - 16
    [levels[value / 36], levels[value / 6 % 6], levels[value % 6]]
  end

  def gradient(a, b, count)
    (0...count).map do |index|
      a.each_with_index.map do |value, component|
        value + away_ratio((b[component] - value) * index, count - 1)
      end
    end
  end

  def rotate(color, degrees)
    h, s, l = hsl(color)
    from_hsl((h + degrees) % 360, s, l)
  end

  def blend_channel(mode, x, y)
    case mode
    when 'MULTIPLY'
      x * y / 255
    when 'SCREEN'
      255 - (255 - x) * (255 - y) / 255
    when 'OVERLAY', 'HARDLIGHT'
      if (mode == 'OVERLAY' ? x : y) < 128
        2 * x * y / 255
      else
        255 - 2 * (255 - x) * (255 - y) / 255
      end
    when 'SOFTLIGHT'
      multiply = x * y / 255
      screen = 255 - (255 - x) * (255 - y) / 255
      ((255 - x) * multiply + x * screen) / 255
    when 'DARKEN'
      [x, y].min
    when 'LIGHTEN'
      [x, y].max
    when 'DIFFERENCE'
      (x - y).abs
    when 'EXCLUSION'
      x + y - 2 * x * y / 255
    when 'ADD'
      [255, x + y].min
    when 'SUBTRACT'
      [0, x - y].max
    when 'COLORDODGE'
      y == 255 ? 255 : [255, 255 * x / (255 - y)].min
    when 'COLORBURN'
      y.zero? ? 0 : [0, 255 - 255 * (255 - x) / y].max
    end
  end

  def blend(mode, base_color, top)
    h1, s1, l1 = hsl(base_color)
    h2, s2, l2 = hsl(top)
    case mode
    when 'HUE' then from_hsl(h2, s1, l1)
    when 'SATURATION' then from_hsl(h1, s2, l1)
    when 'COLOR' then from_hsl(h2, s2, l1)
    when 'LUMINOSITY' then from_hsl(h1, s1, l2)
    else
      base_color.each_with_index.map { |value, i| blend_channel(mode, value, top[i]) }
    end
  end

  def contrast(a, b)
    luminance = ->(color) { 2126 * color[0]**2 + 7152 * color[1]**2 + 722 * color[2]**2 }
    first, second = luminance.call(a), luminance.call(b)
    high, low = [first, second].max + 32512500, [first, second].min + 32512500
    verdict = high >= 7 * low ? 'AAA' : 2 * high >= 9 * low ? 'AA' : 'FAIL'
    [round_ratio(100 * high, low), verdict]
  end

  def contrast_text(info)
    format('%d.%02d %s', info[0] / 100, info[0] % 100, info[1])
  end

  def accessible(foreground, background)
    return foreground if contrast(foreground, background)[1] != 'FAIL'
    h, s, l = hsl(foreground)
    (1..100).each do |step|
      [l - step, l + step].each do |lightness|
        next unless lightness.between?(0, 100)
        candidate = from_hsl(h, s, lightness)
        return candidate if contrast(candidate, background)[1] != 'FAIL'
      end
    end
    raise 'Accessible color must exist'
  end

  def describe(color)
    h, s, l = hsl(color)
    return 'black' if l <= 5
    return 'white' if l >= 95
    lightness = if l <= 20 then 'very dark'
                elsif l <= 40 then 'dark'
                elsif l <= 60 then 'medium'
                elsif l <= 80 then 'light'
                else 'very light'
                end
    return "#{lightness} gray" if s < 10
    saturation = s < 40 ? 'muted' : s < 80 ? 'moderate' : 'vivid'
    names = %w[red orange yellow chartreuse green spring-green cyan azure blue violet magenta rose]
    "#{lightness} #{saturation} #{names[((h + 15) % 360) / 30]}"
  end

  def mean(colors)
    (0...3).map { |component| round_ratio(colors.sum { |color| color[component] }, colors.length) }
  end

  def palette(colors, count)
    boxes = [colors.dup]
    while boxes.length < count
      chosen = -1
      chosen_width = -1
      component = 0
      boxes.each_with_index do |box, index|
        next if box.length < 2
        widths = (0...3).map do |c|
          minimum, maximum = box.map { |color| color[c] }.minmax
          maximum - minimum
        end
        width = widths.max
        if width > chosen_width
          chosen = index
          chosen_width = width
          component = widths.index(width)
        end
      end
      sorted = boxes[chosen].each_with_index.sort_by { |color, index| [color[component], index] }.map(&:first)
      middle = sorted.length / 2
      boxes[chosen, 1] = [sorted.take(middle), sorted.drop(middle)]
    end
    boxes
  end

  def kmeans(colors, count)
    representatives = palette(colors, count).map { |box| mean(box) }
    counts = []
    iterations = 0
    20.times do
      groups = Array.new(count) { [] }
      colors.each do |color|
        selected = (0...count).min_by { |j| distance(color, representatives[j]) }
        groups[selected] << color
      end
      following = groups.each_with_index.map do |group, j|
        group.empty? ? representatives[j] : mean(group)
      end
      counts = groups.map(&:length)
      iterations += 1
      unchanged = following == representatives
      representatives = following
      break if unchanged
    end
    items = representatives.each_with_index.map { |color, j| "#{hex(color)}:#{counts[j]}" }
    "#{iterations} #{items.join(' ')}"
  end

  def dither(colors)
    error = [0, 0, 0]
    names = []
    entries = BUILTINS.first(16)
    colors.each do |color|
      adjusted = color.each_with_index.map { |value, component| clamp(value + error[component]) }
      selected = (0...16).min_by { |j| distance(adjusted, entries[j][1]) }
      names << entries[selected][0]
      error = adjusted.each_with_index.map { |value, component| value - entries[selected][1][component] }
    end
    names.join(' ')
  end

  def execute(line)
    command, *args = line.split(' ')
    limits = ARITIES[command]
    validate(!limits.nil? && args.length.between?(*limits))
    case command
    when 'DEFINE'
      name = name_argument(args[0])
      validate(!BUILTINS.key?(name))
      color = color_argument(args[1])
      @registered[name] = color
      "#{name} #{hex(color)}"
    when 'UNDEFINE'
      name = name_argument(args[0])
      validate(@registered.key?(name))
      @registered.delete(name)
      "#{name} removed"
    when 'LIST'
      return 'NONE' if @registered.empty?
      @registered.keys.sort.map { |name| "#{name}=#{hex(@registered[name])}" }.join(' ')
    when 'PARSE'
      color = color_argument(args[0])
      first = table.find { |_, value| value == color }
      models = %w[HSL HSV HWB CMYK YCBCR YIQ].map { |model| model_text(model, color) }
      [hex(color), "rgb(#{color.join(',')})", *models, first ? first[0] : '-'].join(' ')
    when 'HSL', 'HSV', 'HWB', 'CMYK', 'YCBCR', 'YIQ'
      model_text(command, color_argument(args[0]))
    when 'FROMHSL', 'FROMHSV', 'FROMHWB'
      h, second, third = integers(args, [[0, 359], [0, 100], [0, 100]])
      color = if command == 'FROMHSL' then from_hsl(h, second, third)
              elsif command == 'FROMHSV' then from_hsv(h, second, third)
              else from_hwb(h, second, third)
              end
      hex(color)
    when 'FROMCMYK'
      c, m, y, k = integers(args, Array.new(4) { [0, 100] })
      hex([c, m, y].map { |value| round_ratio(255 * (100 - value) * (100 - k), 10000) })
    when 'FROMYCBCR'
      y, cb, cr = integers(args, [[0, 255], [0, 255], [0, 255]])
      hex([
        clamp(round_ratio(1000 * y + 1402 * (cr - 128), 1000)),
        clamp(round_ratio(1000 * y - 344 * (cb - 128) - 714 * (cr - 128), 1000)),
        clamp(round_ratio(1000 * y + 1772 * (cb - 128), 1000))
      ])
    when 'FROMYIQ'
      y, i, q = integers(args, [[0, 255], [-255, 255], [-255, 255]])
      hex([
        clamp(round_ratio(1000 * y + 956 * i + 619 * q, 1000)),
        clamp(round_ratio(1000 * y - 272 * i - 647 * q, 1000)),
        clamp(round_ratio(1000 * y - 1106 * i + 1703 * q, 1000))
      ])
    when 'FROM565'
      validate(args[0].match?(/\A0x[0-9a-fA-F]{4}\z/))
      value = args[0][2..].to_i(16)
      hex([
        round_ratio(255 * (value / 2048), 31),
        round_ratio(255 * (value / 32 % 64), 63),
        round_ratio(255 * (value % 32), 31)
      ])
    when 'FROMANSI'
      hex(ansi_color(integer(args[0], 0, 255)))
    when 'RGB565'
      r, g, b = color_argument(args[0])
      value = 2048 * round_ratio(31 * r, 255) + 32 * round_ratio(63 * g, 255) + round_ratio(31 * b, 255)
      format('0x%04X', value)
    when 'ANSI'
      color = color_argument(args[0])
      selected = (16..255).min_by { |code| distance(color, ansi_color(code)) }
      best = distance(color, ansi_color(selected))
      "#{selected} #{hex(ansi_color(selected))} #{best}"
    when 'WEBSAFE'
      hex(color_argument(args[0]).map { |value| 51 * round_ratio(value, 51) })
    when 'INVERT'
      hex(color_argument(args[0]).map { |value| 255 - value })
    when 'GRAY'
      color = color_argument(args[0])
      r, g, b = color
      method = keyword(args[1], %w[LUMA AVERAGE LIGHTNESS HSP])
      value = case method
              when 'LUMA' then round_ratio(299 * r + 587 * g + 114 * b, 1000)
              when 'AVERAGE' then round_ratio(r + g + b, 3)
              when 'LIGHTNESS' then round_ratio(color.max + color.min, 2)
              else Integer.sqrt((299 * r * r + 587 * g * g + 114 * b * b) / 1000)
              end
      hex([value, value, value])
    when 'MIX', 'MIXHSL'
      a, b = color_argument(args[0]), color_argument(args[1])
      p = integer(args[2], 0, 100)
      if command == 'MIX'
        return hex(a.each_with_index.map { |value, i| round_ratio(value * (100 - p) + b[i] * p, 100) })
      end
      h1, s1, l1 = hsl(a)
      h2, s2, l2 = hsl(b)
      delta = (h2 - h1) % 360
      delta -= 360 if delta > 180
      hex(from_hsl(
        (h1 + away_ratio(delta * p, 100)) % 360,
        s1 + away_ratio((s2 - s1) * p, 100),
        l1 + away_ratio((l2 - l1) * p, 100)
      ))
    when 'GRADIENT'
      a, b = color_argument(args[0]), color_argument(args[1])
      count = integer(args[2], 2, 16)
      gradient(a, b, count).map { |color| hex(color) }.join(' ')
    when 'TINTS', 'SHADES', 'TONES'
      color = color_argument(args[0])
      count = integer(args[1], 1, 10)
      target = command == 'TINTS' ? [255, 255, 255] : command == 'SHADES' ? [0, 0, 0] : [128, 128, 128]
      gradient(color, target, count + 2)[1...-1].map { |value| hex(value) }.join(' ')
    when 'BLEND'
      mode = keyword(args[0], BLEND_MODES)
      base_color, top = color_argument(args[1]), color_argument(args[2])
      hex(blend(mode, base_color, top))
    when 'ALPHA'
      foreground = color_argument(args[0])
      p = integer(args[1], 0, 100)
      background = color_argument(args[2])
      q = integer(args[3], 0, 100)
      opacity = 100 * p + q * (100 - p)
      color = if opacity.zero?
                [0, 0, 0]
              else
                foreground.each_with_index.map do |value, i|
                  round_ratio(100 * p * value + q * (100 - p) * background[i], opacity)
                end
              end
      "#{hex(color)} #{round_ratio(opacity, 100)}%"
    when 'SIMULATE'
      color = color_argument(args[0])
      type = keyword(args[1], SIMULATIONS.keys)
      result = SIMULATIONS[type].map do |row|
        round_ratio(row.each_with_index.sum { |value, i| value * color[i] }, 1000)
      end
      hex(result)
    when 'ROTATE'
      hex(rotate(color_argument(args[0]), integer(args[1], -720, 720)))
    when 'COMPLEMENT', 'TRIADIC', 'TETRADIC', 'SPLITCOMP'
      color = color_argument(args[0])
      ROTATIONS[command].map { |degrees| hex(rotate(color, degrees)) }.join(' ')
    when 'ANALOGOUS'
      color = color_argument(args[0])
      k, step = integer(args[1], 1, 6), integer(args[2], 1, 60)
      (-k..k).reject(&:zero?).map { |i| hex(rotate(color, i * step)) }.join(' ')
    when 'LIGHTEN', 'DARKEN', 'SATURATE', 'DESATURATE'
      color = color_argument(args[0])
      p = integer(args[1], 0, 100)
      h, s, l = hsl(color)
      l = [100, l + p].min if command == 'LIGHTEN'
      l = [0, l - p].max if command == 'DARKEN'
      s = [100, s + p].min if command == 'SATURATE'
      s = [0, s - p].max if command == 'DESATURATE'
      hex(from_hsl(h, s, l))
    when 'NEAREST'
      color = color_argument(args[0])
      selected = table.min_by { |entry| distance(color, entry[1]) }
      best = distance(color, selected[1])
      "#{selected[0]} #{hex(selected[1])} #{best}"
    when 'DISTANCE'
      a, b = color_argument(args[0]), color_argument(args[1])
      dr, dg, db = a.each_with_index.map { |value, i| value - b[i] }
      weighted = (1024 + a[0] + b[0]) * dr * dr + 2048 * dg * dg + (1534 - a[0] - b[0]) * db * db
      "#{distance(a, b)} #{Integer.sqrt(weighted / 512)}"
    when 'CONTRAST'
      contrast_text(contrast(color_argument(args[0]), color_argument(args[1])))
    when 'ACCESSIBLE'
      foreground, background = color_argument(args[0]), color_argument(args[1])
      result = accessible(foreground, background)
      "#{hex(result)} #{contrast_text(contrast(result, background))}"
    when 'BEST'
      background, *colors = args.map { |token| color_argument(token) }
      chosen = colors.max_by { |color| contrast(color, background)[0] }
      info = contrast(chosen, background)
      "#{hex(chosen)} #{contrast_text(info)}"
    when 'DESCRIBE'
      describe(color_argument(args[0]))
    when 'PALETTE', 'KMEANS'
      count = integer(args[0], 1, args.length - 1)
      colors = args.drop(1).map { |token| color_argument(token) }
      return kmeans(colors, count) if command == 'KMEANS'
      palette(colors, count).map { |box| "#{hex(mean(box))}:#{box.length}" }.join(' ')
    when 'SORT'
      records = args.each_with_index.map { |token, index| [color_argument(token), index] }
      records.sort_by { |color, index| [*hsl(color), index] }.map { |color, _| hex(color) }.join(' ')
    when 'DITHER'
      dither(args.map { |token| color_argument(token) })
    when 'RANDOM'
      state = integer(args[0], 1, 999999999)
      count = integer(args[1], 1, 16)
      colors = count.times.map do
        state = state * 48271 % 2147483647
        h = state % 360
        state = state * 48271 % 2147483647
        s = 40 + state % 61
        state = state * 48271 % 2147483647
        l = 25 + state % 51
        from_hsl(h, s, l)
      end
      colors.map { |color| hex(color) }.join(' ')
    end
  end
end

converter = ColorConverter.new
count = STDIN.gets.to_i
count.times do
  begin
    puts converter.execute(STDIN.gets.chomp)
  rescue Invalid
    puts 'INVALID'
  end
end
