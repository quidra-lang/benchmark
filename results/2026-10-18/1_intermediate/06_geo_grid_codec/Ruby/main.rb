class Invalid < StandardError
end

class Codec
  SEQUENCES = {
    "GEOHASH" => (1..9).to_a, "MAIDENHEAD" => [2, 4, 6, 8],
    "PLUSCODE" => [2, 4, 6, 8, 10, 11], "GARS" => [5, 6, 7],
    "GEOREF" => [2, 4, 8, 10, 12], "MESH" => [4, 6, 8, 9, 10, 11]
  }.freeze
  DIMENSIONS = {
    "MAIDENHEAD" => [[18, 18], [180, 180], [4320, 4320], [43200, 43200]],
    "PLUSCODE" => [[18, 9], [360, 180], [7200, 3600], [144000, 72000], [2880000, 1440000], [11520000, 7200000]],
    "GARS" => [[720, 360], [1440, 720], [4320, 2160]],
    "GEOREF" => [[24, 12], [360, 180], [21600, 10800], [216000, 108000], [2160000, 1080000]],
    "MESH" => [[360, 270], [2880, 2160], [28800, 21600], [57600, 43200], [115200, 86400], [230400, 172800]]
  }.freeze
  L24 = "ABCDEFGHJKLMNPQRSTUVWXYZ"
  GEOHASH = "0123456789bcdefghjkmnpqrstuvwxyz"
  PLUS = "23456789CFGHJMPQRVWX"
  MAIDEN = ["ABCDEFGHIJKLMNOPQR", "0123456789", "abcdefghijklmnopqrstuvwx", "0123456789"].freeze
  NATIONAL = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
  BANDS = "CDEFGHJKLMNPQRSTUVWX"
  MGRS_COLUMNS = %w[ABCDEFGH JKLMNPQR STUVWXYZ].freeze
  MGRS_ROWS = "ABCDEFGHJKLMNPQRSTUV"
  ARITIES = {
    "ENCODE" => [4], "DECODE" => [2], "NEIGHBORS" => [2], "PARENT" => [2],
    "CHILDREN" => [2], "COMMON" => [3], "CONTAINS" => [4], "COVER" => [6],
    "CONVERT" => [5], "STEPS" => [3], "PATH" => [3], "RELATE" => [4], "SIZE" => [2],
    "SHORTEN" => [3], "RECOVER" => [3], "UTMZONE" => [2], "OSGB" => [3],
    "UNOSGB" => [1, 3], "MGRS" => [5], "UNMGRS" => [2, 4], "QUADKEY" => [3],
    "UNQUADKEY" => [1]
  }.freeze

  def invalid
    raise Invalid
  end

  def integer(text, low, high)
    invalid unless text.match?(/\A-?[0-9]{1,9}\z/)
    value = text.to_i
    invalid unless value.between?(low, high)
    value
  end

  def coordinate(text, latitude)
    invalid unless text.match?(/\A-?[0-9]{1,3}(?:\.[0-9]{1,6})?\z/)
    negative = text.start_with?("-")
    whole, fraction = (negative ? text[1..] : text).split(".")
    value = whole.to_i * 1_000_000 + (fraction || "").ljust(6, "0").to_i
    value = -value if negative
    outside = latitude ? !value.between?(-90_000_000, 90_000_000) : value < -180_000_000 || value >= 180_000_000
    invalid if outside
    value
  end

  def system_name(text)
    invalid unless SEQUENCES.key?(text)
    text
  end

  def precision(system, text)
    value = integer(text, 1, 12)
    invalid unless SEQUENCES[system].include?(value)
    value
  end

  def grid(system, p, x = 0, y = 0)
    if system == "GEOHASH"
      w = 1 << (5 * p + 1).div(2)
      h = 1 << (5 * p).div(2)
    else
      w, h = DIMENSIONS[system][SEQUENCES[system].index(p)]
    end
    { system: system, p: p, x: x, y: y, w: w, h: h }
  end

  def digits(value, radices)
    result = Array.new(radices.length)
    (radices.length - 1).downto(0) do |i|
      result[i] = value % radices[i]
      value = value.div(radices[i])
    end
    result
  end

  def character(set, value)
    index = value && set.index(value)
    invalid unless value && value.length == 1 && index
    index
  end

  def encode(cell)
    x = cell[:x]
    y = cell[:y]
    p = cell[:p]
    case cell[:system]
    when "GEOHASH"
      xs = x.to_s(2).rjust((5 * p + 1).div(2), "0")
      ys = y.to_s(2).rjust((5 * p).div(2), "0")
      bits = Array.new(5 * p) { |i| i.even? ? xs[i.div(2)] : ys[i.div(2)] }.join
      bits.scan(/.{5}/).map { |part| GEOHASH[part.to_i(2)] }.join
    when "MAIDENHEAD"
      count = p.div(2)
      radices = [18, 10, 24, 10].take(count)
      xs = digits(x, radices)
      ys = digits(y, radices)
      xs.each_with_index.map { |value, i| MAIDEN[i][value] + MAIDEN[i][ys[i]] }.join
    when "PLUSCODE"
      tail = ""
      if p == 11
        tail = PLUS[4 * (y % 5) + x % 4]
        x = x.div(4)
        y = y.div(5)
      end
      count = [p, 10].min.div(2)
      xs = digits(x, [18] + [20] * (count - 1))
      ys = digits(y, [9] + [20] * (count - 1))
      code = xs.each_with_index.map { |value, i| PLUS[ys[i]] + PLUS[value] }.join + tail
      p >= 8 ? code[0, 8] + "+" + code[8..] : code + "0" * (8 - p) + "+"
    when "GARS"
      suffix = ""
      if p == 7
        suffix = (1 + x % 3 + 3 * (2 - y % 3)).to_s
        x = x.div(3)
        y = y.div(3)
      end
      if p >= 6
        suffix = (1 + x % 2 + 2 * (1 - y % 2)).to_s + suffix
        x = x.div(2)
        y = y.div(2)
      end
      (x + 1).to_s.rjust(3, "0") + L24[y.div(24)] + L24[y % 24] + suffix
    when "GEOREF"
      tail = ""
      if p >= 8
        m = (p - 4).div(2)
        radix = 6 * 10**(m - 1)
        tail = (x % radix).to_s.rjust(m, "0") + (y % radix).to_s.rjust(m, "0")
        x = x.div(radix)
        y = y.div(radix)
      end
      return L24[x] + L24[y] if p == 2
      L24[x.div(15)] + L24[y.div(15)] + L24[x % 15] + L24[y % 15] + tail
    when "MESH"
      index = SEQUENCES["MESH"].index(p)
      scale = [1, 8, 80, 160, 320, 640][index]
      u = x - 280 * scale
      v = y - 135 * scale
      return nil unless u.between?(0, 80 * scale - 1) && v.between?(0, 100 * scale - 1)
      xs = digits(u, [80, 8, 10, 2, 2, 2].take(index + 1))
      ys = digits(v, [100, 8, 10, 2, 2, 2].take(index + 1))
      code = ys[0].to_s.rjust(2, "0") + xs[0].to_s.rjust(2, "0")
      (1...xs.length).each do |i|
        code += i <= 2 ? "#{ys[i]}#{xs[i]}" : (1 + xs[i] + 2 * ys[i]).to_s
      end
      code
    end
  end

  def decode(system, code)
    p = code.length
    x = 0
    y = 0
    case system
    when "GEOHASH"
      invalid unless p.between?(1, 9)
      bits = code.chars.map { |c| character(GEOHASH, c).to_s(2).rjust(5, "0") }.join
      bits.chars.each_with_index do |bit, i|
        if i.even?
          x = 2 * x + bit.to_i
        else
          y = 2 * y + bit.to_i
        end
      end
    when "MAIDENHEAD"
      invalid unless SEQUENCES[system].include?(p)
      p.div(2).times do |i|
        x = x * MAIDEN[i].length + character(MAIDEN[i], code[2 * i])
        y = y * MAIDEN[i].length + character(MAIDEN[i], code[2 * i + 1])
      end
    when "PLUSCODE"
      parts = code.split("+", -1)
      invalid unless parts.length == 2 && parts[0].length == 8
      zero = parts[0].index("0")
      if zero
        invalid unless [2, 4, 6].include?(zero) && parts[0][zero..] == "0" * (8 - zero) && parts[1].empty?
        raw = parts[0][0...zero]
      else
        invalid unless [0, 2, 3].include?(parts[1].length)
        raw = parts.join
      end
      values = raw.chars.map { |c| character(PLUS, c) }
      invalid if values[0] > 8 || values[1] > 17
      p = values.length
      (0...[p, 10].min).step(2) do |i|
        y = y * (i.zero? ? 9 : 20) + values[i]
        x = x * (i.zero? ? 18 : 20) + values[i + 1]
      end
      if p == 11
        x = 4 * x + values[10] % 4
        y = 5 * y + values[10].div(4)
      end
    when "GARS"
      invalid unless code.match?(/\A[0-9]{3}[A-Z]{2}[1-4]?[1-9]?\z/) && p.between?(5, 7)
      band = code[0, 3].to_i
      invalid unless band.between?(1, 720)
      x = band - 1
      y = 24 * character(L24[0, 15], code[3]) + character(L24, code[4])
      if p >= 6
        q = code[5].to_i - 1
        invalid unless q.between?(0, 3)
        x = 2 * x + q % 2
        y = 2 * y + 1 - q.div(2)
      end
      if p == 7
        k = code[6].to_i - 1
        x = 3 * x + k % 3
        y = 3 * y + 2 - k.div(3)
      end
    when "GEOREF"
      invalid unless SEQUENCES[system].include?(p)
      x = character(L24, code[0])
      y = character(L24[0, 12], code[1])
      if p >= 4
        x = 15 * x + character(L24[0, 15], code[2])
        y = 15 * y + character(L24[0, 15], code[3])
      end
      if p >= 8
        m = (p - 4).div(2)
        tail = code[4..]
        invalid unless tail.match?(/\A[0-9]+\z/)
        radix = 6 * 10**(m - 1)
        e = tail[0, m].to_i
        n = tail[m..].to_i
        invalid if e >= radix || n >= radix
        x = x * radix + e
        y = y * radix + n
      end
    when "MESH"
      invalid unless SEQUENCES[system].include?(p) && code.match?(/\A[0-9]+\z/) && code[2, 2].to_i <= 79
      u = code[2, 2].to_i
      v = code[0, 2].to_i
      if p >= 6
        invalid if code[4].to_i > 7 || code[5].to_i > 7
        v = 8 * v + code[4].to_i
        u = 8 * u + code[5].to_i
      end
      if p >= 8
        v = 10 * v + code[6].to_i
        u = 10 * u + code[7].to_i
      end
      (8...p).each do |i|
        q = code[i].to_i - 1
        invalid unless q.between?(0, 3)
        u = 2 * u + q % 2
        v = 2 * v + q.div(2)
      end
      scale = [1, 8, 80, 160, 320, 640][SEQUENCES[system].index(p)]
      x = 280 * scale + u
      y = 135 * scale + v
    end
    grid(system, p, x, y)
  end

  def point(system, p, lat, lon)
    cell = grid(system, p)
    cell[:x] = ((lon + 180_000_000) * cell[:w]).div(360_000_000)
    cell[:y] = [((lat + 90_000_000) * cell[:h]).div(180_000_000), cell[:h] - 1].min
    cell
  end

  def ancestor(cell, p)
    parent = grid(cell[:system], p)
    parent[:x] = (cell[:x] * parent[:w]).div(cell[:w])
    parent[:y] = (cell[:y] * parent[:h]).div(cell[:h])
    parent
  end

  def key(cell)
    [cell[:p], cell[:x], cell[:y]]
  end

  def coordinate_text(value)
    magnitude = value.abs
    "#{value.negative? ? '-' : ''}#{magnitude.div(1_000_000)}.#{(magnitude % 1_000_000).to_s.rjust(6, '0')}"
  end

  def center(cell, latitude)
    divisor = latitude ? cell[:h] : cell[:w]
    index = latitude ? cell[:y] : cell[:x]
    span = latitude ? 180_000_000 : 360_000_000
    Rational(-span * divisor + span * (2 * index + 1), 2 * divisor)
  end

  def relate(a, b)
    aw = Rational(a[:x], a[:w])
    ae = Rational(a[:x] + 1, a[:w])
    south_a = Rational(a[:y], a[:h])
    an = Rational(a[:y] + 1, a[:h])
    bw = Rational(b[:x], b[:w])
    be = Rational(b[:x] + 1, b[:w])
    south_b = Rational(b[:y], b[:h])
    bn = Rational(b[:y] + 1, b[:h])
    inside = aw >= bw && ae <= be && south_a >= south_b && an <= bn
    contains = bw >= aw && be <= ae && south_b >= south_a && bn <= an
    return "EQUAL" if inside && contains
    return "INSIDE" if inside
    return "CONTAINS" if contains
    return "OVERLAP" if aw < be && bw < ae && south_a < bn && south_b < an
    y_touch = south_a <= bn && south_b <= an
    x_touch = aw <= be && bw <= ae
    wrapped = (a[:x] + 1 == a[:w] && b[:x].zero?) || (b[:x] + 1 == b[:w] && a[:x].zero?)
    y_touch && (x_touch || wrapped) ? "TOUCH" : "DISJOINT"
  end

  def compact(cells)
    system = cells[0][:system]
    sequence = SEQUENCES[system]
    selected = {}
    cells.sort_by { |cell| sequence.index(cell[:p]) }.each do |cell|
      index = sequence.index(cell[:p])
      unless sequence.take(index).any? { |p| selected.key?(key(ancestor(cell, p))) }
        selected[key(cell)] = cell
      end
    end
    loop do
      merged = false
      selected.values.each do |cell|
        index = sequence.index(cell[:p])
        next if index.zero?
        parent = ancestor(cell, sequence[index - 1])
        rx = cell[:w].div(parent[:w])
        ry = cell[:h].div(parent[:h])
        next if rx * ry > selected.length
        children = []
        ry.times do |j|
          rx.times do |i|
            children << grid(system, cell[:p], rx * parent[:x] + i, ry * parent[:y] + j)
          end
        end
        if children.all? { |child| selected.key?(key(child)) }
          children.each { |child| selected.delete(key(child)) }
          selected[key(parent)] = parent
          merged = true
          break
        end
      end
      break unless merged
    end
    selected.values.sort_by { |cell| [sequence.index(cell[:p]), -cell[:y], cell[:x]] }
            .map { |cell| encode(cell) }.join(" ")
  end

  def offsets(a, b)
    dx = (b[:x] - a[:x]) % a[:w]
    dx -= a[:w] if 2 * dx > a[:w]
    [dx, b[:y] - a[:y]]
  end

  def numeric_digits(args, offset)
    return [0, 0, 100_000] if args.length == offset
    a, b = args[offset, 2]
    invalid unless a.match?(/\A[0-9]{1,5}\z/) && b.match?(/\A[0-9]{1,5}\z/) && a.length == b.length
    size = 10**(5 - a.length)
    [a.to_i * size, b.to_i * size, size]
  end

  def command(line)
    name, *args = line.split(" ")
    if name == "COMPACT"
      invalid unless args.length.between?(2, 101)
      system = system_name(args[0])
      return compact(args.drop(1).map { |code| decode(system, code) })
    end
    invalid unless ARITIES.key?(name) && ARITIES[name].include?(args.length)
    if %w[ENCODE SIZE COVER].include?(name)
      system = system_name(args[0])
      if name == "ENCODE"
        lat = coordinate(args[1], true)
        lon = coordinate(args[2], false)
        return encode(point(system, precision(system, args[3]), lat, lon)) || "OUT OF AREA"
      end
      p = precision(system, args[1])
      cell = grid(system, p)
      if name == "SIZE"
        count = if system == "MESH"
                  scale = [1, 8, 80, 160, 320, 640][SEQUENCES[system].index(p)]
                  8000 * scale * scale
                else
                  cell[:w] * cell[:h]
                end
        return "w=#{coordinate_text(360_000_000.div(cell[:w]))} h=#{coordinate_text(180_000_000.div(cell[:h]))} cells=#{count}"
      end
      lat1 = coordinate(args[2], true)
      lon1 = coordinate(args[3], false)
      lat2 = coordinate(args[4], true)
      lon2 = coordinate(args[5], false)
      invalid if lat1 > lat2
      a = point(system, p, lat1, lon1)
      b = point(system, p, lat2, lon2)
      columns = b[:x] - a[:x] + 1
      columns = [cell[:w], columns + cell[:w]].min if lon1 > lon2
      return "TOO MANY" if columns * (b[:y] - a[:y] + 1) > 100
      codes = []
      b[:y].downto(a[:y]) do |y|
        columns.times { |i| codes << (encode(grid(system, p, (a[:x] + i) % cell[:w], y)) || "-") }
      end
      return codes.join(" ")
    end
    if name == "SHORTEN" || name == "RECOVER"
      lat = coordinate(args[1], true)
      lon = coordinate(args[2], false)
      if name == "SHORTEN"
        cell = decode("PLUSCODE", args[0])
        invalid if cell[:p] < 8
        distance = [(center(cell, true) - lat).abs, (center(cell, false) - lon).abs].max
        return args[0][6..] if distance < 15_000
        return args[0][4..] if distance < 300_000
        return args[0]
      end
      parts = args[0].split("+", -1)
      invalid unless parts.length == 2 && [2, 4].include?(parts[0].length) && [0, 2, 3].include?(parts[1].length)
      parts.join.each_char { |c| character(PLUS, c) }
      removed = 8 - parts[0].length
      prefix = encode(point("PLUSCODE", 10, lat, lon))[0, removed]
      cell = decode("PLUSCODE", prefix + args[0])
      cy = center(cell, true)
      cx = center(cell, false)
      distance = removed == 4 ? 1_000_000 : 50_000
      my = (distance * cell[:h]).div(180_000_000)
      mx = (distance * cell[:w]).div(360_000_000)
      if lat + distance.div(2) < cy && cy - distance >= -90_000_000
        cell[:y] -= my
      elsif lat - distance.div(2) > cy && cy + distance <= 90_000_000
        cell[:y] += my
      end
      if lon + distance.div(2) < cx
        cell[:x] = (cell[:x] - mx) % cell[:w]
      elsif lon - distance.div(2) > cx
        cell[:x] = (cell[:x] + mx) % cell[:w]
      end
      return encode(cell)
    end
    if name == "RELATE"
      return relate(decode(system_name(args[0]), args[1]), decode(system_name(args[2]), args[3]))
    end
    if %w[DECODE NEIGHBORS PARENT CHILDREN COMMON CONTAINS CONVERT STEPS PATH].include?(name)
      system = system_name(args[0])
      cell = decode(system, args[1])
      sequence = SEQUENCES[system]
      index = sequence.index(cell[:p])
      case name
      when "DECODE"
        south = -90_000_000 + (180_000_000 * cell[:y]).div(cell[:h])
        west = -180_000_000 + (360_000_000 * cell[:x]).div(cell[:w])
        north = -90_000_000 + (180_000_000 * (cell[:y] + 1)).div(cell[:h])
        east = -180_000_000 + (360_000_000 * (cell[:x] + 1)).div(cell[:w])
        return "sw=#{coordinate_text(south)},#{coordinate_text(west)} ne=#{coordinate_text(north)},#{coordinate_text(east)} " +
               "c=#{coordinate_text(center(cell, true).floor)},#{coordinate_text(center(cell, false).floor)}"
      when "NEIGHBORS"
        return [[0, 1], [1, 1], [1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1]].map do |dx, dy|
          y = cell[:y] + dy
          y < 0 || y >= cell[:h] ? "-" : encode(grid(system, cell[:p], (cell[:x] + dx) % cell[:w], y)) || "-"
        end.join(" ")
      when "PARENT"
        return index.positive? ? encode(ancestor(cell, sequence[index - 1])) : "NONE"
      when "CHILDREN"
        return "NONE" if index == sequence.length - 1
        child = grid(system, sequence[index + 1])
        rx = child[:w].div(cell[:w])
        ry = child[:h].div(cell[:h])
        return "TOO MANY" if rx * ry > 100
        codes = []
        (ry - 1).downto(0) do |j|
          rx.times { |i| codes << (encode(grid(system, child[:p], rx * cell[:x] + i, ry * cell[:y] + j)) || "-") }
        end
        return codes.join(" ")
      when "CONTAINS"
        lat = coordinate(args[2], true)
        lon = coordinate(args[3], false)
        return key(cell) == key(point(system, cell[:p], lat, lon)) ? "YES" : "NO"
      when "CONVERT"
        invalid unless args[2] == "TO"
        target = system_name(args[3])
        converted = grid(target, precision(target, args[4]))
        converted[:x] = ((2 * cell[:x] + 1) * converted[:w]).div(2 * cell[:w])
        converted[:y] = ((2 * cell[:y] + 1) * converted[:h]).div(2 * cell[:h])
        return encode(converted) || "OUT OF AREA"
      end
      other = decode(system, args[2])
      if name == "COMMON"
        [index, sequence.index(other[:p])].min.downto(0) do |i|
          a = ancestor(cell, sequence[i])
          b = ancestor(other, sequence[i])
          return encode(a) if key(a) == key(b)
        end
        return "NONE"
      end
      return "MISMATCH" if cell[:p] != other[:p]
      dx, dy = offsets(cell, other)
      return "dx=#{dx} dy=#{dy}" if name == "STEPS"
      n = [dx.abs, dy.abs].max
      return "TOO MANY" if n + 1 > 100
      return encode(cell) if n.zero?
      return (0..n).map do |i|
        x = (cell[:x] + (2 * i * dx + n).div(2 * n)) % cell[:w]
        y = cell[:y] + (2 * i * dy + n).div(2 * n)
        encode(grid(system, cell[:p], x, y)) || "-"
      end.join(" ")
    end
    other_command(name, args)
  end

  def other_command(name, args)
    if name == "UTMZONE"
      lat = coordinate(args[0], true)
      lon = coordinate(args[1], false)
      return "NONE" if lat < -80_000_000 || lat >= 84_000_000
      band = BANDS[[(lat + 80_000_000).div(8_000_000), 19].min]
      zone = (lon + 180_000_000).div(6_000_000) + 1
      zone = 32 if band == "V" && lon >= 3_000_000 && lon < 12_000_000
      if band == "X" && lon >= 0 && lon < 42_000_000
        zone = lon < 9_000_000 ? 31 : lon < 21_000_000 ? 33 : lon < 33_000_000 ? 35 : 37
      end
      return "#{zone}#{band}"
    end
    if name == "QUADKEY"
      z = integer(args[2], 1, 23)
      x = integer(args[0], 0, 2**z - 1)
      y = integer(args[1], 0, 2**z - 1)
      return (z - 1).downto(0).map { |i| ((x >> i & 1) + 2 * (y >> i & 1)).to_s }.join
    end
    if name == "UNQUADKEY"
      invalid unless args[0].match?(/\A[0-3]{1,23}\z/)
      x = 0
      y = 0
      args[0].each_char do |c|
        x = 2 * x + c.to_i % 2
        y = 2 * y + c.to_i.div(2)
      end
      return "x=#{x} y=#{y} z=#{args[0].length}"
    end
    if name == "UNOSGB" || name == "UNMGRS"
      if name == "UNOSGB"
        invalid unless args[0].length == 2
        first = character(NATIONAL, args[0][0])
        second = character(NATIONAL, args[0][1])
        e = 500_000 * (first % 5 - 2) + 100_000 * (second % 5)
        n = 500_000 * (3 - first.div(5)) + 100_000 * (4 - second.div(5))
        invalid unless e.between?(0, 699_999) && n.between?(0, 1_299_999)
        offset = 1
      else
        invalid unless args[0].match?(/\A[1-9][0-9]?[C-HJ-NP-X]\z/) && args[1].length == 2
        zone = args[0][0...-1].to_i
        invalid if zone > 60
        character(BANDS, args[0][-1])
        col = character(MGRS_COLUMNS[(zone - 1) % 3], args[1][0])
        row = character(MGRS_ROWS, args[1][1])
        e = 100_000 * (col + 1)
        n = 100_000 * ((row - (zone.even? ? 5 : 0)) % 20)
        offset = 2
      end
      east, north, size = numeric_digits(args, offset)
      return (name == "UNMGRS" ? args[0] + " " : "") + "sw=#{e + east},#{n + north} size=#{size}"
    end
    if name == "OSGB"
      e = integer(args[0], 0, 699_999)
      n = integer(args[1], 0, 1_299_999)
      d = integer(args[2], 0, 5)
      text = NATIONAL[5 * (3 - n.div(500_000)) + 2 + e.div(500_000)] +
             NATIONAL[5 * (4 - n.div(100_000) % 5) + e.div(100_000) % 5]
    else
      zone = integer(args[0], 1, 60)
      character(BANDS, args[1])
      e = integer(args[2], 100_000, 899_999)
      n = integer(args[3], 0, 9_999_999)
      d = integer(args[4], 0, 5)
      text = "#{zone}#{args[1]} " + MGRS_COLUMNS[(zone - 1) % 3][e.div(100_000) - 1] +
             MGRS_ROWS[(n.div(100_000) + (zone.even? ? 5 : 0)) % 20]
    end
    if d.positive?
      text += " " + (e % 100_000).to_s.rjust(5, "0")[0, d] + " " + (n % 100_000).to_s.rjust(5, "0")[0, d]
    end
    text
  end
end

lines = STDIN.read.split("\n")
codec = Codec.new
output = lines[0].to_i.times.map do |i|
  begin
    codec.command(lines[i + 1])
  rescue Invalid
    "INVALID"
  end
end
STDOUT.write(output.join("\n") + "\n")
