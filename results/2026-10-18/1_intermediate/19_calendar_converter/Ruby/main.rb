CALENDARS = %w[GREGORIAN JULIAN ISO ISLAMIC HEBREW PERSIAN COPTIC ETHIOPIC FRENCH MAYAN JD FIXED].freeze
YMD = (CALENDARS - %w[ISO MAYAN JD FIXED]).freeze
YEAR_CALENDARS = (YMD + ['ISO']).freeze
WEEKDAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
TZ = %w[Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau].freeze
HB = %w[Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb].freeze
DC = %w[Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi].freeze
FS = %w[Vertu Genie Travail Opinion Recompenses Revolution].freeze
MAX_FIXED = 3652059
MONTH_NAMES = {
  'GREGORIAN' => %w[January February March April May June July August September October November December],
  'JULIAN' => %w[January February March April May June July August September October November December],
  'ISLAMIC' => %w[Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah],
  'HEBREW' => %w[Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul],
  'PERSIAN' => %w[Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand],
  'COPTIC' => %w[Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie],
  'ETHIOPIC' => %w[Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume],
  'FRENCH' => %w[Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor
                 Fructidor Sansculottides]
}.freeze
HEBREW_LEAP_NAMES = %w[Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul].freeze

class DateError < StandardError; end
class CommandError < StandardError; end

def validate(condition)
  raise CommandError unless condition
end

def in_range?(fixed)
  fixed.between?(1, MAX_FIXED)
end

def leap?(calendar, year)
  case calendar
  when 'GREGORIAN' then (year % 4).zero? && (year % 100 != 0 || (year % 400).zero?)
  when 'JULIAN' then (year % 4).zero?
  when 'ISLAMIC' then [2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29].include?(year % 30)
  when 'HEBREW' then (7 * year + 1) % 19 < 7
  when 'PERSIAN'
    b = (year - 474) % 2820 + 474
    (b + 38) * 682 % 2816 < 682
  when 'COPTIC', 'ETHIOPIC' then year % 4 == 3
  when 'FRENCH' then (year % 4).zero? && ![100, 200, 300].include?(year % 400) && year % 4000 != 0
  else (start('ISO', year + 1) - start('ISO', year)) / 7 == 53
  end
end

def months_before(year)
  (235 * year - 234) / 19
end

def molad(year)
  quantity = 5604 + 765433 * months_before(year)
  day, parts = quantity.divmod(25920)
  weekday = (day - 1373427) % 7
  rules = []
  postponed = day
  if parts >= 19440
    postponed += 1
    rules << 'ZAKEN'
  elsif !leap?('HEBREW', year) && weekday == 2 && parts >= 9924
    postponed += 2
    rules << 'GATARAD'
  elsif leap?('HEBREW', year - 1) && weekday == 1 && parts >= 16789
    postponed += 1
    rules << 'BETUTAKPAT'
  end
  if [0, 3, 5].include?((postponed - 1373427) % 7)
    postponed += 1
    rules << 'ADU'
  end
  [day, parts, postponed - 1373427, rules]
end

def start(calendar, year)
  previous = year - 1
  case calendar
  when 'GREGORIAN' then 365 * previous + previous / 4 - previous / 100 + previous / 400 + 1
  when 'JULIAN' then 365 * previous + previous / 4 - 1
  when 'ISLAMIC' then 227015 + 354 * previous + (3 + 11 * year) / 30
  when 'HEBREW' then molad(year)[2]
  when 'PERSIAN'
    a = year - 474
    b = a % 2820 + 474
    226896 + 1029983 * (a / 2820) + 365 * (b - 1) + (682 * b - 110) / 2816
  when 'COPTIC' then 103605 + 365 * previous + year / 4
  when 'ETHIOPIC' then 2796 + 365 * previous + year / 4
  when 'FRENCH'
    654415 + 365 * previous + previous / 4 - previous / 100 + previous / 400 - previous / 4000
  else
    january_four = start('GREGORIAN', year) + 3
    january_four - (january_four - 1) % 7
  end
end

def year_type(year)
  case start('HEBREW', year + 1) - start('HEBREW', year)
  when 353, 383 then 'DEFICIENT'
  when 354, 384 then 'REGULAR'
  else 'COMPLETE'
  end
