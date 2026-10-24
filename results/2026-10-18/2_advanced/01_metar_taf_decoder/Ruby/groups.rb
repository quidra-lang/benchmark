require_relative 'units'

module Groups
  DESCRIPTORS = {
    'MI' => 'shallow', 'BC' => 'patches', 'PR' => 'partial', 'DR' => 'low drifting',
    'BL' => 'blowing', 'SH' => 'showers', 'TS' => 'thunderstorm', 'FZ' => 'freezing'
  }.freeze
  PHENOMENA = {
    'DZ' => 'drizzle', 'RA' => 'rain', 'SN' => 'snow', 'SG' => 'snow grains',
    'IC' => 'ice crystals', 'PL' => 'ice pellets', 'GR' => 'hail', 'GS' => 'small hail',
    'UP' => 'unknown precipitation', 'BR' => 'mist', 'FG' => 'fog', 'FU' => 'smoke',
    'VA' => 'volcanic ash', 'DU' => 'dust', 'SA' => 'sand', 'HZ' => 'haze', 'PY' => 'spray',
    'PO' => 'dust whirls', 'SQ' => 'squalls', 'FC' => 'funnel cloud', 'SS' => 'sandstorm', 'DS' => 'duststorm'
  }.freeze
  PRECIPITATION = %w[DZ RA SN SG IC PL GR GS UP].freeze
  AMOUNTS = {'FEW' => 'few', 'SCT' => 'scattered', 'BKN' => 'broken', 'OVC' => 'overcast'}.freeze
  CLEAR = {'SKC' => 'sky clear', 'CLR' => 'clear below 12000 ft', 'NSC' => 'no significant cloud'}.freeze
  WEATHER = /\A(-|\+|VC)?((?:#{(DESCRIPTORS.keys + PHENOMENA.keys).join('|')})+)\z/

  module_function

  def recognize(kind, text)
    case kind
    when :modifier
      {code: text} if %w[AUTO COR].include?(text)
    when :wind
      match = /\A(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?(KT|MPS)\z/.match(text)
      if match
        {direction: match[1] == 'VRB' ? 'VRB' : match[1].to_i,
         speed: match[2].to_i, gust: match[3]&.to_i, unit: match[4]}
      end
    when :variation
      match = /\A(\d{3})V(\d{3})\z/.match(text)
      {first: match[1].to_i, last: match[2].to_i} if match
    when :visibility
      visibility(text)
    when :rvr
      match = /\AR(\d{2}[LCR]?)\/([MP]?)(\d{4})(?:V([MP]?)(\d{4}))?(FT)?([UDN])?\z/.match(text)
      if match
        readings = [[match[2], match[3].to_i]]
        readings << [match[4], match[5].to_i] if match[5]
        {runway: match[1], readings:, unit: match[6] ? 'ft' : 'm', trend: match[7]}
      end
    when :weather
      return {raw: text, nsw: true, descriptor: nil, phenomena: []} if text == 'NSW'
      match = WEATHER.match(text)
      if match
        codes = match[2].scan(/../)
        descriptor = DESCRIPTORS.key?(codes[0]) ? codes.shift : nil
        {raw: text, nsw: false, intensity: match[1], descriptor:, phenomena: codes}
      end
    when :cloud
      match = /\A(FEW|SCT|BKN|OVC)(\d{3})(CB|TCU)?\z/.match(text)
      if match
        {amount: match[1], height: match[2].to_i * 100, extra: match[3], layer: true}
      elsif (match = /\AVV(\d{3})\z/.match(text))
        {amount: 'VV', height: match[1].to_i * 100, layer: false}
      elsif CLEAR.key?(text)
        {amount: text, height: nil, layer: false}
      end
    when :temperature
      match = /\A(M?)(\d{2})\/(M?)(\d{2})\z/.match(text)
      if match
        {temperature: match[2].to_i * (match[1] == 'M' ? -1 : 1),
         dew: match[4].to_i * (match[3] == 'M' ? -1 : 1)}
      end
    when :pressure
      match = /\A([AQ])(\d{4})\z/.match(text)
      {unit: match[1], value: match[2].to_i} if match
    when :nosig
      {code: text} if text == 'NOSIG'
    end
  end

  def visibility(text)
    return {kind: :cavok, value: 10_000, qualifier: 'P'} if text == 'CAVOK'
    if /\A\d{4}\z/.match?(text)
      return {kind: :meters, value: text == '9999' ? 10_000 : text.to_i, qualifier: text == '9999' ? 'P' : ''}
    end
    if (match = /\A([MP]?)(\d{1,2})SM\z/.match(text))
      {kind: :miles, whole: match[2].to_i, numerator: 0, denominator: 1, qualifier: match[1], fraction: false, mixed: false}
    elsif (match = /\A([MP]?)(\d)\/(\d{1,2})SM\z/.match(text))
      {kind: :miles, whole: 0, numerator: match[2].to_i, denominator: match[3].to_i, qualifier: match[1], fraction: true, mixed: false}
    elsif (match = /\A(\d) (\d)\/(\d{1,2})SM\z/.match(text))
      {kind: :miles, whole: match[1].to_i, numerator: match[2].to_i, denominator: match[3].to_i, qualifier: '', fraction: true, mixed: true}
    end
  end

  def valid?(kind, value, section, station, change)
    case kind
    when :wind
      direction, speed, gust = value.values_at(:direction, :speed, :gust)
      if direction == 'VRB'
        return false if speed < 1
      else
        return false unless direction <= 360 && direction % 10 == 0
        return false unless direction.zero? == speed.zero?
        return false if direction.zero? && gust
      end
      gust.nil? || gust > speed
    when :variation
      first, last = value.values_at(:first, :last)
      wind = section[:wind]
      first.between?(10, 360) && last.between?(10, 360) && first % 10 == 0 && last % 10 == 0 &&
        first != last && wind && wind[:direction] != 'VRB' && wind[:direction] != 0
    when :visibility
      return true unless value[:kind] == :miles
      return value[:whole] >= 1 unless value[:fraction]
      [2, 4, 8, 16].include?(value[:denominator]) && value[:numerator] >= 1 &&
        value[:numerator] < value[:denominator] && (!value[:mixed] || value[:whole] >= 1)
    when :rvr
      station[:runways].any? { |runway| runway[:name] == value[:runway] } &&
        (value[:readings].length == 1 || value[:readings][0][1] < value[:readings][1][1])
    when :weather
      previous = section[:weather] || []
      return false if previous.length >= 3 || previous.any? { |item| item[:nsw] }
      return change && previous.empty? if value[:nsw]
      phenomena = value[:phenomena]
      return false unless phenomena.all? { |code| PHENOMENA.key?(code) }
      return false if phenomena.uniq.length != phenomena.length
      return false if phenomena.empty? && !%w[TS SH].include?(value[:descriptor])
      return false if %w[- +].include?(value[:intensity]) && (phenomena & PRECIPITATION).empty?
      phenomena.length < 2 || phenomena.all? { |code| PRECIPITATION.include?(code) }
    when :cloud
      previous = section[:cloud]
      previous.nil? || previous.empty? || (value[:layer] && previous[-1][:layer] && value[:height] > previous[-1][:height])
    when :temperature
      value[:dew] <= value[:temperature]
    when :pressure
      value[:value].between?(*(value[:unit] == 'A' ? [2500, 3150] : [850, 1070]))
    else
      true
    end
  end

  def record(section, kind, value, repeatable)
    if kind == :wind && value[:unit] == 'MPS'
      value[:speed] = Units.knots(value[:speed])
      value[:gust] = Units.knots(value[:gust]) if value[:gust]
      value[:unit] = 'KT'
    elsif kind == :pressure
      value[:inhg] = value[:unit] == 'A' ? value[:value] : Units.inhg(value[:value])
      value[:hpa] = value[:unit] == 'Q' ? value[:value] : Units.hpa(value[:value])
    end
    if repeatable
      (section[kind] ||= []) << value
    else
      section[kind] = value
    end
  end
end
