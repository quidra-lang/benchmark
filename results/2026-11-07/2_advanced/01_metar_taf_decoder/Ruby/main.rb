require_relative 'groups'
require_relative 'units'
require_relative 'metar'
require_relative 'taf'
require_relative 'verification'

class WeatherDecoder
  CATEGORIES = Verification::CATEGORIES

  def initialize
    @settings = read_lines('params.txt').to_h do |line|
      name, *values = line.split(' ')
      [name, name == 'VERIFY' ? values : values[0].to_i]
    end
    @calendar = Units::Calendar.new(@settings['YEAR'], @settings['MONTH'])
    @stations = read_lines('stations.txt').to_h do |line|
      code, elevation, list, name = line.split(' ', 4)
      runways = list.split(',').map do |item|
        runway, heading = item.split('/')
        {name: runway, heading: heading.to_i}
      end
      [code, {code:, elevation: elevation.to_i, runways:, name:}]
    end
    @errors = []
    @reports = []
    @previous = {}
  end

  def run
    read_reports.each_with_index do |words, index|
      report = header(words, index + 1)
      next unless report
      if report[:kind] == 'TAF'
        decode_taf(report)
      else
        decode_metar(report)
      end
      @reports << report
    end
    categories = ['station,time,ceiling,visibility,category']
    @reports.each do |report|
      next if report[:kind] == 'TAF'
      state = report[:state]
      visibility = state[:visibility]
      categories << [report[:station][:code], @calendar.stamp(report[:time]), state[:ceiling] || 'NONE',
                     visibility ? visibility[:qualifier] + Units.meters(visibility).to_s : 'NONE', state[:category]].join(',')
    end
    errors = @errors.sort_by { |error| [error[:report], error[:position]] }.map do |error|
      "report #{error[:report]} word #{error[:position]}: #{error[:content]}"
    end
    files = {
      'decoded.txt' => block_text(@reports.map { |report| decoded(report) }),
      'categories.csv' => line_text(categories),
      'taf_timeline.txt' => block_text(@reports.select { |report| report[:kind] == 'TAF' }.map { |report| timeline(report) }),
      'verification.txt' => block_text(@settings['VERIFY'].map { |code| verification(@stations.fetch(code)) }),
      'errors.txt' => line_text(errors)
    }
    Dir.mkdir('output') unless Dir.exist?('output')
    files.each { |file, text| File.binwrite('output/' + file, text) }
  end

  private

  def read_lines(file)
    File.readlines('input/' + file, chomp: true, encoding: Encoding::US_ASCII)
  end

  def line_text(lines) = lines.empty? ? '' : lines.join("\n") + "\n"
  def block_text(blocks) = blocks.empty? ? '' : blocks.map { |lines| lines.join("\n") }.join("\n\n") + "\n"

  def read_reports
    reports = []
    read_lines('reports.txt').each do |line|
      words = line.lstrip.split(' ')
      if line.start_with?(' ')
        reports[-1].concat(words)
      else
        reports << words
      end
    end
    reports
  end

  def reject_report(number, position, reason, word = nil)
    content = 'rejected report, ' + reason
    content += ' "' + word + '"' if word
    @errors << {report: number, position:, content:}
    nil
  end

  def header(words, number)
    kind = words[0]
    return reject_report(number, 1, 'invalid type', kind) unless %w[METAR SPECI TAF].include?(kind)
    index = 1
    modifier = nil
    if kind == 'TAF' && %w[AMD COR].include?(words[index])
      modifier = words[index]
      index += 1
    end
    report = {number:, kind:, modifier:}
    required = kind == 'TAF' ? %i[station time validity] : %i[station time]
    required.each do |item|
      return reject_report(number, words.length + 1, "missing #{item}") if index == words.length
      word = words[index]
      value = case item
              when :station then @stations[word]
              when :time then @calendar.report_time(word)
              when :validity then @calendar.period(word, report[:issue_day], 1800)
              end
      return reject_report(number, index + 1, "invalid #{item}", word) if value.nil?
      if item == :validity
        report[:start], report[:end] = value
      else
        report[item] = value
        report[:issue_day] = value.div(1440) + 1 if item == :time
      end
      index += 1
    end
    report[:groups] = join_groups(words, index)
    report
  end

  def join_groups(words, index)
    groups = []
    while index < words.length
      text = words[index]
      position = index + 1
      if /\A\d\z/.match?(text) && words[index + 1] && /\A\d\/\d{1,2}SM\z/.match?(words[index + 1])
        text += ' ' + words[index + 1]
        index += 2
      else
        index += 1
      end
      groups << {text:, position:}
    end
    groups
  end

  def group_error(report, group, reason)
    @errors << {report: report[:number], position: group[:position], content: reason + ' "' + group[:text] + '"'}
  end

  def match_section(groups, slots, report, change = false)
    state = Taf::ELEMENTS.to_h { |element| [element, nil] }
    slots.each { |kind, _repeatable| state[kind] = nil }
    recognize = slots.equal?(Metar::SLOTS) ? Metar.method(:slot_value) : Groups.method(:recognize)
    current = 0
    groups.each do |group|
      found = nil
      value = nil
      (current...slots.length).each do |index|
        candidate = recognize.call(slots[index][0], group[:text])
        next unless candidate
        found = index
        value = candidate
        break
      end
      if found.nil?
        earlier = slots.take(current).any? { |kind, _repeatable| recognize.call(kind, group[:text]) }
        group_error(report, group, earlier ? 'out of order group' : 'unknown group')
        next
      end
      kind, repeatable = slots[found]
      unless Groups.valid?(kind, value, state, report[:station], change)
        group_error(report, group, 'invalid group')
        next
      end
      Groups.record(state, kind, value, repeatable)
      current = repeatable ? found : found + 1
      if kind == :visibility && value[:kind] == :cavok
        state[:weather] = []
        state[:cloud] = []
        current = slots.index { |slot| slot[0] == :cloud } + 1
      end
    end
    state
  end

  def decode_metar(report)
    parts = Metar.split(report[:groups]) { |group, reason| group_error(report, group, reason) }
    report[:state] = match_section(parts[:main], Metar::SLOTS, report)
    describe_state(report[:state])
    report[:trends] = parts[:trends].map do |trend|
      trend.merge(state: match_section(trend[:groups], Taf::SLOTS, report, true))
    end
    report[:remarks] = parts[:remarks]
    derive_observation(report)
    code = report[:station][:code]
    report[:speci] = speci_check(@previous[code], report) if report[:kind] == 'SPECI'
    @previous[code] = report
  end

  def decode_taf(report)
    parts = Taf.split(report[:groups], report, @calendar) { |group, reason| group_error(report, group, reason) }
    report[:base] = match_section(parts[:base], Taf::SLOTS, report)
    report[:changes] = parts[:changes].map do |change|
      change.merge(state: match_section(change[:groups], Taf::SLOTS, report, true))
    end
    report[:hours] = Taf.expand(report) { |state| describe_state(state) }
  end

  def describe_state(state)
    cloud = (state[:cloud] || []).find { |item| %w[BKN OVC VV].include?(item[:amount]) }
    ceiling = cloud && cloud[:height]
    visibility = state[:visibility] && Units.miles(state[:visibility])
    state[:ceiling] = ceiling
    state[:category] = if (ceiling && ceiling < 500) || (visibility && visibility < 1)
                         'LIFR'
                       elsif (ceiling && ceiling < 1000) || (visibility && visibility < 3)
                         'IFR'
                       elsif (ceiling && ceiling <= 3000) || (visibility && visibility <= 5)
                         'MVFR'
                       else
                         'VFR'
                       end
  end

  def components(speed, direction, heading)
    angle = direction - heading
    [(speed * Units.cos(angle)).div(1000), (speed * Units.sin(angle)).div(1000)]
  end

  def derive_observation(report)
    state = report[:state]
    pressure = state[:pressure]
    temperature = state[:temperature]
    if pressure
      altitude = report[:station][:elevation] + (2992 - pressure[:inhg]) * 10
      report[:pressure_altitude] = altitude
      if temperature
        report[:density_altitude] = altitude + (120 * (1000 * temperature[:temperature] - 15_000 + 2 * altitude)).div(1000)
      end
    end
    wind = state[:wind]
    return unless wind && wind[:direction] != 'VRB' && wind[:direction] != 0
    report[:components] = report[:station][:runways].map do |runway|
      mean = components(wind[:speed], wind[:direction], runway[:heading])
      gust = wind[:gust] && components(wind[:gust], wind[:direction], runway[:heading])
      deciding = gust || mean
      usable = deciding[1].abs <= @settings['CROSSWIND_LIMIT'] && -deciding[0] <= @settings['TAILWIND_LIMIT']
      {name: runway[:name], mean:, gust:, usable:}
    end
    report[:usable] = report[:components].select { |runway| runway[:usable] }
    preferred = nil
    report[:usable].each do |runway|
      preferred = runway if preferred.nil? || runway[:mean][0] > preferred[:mean][0]
    end
    report[:preferred] = preferred && preferred[:name]
  end

  def wind_changes(earlier, later, angle)
    return [] unless earlier && later
    reasons = []
    directions = [earlier[:direction], later[:direction]]
    unless directions.any? { |direction| direction == 'VRB' || direction == 0 }
      difference = (directions[0] - directions[1]).abs % 360
      difference = [difference, 360 - difference].min
      reasons << 'wind shift' if [earlier[:speed], later[:speed]].max >= 10 && difference >= angle
    end
    reasons << 'wind speed' if (earlier[:speed] - later[:speed]).abs >= 10
    reasons
  end

  def weather_present?(state, type)
    (state[:weather] || []).any? do |weather|
      if type == :thunderstorm
        weather[:descriptor] == 'TS'
      else
        weather[:descriptor] == 'FZ' && (weather[:phenomena].include?('DZ') || weather[:phenomena].include?('RA'))
      end
    end
  end

  def speci_check(previous, report)
    return 'no previous report' unless previous
    earlier, later = previous[:state], report[:state]
    reasons = []
    reasons << "category #{earlier[:category]} to #{later[:category]}" if earlier[:category] != later[:category]
    reasons.concat(wind_changes(earlier[:wind], later[:wind], 45))
    {thunderstorm: 'thunderstorm', freezing: 'freezing precipitation'}.each do |type, text|
      before, after = weather_present?(earlier, type), weather_present?(later, type)
      reasons << text + (after ? ' began' : ' ended') if before != after
    end
    reasons.empty? ? 'no criteria met' : reasons.join(', ')
  end

  def wind_phrase(wind)
    return 'calm' if wind[:direction] == 0
    text = wind[:direction] == 'VRB' ? "variable at #{wind[:speed]} KT" : format('%03d degrees at %d KT', wind[:direction], wind[:speed])
    text += " gusting #{wind[:gust]} KT" if wind[:gust]
    text
  end

  def visibility_number(visibility)
    return visibility[:whole].to_s unless visibility[:fraction]
    fraction = "#{visibility[:numerator]}/#{visibility[:denominator]}"
    visibility[:whole].zero? ? fraction : "#{visibility[:whole]} #{fraction}"
  end

  def visibility_phrase(visibility)
    return '10 km or more (CAVOK)' if visibility[:kind] == :cavok
    if visibility[:kind] == :meters
      return visibility[:value] == 10_000 ? '10 km or more' : "#{visibility[:value]} m"
    end
    {'M' => 'less than ', 'P' => 'more than '}.fetch(visibility[:qualifier], '') + visibility_number(visibility) + ' SM'
  end

  def weather_phrase(weather)
    return 'no significant weather' if weather[:nsw]
    intensity = {'-' => 'light', '+' => 'heavy', 'VC' => 'nearby'}[weather[:intensity]]
    descriptor = Groups::DESCRIPTORS[weather[:descriptor]]
    phenomena = weather[:phenomena].map { |code| Groups::PHENOMENA.fetch(code) }.join(' and ')
    [intensity, descriptor, phenomena].compact.reject(&:empty?).join(' ')
  end

  def cloud_phrase(cloud)
    return Groups::CLEAR[cloud[:amount]] if Groups::CLEAR.key?(cloud[:amount])
    return "vertical visibility #{cloud[:height]} ft" if cloud[:amount] == 'VV'
    text = "#{Groups::AMOUNTS.fetch(cloud[:amount])} at #{cloud[:height]} ft"
    text += ' cumulonimbus' if cloud[:extra] == 'CB'
    text += ' towering cumulus' if cloud[:extra] == 'TCU'
    text
  end

  def summary(state)
    parts = []
    parts << 'wind ' + wind_phrase(state[:wind]) if state[:wind]
    parts << 'visibility ' + visibility_phrase(state[:visibility]) if state[:visibility]
    parts << 'weather ' + state[:weather].map { |weather| weather_phrase(weather) }.join(', ') if state[:weather] && !state[:weather].empty?
    parts << 'cloud ' + state[:cloud].map { |cloud| cloud_phrase(cloud) }.join(', ') if state[:cloud] && !state[:cloud].empty?
    parts.empty? ? 'no conditions' : parts.join('; ')
  end

  def wind_code(wind)
    return '00000KT' if wind[:direction] == 0
    direction = wind[:direction] == 'VRB' ? 'VRB' : format('%03d', wind[:direction])
    direction + format('%02d', wind[:speed]) + (wind[:gust] ? format('G%02d', wind[:gust]) : '') + 'KT'
  end

  def visibility_code(visibility)
    return 'CAVOK' if visibility[:kind] == :cavok
    return format('%04d', visibility[:value] == 10_000 ? 9999 : visibility[:value]) if visibility[:kind] == :meters
    visibility[:qualifier] + visibility_number(visibility) + 'SM'
  end

  def cloud_code(cloud)
    return cloud[:amount] if Groups::CLEAR.key?(cloud[:amount])
    cloud[:amount] + format('%03d', cloud[:height] / 100) + cloud[:extra].to_s
  end

  def tokens(state)
    words = []
    words << wind_code(state[:wind]) if state[:wind]
    words << visibility_code(state[:visibility]) if state[:visibility]
    (state[:weather] || []).each { |weather| words << weather[:raw] unless weather[:nsw] }
    (state[:cloud] || []).each { |cloud| words << cloud_code(cloud) }
    words << state[:category]
    words.join(' ')
  end

  def tenths(value)
    (value.negative? ? '-' : '') + "#{value.abs / 10}.#{value.abs % 10}"
  end

  def inhg_text(value) = format('%d.%02d', value / 100, value % 100)

  def component_phrase(values)
    head, cross = values
    text = head.negative? ? "tailwind #{-head} KT" : "headwind #{head} KT"
    text += if cross.positive?
              ", crosswind #{cross} KT from right"
            elsif cross.negative?
              ", crosswind #{-cross} KT from left"
            else
              ', crosswind 0 KT'
            end
    text
  end

  def rvr_phrase(value)
    readings = value[:readings].map do |qualifier, number|
      {'M' => 'less than ', 'P' => 'more than '}.fetch(qualifier, '') + number.to_s
    end
    text = "runway #{value[:runway]} " + (readings.length == 1 ? readings[0] : "between #{readings[0]} and #{readings[1]}")
    text += ' ' + value[:unit]
    text += ', ' + {'U' => 'rising', 'D' => 'falling', 'N' => 'no change'}.fetch(value[:trend]) if value[:trend]
    text
  end

  def decoded(report)
    lines = ["REPORT #{report[:number]}: #{report[:kind]} #{report[:station][:code]} (#{report[:station][:name]})"]
    details = report[:kind] == 'TAF' ? decoded_taf(report) : decoded_metar(report)
    lines + details.map { |line| '  ' + line }
  end

  def decoded_taf(report)
    lines = ['issued: ' + @calendar.stamp(report[:time])]
    lines << 'modifier: ' + (report[:modifier] == 'AMD' ? 'amended' : 'corrected') if report[:modifier]
    lines << "valid: #{@calendar.stamp(report[:start])} to #{@calendar.stamp(report[:end])}"
    lines << 'base: ' + summary(report[:base])
    report[:changes].each do |change|
      period = if change[:kind] == 'FM'
                 @calendar.stamp(change[:time])
               else
                 "#{@calendar.stamp(change[:start])} to #{@calendar.stamp(change[:end])}"
               end
      lines << "#{change[:kind]} #{period}: #{summary(change[:state])}"
    end
    lines
  end

  def decoded_metar(report)
    state = report[:state]
    lines = ['time: ' + @calendar.stamp(report[:time])]
    lines << 'modifier: ' + (state[:modifier][:code] == 'AUTO' ? 'automated' : 'corrected') if state[:modifier]
    wind = state[:wind] ? wind_phrase(state[:wind]) : 'not reported'
    if state[:variation]
      wind += format(', varying between %03d and %03d degrees', state[:variation][:first], state[:variation][:last])
    end
    lines << 'wind: ' + wind
    lines << 'visibility: ' + (state[:visibility] ? visibility_phrase(state[:visibility]) : 'not reported')
    (state[:rvr] || []).each { |rvr| lines << 'runway visual range: ' + rvr_phrase(rvr) }
    (state[:weather] || []).each { |weather| lines << 'weather: ' + weather_phrase(weather) }
    if state[:visibility] && state[:visibility][:kind] == :cavok
      lines << 'cloud: no significant cloud'
    elsif state[:cloud].nil?
      lines << 'cloud: not reported'
    else
      state[:cloud].each { |cloud| lines << 'cloud: ' + cloud_phrase(cloud) }
    end
    temperature = state[:temperature]
    lines << if temperature
               "temperature: #{temperature[:temperature]} C, dew point #{temperature[:dew]} C, spread #{temperature[:temperature] - temperature[:dew]} C"
             else
               'temperature: not reported'
             end
    pressure = state[:pressure]
    lines << if pressure.nil?
               'altimeter: not reported'
             elsif pressure[:unit] == 'A'
               "altimeter: #{inhg_text(pressure[:inhg])} inHg (#{pressure[:hpa]} hPa)"
             else
               "altimeter: #{pressure[:hpa]} hPa (#{inhg_text(pressure[:inhg])} inHg)"
             end
    lines << 'trend: no significant change' if state[:nosig]
    report[:trends].each do |trend|
      text = trend[:kind] == 'BECMG' ? 'becoming' : 'temporarily'
      trend[:times].each do |time|
        text += ' ' + {'FM' => 'from', 'TL' => 'until', 'AT' => 'at'}.fetch(time[:kind]) + format(' %02d:%02dZ', time[:hour], time[:minute])
      end
      lines << 'trend: ' + text + ': ' + summary(trend[:state])
    end
    report[:remarks][:sea_levels].each { |value| lines << 'sea level pressure: ' + tenths(value) + ' hPa' }
    report[:remarks][:temperatures].each do |value, dew|
      lines << "precise temperature: #{tenths(value)} C, dew point #{tenths(dew)} C"
    end
    lines << 'ceiling: ' + (state[:ceiling] ? "#{state[:ceiling]} ft" : 'none')
    lines << 'flight category: ' + state[:category]
    lines << 'pressure altitude: ' + (report[:pressure_altitude] ? "#{report[:pressure_altitude]} ft" : 'not available')
    lines << 'density altitude: ' + (report[:density_altitude] ? "#{report[:density_altitude]} ft" : 'not available')
    if report[:components]
      report[:components].each do |runway|
        text = "runway #{runway[:name]}: #{component_phrase(runway[:mean])}"
        text += '; gusts ' + component_phrase(runway[:gust]) if runway[:gust]
        lines << text
      end
      usable = report[:usable].map { |runway| runway[:name] }
      lines << 'usable runways: ' + (usable.empty? ? 'none' : usable.join(' '))
      lines << 'preferred runway: ' + (report[:preferred] || 'none')
    else
      lines << 'runway wind: not computed'
    end
    lines << 'speci check: ' + report[:speci] if report[:kind] == 'SPECI'
    lines
  end

  def category_counts(states)
    CATEGORIES.map { |category| "#{category} #{states.count { |state| state[:category] == category }}" }.join(', ')
  end

  def timeline(report)
    lines = ["TAF #{report[:station][:code]} issued #{@calendar.stamp(report[:time])} valid #{@calendar.stamp(report[:start])} to #{@calendar.stamp(report[:end])}"]
    report[:hours].each do |hour, states|
      text = @calendar.stamp(hour) + ' ' + tokens(states[:state])
      states[:temporary].each { |change| text += " | #{change[:kind]} #{tokens(change[:state])}" }
      lines << text
    end
    lines << 'summary: ' + category_counts(report[:hours].values.map { |states| states[:state] })
    lines
  end

  def extreme(observations, maximum = false)
    chosen = nil
    chosen_value = nil
    observations.each do |observation|
      value = yield observation
      next if value.nil?
      if chosen.nil? || (maximum ? value > chosen_value : value < chosen_value)
        chosen = observation
        chosen_value = value
      end
    end
    chosen
  end

  def extreme_line(label, report)
    return label + ': not available' unless report
    label + ': ' + yield(report) + ' at ' + @calendar.stamp(report[:time])
  end

  def table_lines(result)
    row = ->(name, values) { name.ljust(8) + values.map { |value| value.to_s.rjust(6) }.join }
    lines = [row.call('forecast', CATEGORIES + ['total'])]
    CATEGORIES.each_with_index { |category, index| lines << row.call(category, result[:table][index] + [result[:rows][index]]) }
    lines << row.call('total', result[:columns] + [result[:total]])
    lines
  end

  def forecast_buckets(observations, forecasts)
    buckets = Array.new(5) { [0, 0] }
    forecasts.each do |forecast|
      observations.each do |observation|
        next unless Verification.covers?(forecast, observation)
        hour = observation[:time] - observation[:time] % 60
        bucket = (hour - forecast[:start]).div(360)
        buckets[bucket][1] += 1
        buckets[bucket][0] += 1 if forecast[:hours][hour][:state][:category] == observation[:state][:category]
      end
    end
    buckets
  end

  def amendments(selected)
    selected.filter_map do |choice|
      observation = choice[:observation]
      actual = observation[:state]
      forecast = choice[:states][:state]
      reasons = []
      reasons << "category #{actual[:category]}, forecast #{forecast[:category]}" unless choice[:possible].include?(actual[:category])
      unless wind_changes(forecast[:wind], actual[:wind], 60).empty?
        reasons << "wind #{wind_code(actual[:wind])}, forecast #{wind_code(forecast[:wind])}"
      end
      "amendment #{@calendar.stamp(observation[:time])}: #{reasons.join('; ')}" unless reasons.empty?
    end
  end

  def verification(station)
    reports = @reports.select { |report| report[:station][:code] == station[:code] }
    observations, forecasts = reports.partition { |report| report[:kind] != 'TAF' }
    result = Verification.compare(observations, forecasts)
    low_temperature = extreme(observations) { |report| report[:state][:temperature]&.fetch(:temperature) }
    high_temperature = extreme(observations, true) { |report| report[:state][:temperature]&.fetch(:temperature) }
    strongest = extreme(observations, true) { |report| report[:state][:wind] && (report[:state][:wind][:gust] || report[:state][:wind][:speed]) }
    low_ceiling = extreme(observations) { |report| report[:state][:ceiling] }
    low_visibility = extreme(observations) { |report| report[:state][:visibility] && Units.miles(report[:state][:visibility]) }
    lines = ["station #{station[:code]} (#{station[:name]})"]
    lines << "reports: METAR #{observations.count { |report| report[:kind] == 'METAR' }}, SPECI #{observations.count { |report| report[:kind] == 'SPECI' }}"
    lines << 'observed categories: ' + category_counts(observations.map { |report| report[:state] })
    lines << extreme_line('lowest temperature', low_temperature) { |report| "#{report[:state][:temperature][:temperature]} C" }
    lines << extreme_line('highest temperature', high_temperature) { |report| "#{report[:state][:temperature][:temperature]} C" }
    lines << extreme_line('strongest wind', strongest) { |report| wind_phrase(report[:state][:wind]) }
    lines << extreme_line('lowest ceiling', low_ceiling) { |report| "#{report[:state][:ceiling]} ft" }
    lines << extreme_line('lowest visibility', low_visibility) { |report| visibility_phrase(report[:state][:visibility]) }
    lines << "verified: #{result[:total]}"
    lines << "no forecast: #{result[:no_forecast]}"
    lines.concat(table_lines(result))
    lines << 'hit rate: ' + Units.fraction(result[:hits], result[:total])
    lines << 'hit rate with temporary groups: ' + Units.fraction(result[:temporary_hits], result[:total])
    lines << 'heidke skill score: ' + Units.fraction(*result[:skill])
    CATEGORIES.each_with_index do |category, index|
      lines << "#{category}: pod #{Units.fraction(*result[:pod][index])}, far #{Units.fraction(*result[:far][index])}"
    end
    forecast_buckets(observations, forecasts).each_with_index do |values, index|
      lines << "hours #{index * 6}-#{index * 6 + 5}: #{Units.fraction(*values)}"
    end
    lines.concat(amendments(result[:selected]))
    lines
  end
end

WeatherDecoder.new.run