end

def names(calendar, year)
  calendar == 'HEBREW' && leap?(calendar, year) ? HEBREW_LEAP_NAMES : MONTH_NAMES[calendar]
end

def lengths(calendar, year)
  leap = leap?(calendar, year)
  extra = leap ? 1 : 0
  case calendar
  when 'GREGORIAN', 'JULIAN' then [31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  when 'ISLAMIC' then [30, 29] * 5 + [30, 29 + extra]
  when 'PERSIAN' then [31] * 6 + [30] * 5 + [29 + extra]
  when 'COPTIC', 'ETHIOPIC', 'FRENCH' then [30] * 12 + [5 + extra]
  else
    kind = year_type(year)
    heshvan = kind == 'COMPLETE' ? 30 : 29
    kislev = kind == 'DEFICIENT' ? 29 : 30
    if leap
      [30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29]
    else
      [30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29]
    end
  end
end

def fixed_date(calendar, year, month, day)
  return start(calendar, year) + 7 * (month - 1) + day - 1 if calendar == 'ISO'
  start(calendar, year) + lengths(calendar, year).take(month - 1).sum + day - 1
end

def year_of(calendar, fixed)
  return 0 if fixed < start(calendar, 1)
  (1..100000).bsearch { |year| start(calendar, year) > fixed } - 1
end

def parts_of(calendar, fixed)
  year = year_of(calendar, fixed)
  return nil if year.zero?
  offset = fixed - start(calendar, year)
  return [year, offset / 7 + 1, offset % 7 + 1] if calendar == 'ISO'
  lengths(calendar, year).each.with_index(1) do |days, month|
    return [year, month, offset + 1] if offset < days
    offset -= days
  end
  raise 'calendar year length'
end

def format_date(calendar, fixed)
  return 'OUT OF RANGE' unless in_range?(fixed)
  if YEAR_CALENDARS.include?(calendar)
    parts = parts_of(calendar, fixed)
    return 'OUT OF RANGE' if parts.nil?
    return format('%04d-W%02d-%d', *parts) if calendar == 'ISO'
    return format('%04d-%02d-%02d', *parts)
  end
  return (fixed + 1721425).to_s if calendar == 'JD'
  return fixed.to_s if calendar == 'FIXED'
  count = fixed + 1137142
  long_count = [count / 144000, count / 7200 % 20, count / 360 % 20, count / 20 % 18, count % 20]
  tz_number = (count + 3) % 13 + 1
  tz_name = TZ[(count + 19) % 20]
  haab = (count + 348) % 365
  "#{long_count.join('.')} #{tz_number} #{tz_name} #{haab % 20} #{HB[haab / 20]}"
end

def parse_date(calendar, text)
  if YMD.include?(calendar)
    raise DateError, 'FORMAT' unless text.match?(/\A[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}\z/)
    year, month, day = text.split('-').map(&:to_i)
    raise DateError, 'YEAR' if year.zero?
    days = lengths(calendar, year)
    raise DateError, 'MONTH' unless month.between?(1, days.length)
    raise DateError, 'DAY' unless day.between?(1, days[month - 1])
    fixed = fixed_date(calendar, year, month, day)
  elsif calendar == 'ISO'
    raise DateError, 'FORMAT' unless text.match?(/\A[0-9]{1,5}-W[0-9]{1,2}-[0-9]\z/)
    year_text, week_text, day_text = text.split('-')
    year = year_text.to_i
    week = week_text[1..].to_i
    day = day_text.to_i
    raise DateError, 'YEAR' if year.zero?
    weeks = (start(calendar, year + 1) - start(calendar, year)) / 7
    raise DateError, 'WEEK' unless week.between?(1, weeks)
    raise DateError, 'DAY' unless day.between?(1, 7)
    fixed = fixed_date(calendar, year, week, day)
  elsif calendar == 'MAYAN'
    raise DateError, 'FORMAT' unless text.match?(/\A[0-9]{1,2}(?:\.[0-9]{1,2}){4}\z/)
    b, k, t, u, n = text.split('.').map(&:to_i)
    raise DateError, 'FIELD' if k > 19 || t > 19 || u > 17 || n > 19
    fixed = (((b * 20 + k) * 20 + t) * 18 + u) * 20 + n - 1137142
  else
    raise DateError, 'FORMAT' unless text.match?(/\A-?[0-9]{1,8}\z/)
    fixed = text.to_i - (calendar == 'JD' ? 1721425 : 0)
  end
  raise DateError, 'RANGE' unless in_range?(fixed)
  fixed
end

def month_index(calendar, year)
  return months_before(year) if calendar == 'HEBREW'
  count = %w[COPTIC ETHIOPIC FRENCH].include?(calendar) ? 13 : 12
  count * (year - 1)
end

def shift(calendar, fixed, years, months)
  year, month, day = parts_of(calendar, fixed)
  target_year = year + years
  if calendar == 'ISO'
    return nil unless target_year.between?(1, 99999)
    weeks = (start(calendar, target_year + 1) - start(calendar, target_year)) / 7
    return fixed_date(calendar, target_year, [month, weeks].min, day)
  end
  if calendar == 'HEBREW'
    old_name = names(calendar, year)[month - 1]
    new_names = names(calendar, target_year)
    old_name = old_name == 'Adar' ? 'AdarII' : 'Adar' unless new_names.include?(old_name)
    month = new_names.index(old_name) + 1
  end
  absolute = month_index(calendar, target_year) + month - 1 + months
  if calendar == 'HEBREW'
    final_year = (19 * absolute + 234) / 235
    final_year -= 1 while month_index(calendar, final_year) > absolute
    final_year += 1 while month_index(calendar, final_year + 1) <= absolute
  else
    final_year = absolute / names(calendar, target_year).length + 1
  end
  return nil unless final_year.between?(1, 99999)
  final_month = absolute - month_index(calendar, final_year) + 1
  final_day = [day, lengths(calendar, final_year)[final_month - 1]].min
  fixed_date(calendar, final_year, final_month, final_day)
end

def month_bounds(calendar, year, month)
  days = lengths(calendar, year)
  raise DateError, 'MONTH' unless month.between?(1, days.length)
  first = fixed_date(calendar, year, month, 1)
  [first, first + days[month - 1] - 1]
end

def new_years(calendar, first, last)
  year = [1, year_of(calendar, first)].max
  year += 1 while start(calendar, year) < first
  result = []
  while start(calendar, year) <= last
    result << [year, start(calendar, year)]
    year += 1
  end
  result
end

def easter(year, calendar)
  golden = year % 19
  if calendar == 'GREGORIAN'
    century = year / 100 + 1
    epact = (14 + 11 * golden - 3 * century / 4 + (5 + 8 * century) / 25) % 30
    epact += 1 if epact.zero? || (epact == 1 && golden > 10)
  else
    epact = (14 + 11 * golden) % 30
  end
  moon = fixed_date(calendar, year, 4, 19) - epact
  sunday = moon + 7 - moon % 7
  index = -start(calendar, year) % 7
  letters = 'ABCDEFG'[index]
  letters += 'ABCDEFG'[(index - 1) % 7] if leap?(calendar, year)
  [epact, letters, moon, sunday]
end

HOLIDAYS = [
  ['Christmas', 'GREGORIAN', 'December', 25],
  ['OrthodoxChristmas', 'JULIAN', 'December', 25],
  ['RoshHashanah', 'HEBREW', 'Tishri', 1],
  ['YomKippur', 'HEBREW', 'Tishri', 10],
  ['Sukkot', 'HEBREW', 'Tishri', 15],
  ['Hanukkah', 'HEBREW', 'Kislev', 25],
  ['Purim', 'HEBREW', 'Adar', 14],
  ['Passover', 'HEBREW', 'Nisan', 15],
  ['Shavuot', 'HEBREW', 'Sivan', 6],
  ['IslamicNewYear', 'ISLAMIC', 'Muharram', 1],
  ['Ashura', 'ISLAMIC', 'Muharram', 10],
  ['Mawlid', 'ISLAMIC', 'RabiI', 12],
  ['RamadanStart', 'ISLAMIC', 'Ramadan', 1],
  ['EidAlFitr', 'ISLAMIC', 'Shawwal', 1],
  ['EidAlAdha', 'ISLAMIC', 'DhuAlHijjah', 10],
  ['Nowruz', 'PERSIAN', 'Farvardin', 1],
  ['SizdahBedar', 'PERSIAN', 'Farvardin', 13],
  ['Yalda', 'PERSIAN', 'Azar', 30],
  ['Nayrouz', 'COPTIC', 'Thout', 1],
  ['CopticChristmas', 'COPTIC', 'Koiak', 29],
  ['Enkutatash', 'ETHIOPIC', 'Meskerem', 1],
  ['Meskel', 'ETHIOPIC', 'Meskerem', 17],
  ['Timkat', 'ETHIOPIC', 'Ter', 11],
  ['RepublicDay', 'FRENCH', 'Vendemiaire', 1],
  ['RevolutionDay', 'FRENCH', 'Sansculottides', 6]
].freeze

def holiday_lines(year)
  first = start('GREGORIAN', year)
  last = start('GREGORIAN', year + 1) - 1
  gregorian_easter = easter(year, 'GREGORIAN')[3]
  orthodox_easter = easter(year, 'JULIAN')[3]
  movable = [['AshWednesday', -46], ['GoodFriday', -2], ['Easter', 0], ['Ascension', 39], ['Pentecost', 49]]
  entries = movable.each_with_index.map do |(name, offset), order|
    [gregorian_easter + offset, order, name, 'GREGORIAN']
  end
  entries << [orthodox_easter, 5, 'OrthodoxEaster', 'JULIAN']
  HOLIDAYS.each.with_index(6) do |(name, calendar, month_name, day), order|
    candidate_year = [1, year_of(calendar, first)].max
    while start(calendar, candidate_year) <= last
      actual_name = month_name
      actual_name = 'AdarII' if calendar == 'HEBREW' && month_name == 'Adar' && leap?(calendar, candidate_year)
      month = names(calendar, candidate_year).index(actual_name) + 1
      if day <= lengths(calendar, candidate_year)[month - 1]
        fixed = fixed_date(calendar, candidate_year, month, day)
        entries << [fixed, order, name, calendar] if fixed.between?(first, last)
      end
      candidate_year += 1
    end
  end
  entries.sort_by { |fixed, order| [fixed, order] }.map do |fixed, _, name, calendar|
    "#{format_date('GREGORIAN', fixed)} #{WEEKDAYS[fixed % 7]} #{name} #{calendar} #{format_date(calendar, fixed)}"
  end
end

ARITY = {
  'CONVERT' => 4, 'ALL' => 2, 'VALID' => 2, 'WEEKDAY' => 2, 'INFO' => 2,
  'LEAP' => 2, 'MONTHS' => 2, 'MONTHCAL' => 3, 'NTH' => 5, 'NEWYEAR' => 2,
  'DIFF' => 4, 'COUNT' => 4, 'ADD' => 4, 'SPAN' => 3, 'EASTER' => 2,
  'COMPUTUS' => 2, 'PASSOVER' => 1, 'HOLIDAYS' => 1, 'MOLAD' => 1, 'ROUND' => 6
}.freeze

def valid_year?(text)
  text.match?(/\A[0-9]{1,5}\z/) && text.to_i >= 1
end

def validate_arguments(command, args)
  case command
  when 'EASTER', 'COMPUTUS'
    validate(valid_year?(args[0]) && %w[GREGORIAN JULIAN].include?(args[1]))
    return
  when 'PASSOVER', 'HOLIDAYS', 'MOLAD'
    validate(valid_year?(args[0]))
    return
  end
  calendar = args[0]
  allowed = case command
            when 'INFO', 'MONTHS', 'MONTHCAL', 'NTH', 'SPAN' then YMD
            when 'LEAP', 'NEWYEAR' then YEAR_CALENDARS
            else CALENDARS
            end
  validate(allowed.include?(calendar))
  case command
  when 'CONVERT'
    validate(args[2] == 'TO' && CALENDARS.include?(args[3]))
  when 'DIFF'
    validate(CALENDARS.include?(args[2]))
  when 'LEAP', 'MONTHS', 'MONTHCAL', 'NTH', 'NEWYEAR'
    validate(valid_year?(args[1]))
    validate(args[2].match?(/\A[0-9]{1,2}\z/)) if %w[MONTHCAL NTH].include?(command)
    if command == 'NTH'
      validate(%w[1 2 3 4 5 LAST].include?(args[3]))
      validate(WEEKDAYS.include?(args[4]))
    end
  when 'COUNT'
    validate(WEEKDAYS.include?(args[3]))
  when 'ADD'
    validate(args[2].match?(/\A-?[0-9]{1,7}\z/))
    validate(%w[DAYS WEEKS MONTHS YEARS].include?(args[3]))
    validate(YMD.include?(calendar)) if args[3] == 'MONTHS'
    validate(YEAR_CALENDARS.include?(calendar)) if args[3] == 'YEARS'
  when 'ROUND'
    validate(args[2].match?(/\A[0-9]{1,2}\z/))
    validate(args[2].to_i.between?(1, 13) && TZ.include?(args[3]))
    validate(args[4].match?(/\A[0-9]{1,2}\z/))
    validate(HB.include?(args[5]))
    validate(args[4].to_i <= (args[5] == 'Uayeb' ? 4 : 19))
  end
end

def calendar_lines(calendar, year, month)
  first, last = month_bounds(calendar, year, month)
  return ['OUT OF RANGE'] unless in_range?(first) && in_range?(last)
  title = "#{names(calendar, year)[month - 1]} #{year} " \
          "(#{format_date('GREGORIAN', first)} to #{format_date('GREGORIAN', last)})"
  result = [title, 'Mo Tu We Th Fr Sa Su']
  (first - (first - 1) % 7).step(last, 7) do |cursor|
    fields = (cursor...cursor + 7).map do |fixed|
      fixed.between?(first, last) ? format('%2d', fixed - first + 1) : '  '
    end
    result << fields.join(' ').rstrip
  end
  result
end

def span_text(calendar, first, last)
  negative = first > last
  first, last = last, first if negative
  start_year = parts_of(calendar, first)[0]
  end_year = parts_of(calendar, last)[0]
  beyond = lambda do |years, months|
    shifted = shift(calendar, first, years, months)
    shifted.nil? || shifted > last
  end
  years = (1..end_year - start_year + 1).bsearch { |count| beyond.call(count, 0) } - 1
  months = (1..31).bsearch { |count| beyond.call(years, count) } - 1
  days = last - shift(calendar, first, years, months)
  "#{negative ? '-' : ''}#{years}y #{months}m #{days}d"
end

def round_date(calendar, fixed, number, tz_name, day, month)
  target_tz = TZ.index(tz_name)
  target_haab = HB.index(month) * 20 + day
  first_match = (fixed..).find do |candidate|
    count = candidate + 1137142
    (count + 3) % 13 + 1 == number && (count + 19) % 20 == target_tz
  end
  first_match.step(fixed + 18979, 260) do |candidate|
    return format_date(calendar, candidate) if (candidate + 1137142 + 348) % 365 == target_haab
  end
  'NONE'
end

def execute(command, args)
  validate_arguments(command, args)
  if %w[EASTER COMPUTUS].include?(command)
    year = args[0].to_i
    return ['OUT OF RANGE'] if year > 9999
    kind = args[1]
    epact, letters, moon, sunday = easter(year, kind)
    return [format_date('GREGORIAN', sunday)] if command == 'EASTER'
    return ["golden=#{year % 19 + 1} epact=#{epact} letters=#{letters} " \
            "moon=#{format_date(kind, moon)} easter=#{format_date(kind, sunday)}"]
  end
  if %w[PASSOVER HOLIDAYS MOLAD].include?(command)
    year = args[0].to_i
    if command == 'MOLAD'
      day, parts, fixed, rules = molad(year)
      return ['OUT OF RANGE'] unless in_range?(fixed)
      applied = rules.empty? ? 'NONE' : rules.join('+')
      return ["#{WEEKDAYS[(day - 1373427) % 7]} #{parts / 1080}h #{parts % 1080}p #{applied} " \
              "#{WEEKDAYS[fixed % 7]} #{format_date('GREGORIAN', fixed)}"]
    end
    return ['OUT OF RANGE'] if year > 9999
    return holiday_lines(year) if command == 'HOLIDAYS'
    hebrew_year = year + 3760
    month = names('HEBREW', hebrew_year).index('Nisan') + 1
    fixed = fixed_date('HEBREW', hebrew_year, month, 15)
    return ["#{format_date('GREGORIAN', fixed)} #{WEEKDAYS[fixed % 7]}"]
  end
  calendar = args[0]
  if %w[LEAP MONTHS MONTHCAL NTH NEWYEAR].include?(command)
    year = args[1].to_i
    case command
    when 'LEAP'
      text = "#{leap?(calendar, year) ? 'YES' : 'NO'} #{start(calendar, year + 1) - start(calendar, year)}"
      text += " #{year_type(year)}" if calendar == 'HEBREW'
      return [text]
    when 'MONTHS'
      return [names(calendar, year).zip(lengths(calendar, year)).map { |name, days| "#{name}=#{days}" }.join(' ')]
    when 'NEWYEAR'
      return ['OUT OF RANGE'] if year > 9999
      entries = new_years(calendar, start('GREGORIAN', year), start('GREGORIAN', year + 1) - 1)
      return ['NONE'] if entries.empty?
      return [entries.map { |new_year, fixed| "#{new_year}:#{format_date('GREGORIAN', fixed)}" }.join(' ')]
    end
    month = args[2].to_i
    return calendar_lines(calendar, year, month) if command == 'MONTHCAL'
    first, last = month_bounds(calendar, year, month)
    weekday = WEEKDAYS.index(args[4])
    fixed = if args[3] == 'LAST'
              last - (last - weekday) % 7
            else
              first + (weekday - first) % 7 + 7 * (args[3].to_i - 1)
            end
    return [fixed > last ? 'NONE' : format_date(calendar, fixed)]
  end
  if command == 'VALID'
    begin
      fixed = parse_date(calendar, args[1])
    rescue DateError => error
      return ["NO #{error.message}"]
    end
    return ["YES #{format_date(calendar, fixed)}"]
  end
  first = parse_date(calendar, args[1])
  case command
  when 'DIFF'
    [(parse_date(args[2], args[3]) - first).to_s]
  when 'COUNT', 'SPAN'
    last = parse_date(calendar, args[2])
    return [span_text(calendar, first, last)] if command == 'SPAN'
    low, high = [first, last].minmax
    occurrence = low + (WEEKDAYS.index(args[3]) - low) % 7
    [(occurrence > high ? 0 : (high - occurrence) / 7 + 1).to_s]
  when 'CONVERT'
    [format_date(args[3], first)]
  when 'WEEKDAY'
    [WEEKDAYS[first % 7]]
  when 'ALL'
    CALENDARS.map do |target|
      text = format_date(target, first)
      if YMD.include?(target) && text != 'OUT OF RANGE'
        year, month = parts_of(target, first)
        text += " #{names(target, year)[month - 1]}"
      end
      "#{target} #{text}"
    end
  when 'INFO'
    year, month, day = parts_of(calendar, first)
    weekday = WEEKDAYS[first % 7]
    weekday = month <= 12 ? DC[(day - 1) % 10] : FS[day - 1] if calendar == 'FRENCH'
    ordinal = first - start(calendar, year) + 1
    length = start(calendar, year + 1) - start(calendar, year)
    ["#{weekday} #{day} #{names(calendar, year)[month - 1]} #{year} day=#{ordinal}/#{length}"]
  when 'ROUND'
    [round_date(calendar, first, args[2].to_i, args[3], args[4].to_i, args[5])]
  else
    amount = args[2].to_i
    result = case args[3]
             when 'DAYS' then first + amount
             when 'WEEKS' then first + 7 * amount
             when 'YEARS' then shift(calendar, first, amount, 0)
             else shift(calendar, first, 0, amount)
             end
    [result.nil? ? 'OUT OF RANGE' : format_date(calendar, result)]
  end
end

output = []
STDIN.gets.to_i.times do
  command, *args = STDIN.gets.chomp.split(' ')
  unless ARITY.key?(command) && args.length == ARITY[command]
    output << 'INVALID COMMAND'
    next
  end
  begin
    output.concat(execute(command, args))
  rescue CommandError
    output << 'INVALID COMMAND'
  rescue DateError => error
    output << (error.message == 'RANGE' ? 'OUT OF RANGE' : 'INVALID DATE')
  end
end
STDOUT.write(output.join("\n") + "\n")
