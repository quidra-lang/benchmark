import 'dart:io';
import 'dart:math' as math;

enum Calendar {
  gregorian, julian, iso, islamic, hebrew, persian, coptic, ethiopic, french, mayan, jd, fixed;

  String get label => name.toUpperCase();
}

typedef Parts = ({int year, int month, int day});
typedef Molad = ({int day, int parts, int start, List<String> rules});
typedef Easter = ({int epact, String letters, int moon, int sunday});
typedef Entry = ({int fixed, int order, String name, Calendar calendar});

class DateError implements Exception {
  final String reason;
  DateError(this.reason);
}

class CommandError implements Exception {}

final ymd = Calendar.values.toSet().difference({Calendar.iso, Calendar.mayan, Calendar.jd, Calendar.fixed});
final yearCalendars = {...ymd, Calendar.iso};
final weekdays = 'Sunday Monday Tuesday Wednesday Thursday Friday Saturday'.split(' ');
final tzolkinNames = 'Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau'.split(' ');
final haabNames = 'Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb'.split(' ');
final decadeNames = 'Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi'.split(' ');
final festivalNames = 'Vertu Genie Travail Opinion Recompenses Revolution'.split(' ');
const maxFixed = 3652059;
final romanMonths = 'January February March April May June July August September October November December'.split(' ');
final monthNames = {
  Calendar.gregorian: romanMonths,
  Calendar.julian: romanMonths,
  Calendar.islamic: 'Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah'.split(' '),
  Calendar.hebrew: 'Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul'.split(' '),
  Calendar.persian: 'Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand'.split(' '),
  Calendar.coptic: 'Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie'.split(' '),
  Calendar.ethiopic: 'Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume'.split(' '),
  Calendar.french: 'Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides'.split(' '),
};
final hebrewLeapNames = 'Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul'.split(' ');
const holidays = [
  ('Christmas', Calendar.gregorian, 'December', 25),
  ('OrthodoxChristmas', Calendar.julian, 'December', 25),
  ('RoshHashanah', Calendar.hebrew, 'Tishri', 1),
  ('YomKippur', Calendar.hebrew, 'Tishri', 10),
  ('Sukkot', Calendar.hebrew, 'Tishri', 15),
  ('Hanukkah', Calendar.hebrew, 'Kislev', 25),
  ('Purim', Calendar.hebrew, 'Adar', 14),
  ('Passover', Calendar.hebrew, 'Nisan', 15),
  ('Shavuot', Calendar.hebrew, 'Sivan', 6),
  ('IslamicNewYear', Calendar.islamic, 'Muharram', 1),
  ('Ashura', Calendar.islamic, 'Muharram', 10),
  ('Mawlid', Calendar.islamic, 'RabiI', 12),
  ('RamadanStart', Calendar.islamic, 'Ramadan', 1),
  ('EidAlFitr', Calendar.islamic, 'Shawwal', 1),
  ('EidAlAdha', Calendar.islamic, 'DhuAlHijjah', 10),
  ('Nowruz', Calendar.persian, 'Farvardin', 1),
  ('SizdahBedar', Calendar.persian, 'Farvardin', 13),
  ('Yalda', Calendar.persian, 'Azar', 30),
  ('Nayrouz', Calendar.coptic, 'Thout', 1),
  ('CopticChristmas', Calendar.coptic, 'Koiak', 29),
  ('Enkutatash', Calendar.ethiopic, 'Meskerem', 1),
  ('Meskel', Calendar.ethiopic, 'Meskerem', 17),
  ('Timkat', Calendar.ethiopic, 'Ter', 11),
  ('RepublicDay', Calendar.french, 'Vendemiaire', 1),
  ('RevolutionDay', Calendar.french, 'Sansculottides', 6),
];
const arity = {
  'CONVERT': 4, 'ALL': 2, 'VALID': 2, 'WEEKDAY': 2, 'INFO': 2,
  'LEAP': 2, 'MONTHS': 2, 'MONTHCAL': 3, 'NTH': 5, 'NEWYEAR': 2,
  'DIFF': 4, 'COUNT': 4, 'ADD': 4, 'SPAN': 3, 'EASTER': 2,
  'COMPUTUS': 2, 'PASSOVER': 1, 'HOLIDAYS': 1, 'MOLAD': 1, 'ROUND': 6,
};

void ensure(bool condition) {
  if (!condition) throw CommandError();
}

int floorDiv(int value, int divisor) => (value - value % divisor) ~/ divisor;

String padded(int value, int width) => '$value'.padLeft(width, '0');

bool inRange(int fixed) => fixed >= 1 && fixed <= maxFixed;

String weekdayName(int fixed) => weekdays[fixed % 7];

Calendar calendarNamed(String text) => Calendar.values.firstWhere((calendar) => calendar.label == text);

bool leap(Calendar calendar, int year) => switch (calendar) {
  Calendar.gregorian => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0),
  Calendar.julian => year % 4 == 0,
  Calendar.islamic => const {2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29}.contains(year % 30),
  Calendar.hebrew => (7 * year + 1) % 19 < 7,
  Calendar.persian => ((year - 474) % 2820 + 474 + 38) * 682 % 2816 < 682,
  Calendar.coptic || Calendar.ethiopic => year % 4 == 3,
  Calendar.french => year % 4 == 0 && !const {100, 200, 300}.contains(year % 400) && year % 4000 != 0,
  Calendar.iso => weeks(year) == 53,
  _ => throw ArgumentError('no years in ${calendar.label}'),
};

int weeks(int year) => (start(Calendar.iso, year + 1) - start(Calendar.iso, year)) ~/ 7;

int monthsBefore(int year) => floorDiv(235 * year - 234, 19);

Molad molad(int year) {
  final quantity = 5604 + 765433 * monthsBefore(year);
  final day = floorDiv(quantity, 25920), parts = quantity % 25920;
  final weekday = (day - 1373427) % 7;
  final rules = <String>[];
  var postponed = day;
  if (parts >= 19440) {
    postponed += 1;
    rules.add('ZAKEN');
  } else if (!leap(Calendar.hebrew, year) && weekday == 2 && parts >= 9924) {
    postponed += 2;
    rules.add('GATARAD');
  } else if (leap(Calendar.hebrew, year - 1) && weekday == 1 && parts >= 16789) {
    postponed += 1;
    rules.add('BETUTAKPAT');
  }
  if (const {0, 3, 5}.contains((postponed - 1373427) % 7)) {
    postponed += 1;
    rules.add('ADU');
  }
  return (day: day, parts: parts, start: postponed - 1373427, rules: rules);
}

int start(Calendar calendar, int year) {
  final previous = year - 1;
  switch (calendar) {
    case Calendar.gregorian:
      return 365 * previous + previous ~/ 4 - previous ~/ 100 + previous ~/ 400 + 1;
    case Calendar.julian:
      return 365 * previous + previous ~/ 4 - 1;
    case Calendar.islamic:
      return 227015 + 354 * previous + (3 + 11 * year) ~/ 30;
    case Calendar.hebrew:
      return molad(year).start;
    case Calendar.persian:
      final a = year - 474;
      final b = a % 2820 + 474;
      return 226896 + 1029983 * floorDiv(a, 2820) + 365 * (b - 1) + (682 * b - 110) ~/ 2816;
    case Calendar.coptic:
      return 103605 + 365 * previous + year ~/ 4;
    case Calendar.ethiopic:
      return 2796 + 365 * previous + year ~/ 4;
    case Calendar.french:
      return 654415 + 365 * previous + previous ~/ 4 - previous ~/ 100 + previous ~/ 400 - previous ~/ 4000;
    case Calendar.iso:
      final januaryFour = start(Calendar.gregorian, year) + 3;
      return januaryFour - (januaryFour - 1) % 7;
    default:
      throw ArgumentError('no years in ${calendar.label}');
  }
}

String yearType(int year) => switch (start(Calendar.hebrew, year + 1) - start(Calendar.hebrew, year)) {
  353 || 383 => 'DEFICIENT',
  354 || 384 => 'REGULAR',
  _ => 'COMPLETE',
};

List<String> names(Calendar calendar, int year) =>
    calendar == Calendar.hebrew && leap(calendar, year) ? hebrewLeapNames : monthNames[calendar]!;

List<int> lengths(Calendar calendar, int year) {
  final extra = leap(calendar, year) ? 1 : 0;
  switch (calendar) {
    case Calendar.gregorian || Calendar.julian:
      return [31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    case Calendar.islamic:
      return [30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra];
    case Calendar.persian:
      return [...List.filled(6, 31), ...List.filled(5, 30), 29 + extra];
    case Calendar.coptic || Calendar.ethiopic || Calendar.french:
      return [...List.filled(12, 30), 5 + extra];
    case Calendar.hebrew:
      final kind = yearType(year);
      final heshvan = kind == 'COMPLETE' ? 30 : 29, kislev = kind == 'DEFICIENT' ? 29 : 30;
      if (extra == 1) return [30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29];
      return [30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29];
    default:
      throw ArgumentError('no months in ${calendar.label}');
  }
}

int fixedDate(Calendar calendar, int year, int month, int day) {
  if (calendar == Calendar.iso) return start(calendar, year) + 7 * (month - 1) + day - 1;
  return start(calendar, year) + lengths(calendar, year).take(month - 1).fold<int>(0, (sum, days) => sum + days) + day - 1;
}

int yearOf(Calendar calendar, int fixed) {
  if (fixed < start(calendar, 1)) return 0;
  var low = 1, high = 100000;
  while (low + 1 < high) {
    final middle = (low + high) ~/ 2;
    if (start(calendar, middle) <= fixed) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return low;
}

Parts? partsOf(Calendar calendar, int fixed) {
  final year = yearOf(calendar, fixed);
  if (year == 0) return null;
  var offset = fixed - start(calendar, year);
  if (calendar == Calendar.iso) return (year: year, month: offset ~/ 7 + 1, day: offset % 7 + 1);
  final days = lengths(calendar, year);
  var month = 0;
  while (offset >= days[month]) {
    offset -= days[month];
    month++;
  }
  return (year: year, month: month + 1, day: offset + 1);
}

String formatDate(Calendar calendar, int fixed) {
  if (!inRange(fixed)) return 'OUT OF RANGE';
  if (yearCalendars.contains(calendar)) {
    final parts = partsOf(calendar, fixed);
    if (parts == null) return 'OUT OF RANGE';
    final (:year, :month, :day) = parts;
    if (calendar == Calendar.iso) return '${padded(year, 4)}-W${padded(month, 2)}-$day';
    return '${padded(year, 4)}-${padded(month, 2)}-${padded(day, 2)}';
  }
  if (calendar == Calendar.jd) return '${fixed + 1721425}';
  if (calendar == Calendar.fixed) return '$fixed';
  final count = fixed + 1137142;
  final longCount = [count ~/ 144000, count ~/ 7200 % 20, count ~/ 360 % 20, count ~/ 20 % 18, count % 20].join('.');
  final haab = (count + 348) % 365;
  return '$longCount ${(count + 3) % 13 + 1} ${tzolkinNames[(count + 19) % 20]} ${haab % 20} ${haabNames[haab ~/ 20]}';
}

int parseDate(Calendar calendar, String text) {
  final int fixed;
  if (ymd.contains(calendar)) {
    if (!RegExp(r'^[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}$').hasMatch(text)) throw DateError('FORMAT');
    final [year, month, day] = text.split('-').map(int.parse).toList();
    if (year == 0) throw DateError('YEAR');
    final days = lengths(calendar, year);
    if (month < 1 || month > days.length) throw DateError('MONTH');
    if (day < 1 || day > days[month - 1]) throw DateError('DAY');
    fixed = fixedDate(calendar, year, month, day);
  } else if (calendar == Calendar.iso) {
    if (!RegExp(r'^[0-9]{1,5}-W[0-9]{1,2}-[0-9]$').hasMatch(text)) throw DateError('FORMAT');
    final [yearText, weekText, dayText] = text.split('-');
    final year = int.parse(yearText), week = int.parse(weekText.substring(1)), day = int.parse(dayText);
    if (year == 0) throw DateError('YEAR');
    if (week < 1 || week > weeks(year)) throw DateError('WEEK');
    if (day < 1 || day > 7) throw DateError('DAY');
    fixed = fixedDate(calendar, year, week, day);
  } else if (calendar == Calendar.mayan) {
    if (!RegExp(r'^[0-9]{1,2}(?:\.[0-9]{1,2}){4}$').hasMatch(text)) throw DateError('FORMAT');
    final [b, k, t, u, n] = text.split('.').map(int.parse).toList();
    if (k > 19 || t > 19 || u > 17 || n > 19) throw DateError('FIELD');
    fixed = (((b * 20 + k) * 20 + t) * 18 + u) * 20 + n - 1137142;
  } else {
    if (!RegExp(r'^-?[0-9]{1,8}$').hasMatch(text)) throw DateError('FORMAT');
    fixed = int.parse(text) - (calendar == Calendar.jd ? 1721425 : 0);
  }
  if (!inRange(fixed)) throw DateError('RANGE');
  return fixed;
}

int monthIndex(Calendar calendar, int year) =>
    calendar == Calendar.hebrew ? monthsBefore(year) : monthNames[calendar]!.length * (year - 1);

int? shift(Calendar calendar, int fixed, int years, int months) {
  final (:year, :month, :day) = partsOf(calendar, fixed)!;
  final targetYear = year + years;
  if (calendar == Calendar.iso) {
    if (targetYear < 1 || targetYear > 99999) return null;
    return fixedDate(calendar, targetYear, math.min(month, weeks(targetYear)), day);
  }
  var targetMonth = month;
  if (calendar == Calendar.hebrew) {
    var name = names(calendar, year)[month - 1];
    final newNames = names(calendar, targetYear);
    if (!newNames.contains(name)) name = name == 'Adar' ? 'AdarII' : 'Adar';
    targetMonth = newNames.indexOf(name) + 1;
  }
  final absolute = monthIndex(calendar, targetYear) + targetMonth - 1 + months;
  int finalYear;
  if (calendar == Calendar.hebrew) {
    finalYear = floorDiv(19 * absolute + 234, 235);
    while (monthIndex(calendar, finalYear) > absolute) {
      finalYear--;
    }
    while (monthIndex(calendar, finalYear + 1) <= absolute) {
      finalYear++;
    }
  } else {
    finalYear = floorDiv(absolute, monthNames[calendar]!.length) + 1;
  }
  if (finalYear < 1 || finalYear > 99999) return null;
  final finalMonth = absolute - monthIndex(calendar, finalYear) + 1;
  final finalDay = math.min(day, lengths(calendar, finalYear)[finalMonth - 1]);
  return fixedDate(calendar, finalYear, finalMonth, finalDay);
}

({int first, int last}) monthBounds(Calendar calendar, int year, int month) {
  final days = lengths(calendar, year);
  if (month < 1 || month > days.length) throw DateError('MONTH');
  final first = fixedDate(calendar, year, month, 1);
  return (first: first, last: first + days[month - 1] - 1);
}

List<(int, int)> newYears(Calendar calendar, int first, int last) {
  var year = math.max(1, yearOf(calendar, first));
  while (start(calendar, year) < first) {
    year++;
  }
  final result = <(int, int)>[];
  for (; start(calendar, year) <= last; year++) {
    result.add((year, start(calendar, year)));
  }
  return result;
}

Easter easter(int year, Calendar calendar) {
  final golden = year % 19;
  int epact;
  if (calendar == Calendar.gregorian) {
    final century = year ~/ 100 + 1;
    epact = (14 + 11 * golden - 3 * century ~/ 4 + (5 + 8 * century) ~/ 25) % 30;
    if (epact == 0 || epact == 1 && golden > 10) epact++;
  } else {
    epact = (14 + 11 * golden) % 30;
  }
  final moon = fixedDate(calendar, year, 4, 19) - epact;
  final sunday = moon + 7 - moon % 7;
  final index = -start(calendar, year) % 7;
  var letters = 'ABCDEFG'[index];
  if (leap(calendar, year)) letters += 'ABCDEFG'[(index - 1) % 7];
  return (epact: epact, letters: letters, moon: moon, sunday: sunday);
}

List<String> holidayLines(int year) {
  final first = start(Calendar.gregorian, year), last = start(Calendar.gregorian, year + 1) - 1;
  final gregorianEaster = easter(year, Calendar.gregorian).sunday;
  final orthodoxEaster = easter(year, Calendar.julian).sunday;
  const movable = [('AshWednesday', -46), ('GoodFriday', -2), ('Easter', 0), ('Ascension', 39), ('Pentecost', 49)];
  final entries = <Entry>[
    for (final (order, (name, offset)) in movable.indexed)
      (fixed: gregorianEaster + offset, order: order, name: name, calendar: Calendar.gregorian),
    (fixed: orthodoxEaster, order: 5, name: 'OrthodoxEaster', calendar: Calendar.julian),
  ];
  for (final (index, (name, calendar, monthName, day)) in holidays.indexed) {
    for (var candidateYear = math.max(1, yearOf(calendar, first)); start(calendar, candidateYear) <= last; candidateYear++) {
      var actualName = monthName;
      if (calendar == Calendar.hebrew && monthName == 'Adar' && leap(calendar, candidateYear)) actualName = 'AdarII';
      final month = names(calendar, candidateYear).indexOf(actualName) + 1;
      if (day <= lengths(calendar, candidateYear)[month - 1]) {
        final fixed = fixedDate(calendar, candidateYear, month, day);
        if (first <= fixed && fixed <= last) entries.add((fixed: fixed, order: index + 6, name: name, calendar: calendar));
      }
    }
  }
  entries.sort((a, b) => a.fixed != b.fixed ? a.fixed.compareTo(b.fixed) : a.order.compareTo(b.order));
  return [
    for (final entry in entries)
      '${formatDate(Calendar.gregorian, entry.fixed)} ${weekdayName(entry.fixed)} ${entry.name} '
          '${entry.calendar.label} ${formatDate(entry.calendar, entry.fixed)}',
  ];
}

bool validYear(String text) => RegExp(r'^[0-9]{1,5}$').hasMatch(text) && int.parse(text) >= 1;

bool isCalendar(String text, Iterable<Calendar> allowed) => allowed.any((calendar) => calendar.label == text);

void validateArguments(String command, List<String> args) {
  if (command == 'EASTER' || command == 'COMPUTUS') {
    ensure(validYear(args[0]) && (args[1] == 'GREGORIAN' || args[1] == 'JULIAN'));
    return;
  }
  if (const {'PASSOVER', 'HOLIDAYS', 'MOLAD'}.contains(command)) {
    ensure(validYear(args[0]));
    return;
  }
  final allowed = switch (command) {
    'INFO' || 'MONTHS' || 'MONTHCAL' || 'NTH' || 'SPAN' => ymd,
    'LEAP' || 'NEWYEAR' => yearCalendars,
    _ => Calendar.values,
  };
  ensure(isCalendar(args[0], allowed));
  switch (command) {
    case 'CONVERT':
      ensure(args[2] == 'TO' && isCalendar(args[3], Calendar.values));
    case 'DIFF':
      ensure(isCalendar(args[2], Calendar.values));
    case 'LEAP' || 'MONTHS' || 'MONTHCAL' || 'NTH' || 'NEWYEAR':
      ensure(validYear(args[1]));
      if (command == 'MONTHCAL' || command == 'NTH') ensure(RegExp(r'^[0-9]{1,2}$').hasMatch(args[2]));
      if (command == 'NTH') {
        ensure(const {'1', '2', '3', '4', '5', 'LAST'}.contains(args[3]));
        ensure(weekdays.contains(args[4]));
      }
    case 'COUNT':
      ensure(weekdays.contains(args[3]));
    case 'ADD':
      ensure(RegExp(r'^-?[0-9]{1,7}$').hasMatch(args[2]));
      ensure(const {'DAYS', 'WEEKS', 'MONTHS', 'YEARS'}.contains(args[3]));
      final calendar = calendarNamed(args[0]);
      if (args[3] == 'MONTHS') ensure(ymd.contains(calendar));
      if (args[3] == 'YEARS') ensure(yearCalendars.contains(calendar));
    case 'ROUND':
      ensure(RegExp(r'^[0-9]{1,2}$').hasMatch(args[2]));
      final number = int.parse(args[2]);
      ensure(number >= 1 && number <= 13 && tzolkinNames.contains(args[3]));
      ensure(RegExp(r'^[0-9]{1,2}$').hasMatch(args[4]));
      ensure(haabNames.contains(args[5]));
      ensure(int.parse(args[4]) <= (args[5] == 'Uayeb' ? 4 : 19));
  }
}

List<String> calendarLines(Calendar calendar, int year, int month) {
  final (:first, :last) = monthBounds(calendar, year, month);
  if (!inRange(first) || !inRange(last)) return ['OUT OF RANGE'];
  final result = [
    '${names(calendar, year)[month - 1]} $year '
        '(${formatDate(Calendar.gregorian, first)} to ${formatDate(Calendar.gregorian, last)})',
    'Mo Tu We Th Fr Sa Su',
  ];
  for (var cursor = first - (first - 1) % 7; cursor <= last; cursor += 7) {
    final fields = [
      for (var day = cursor; day < cursor + 7; day++)
        first <= day && day <= last ? '${day - first + 1}'.padLeft(2) : '  ',
    ];
    result.add(fields.join(' ').trimRight());
  }
  return result;
}

String spanText(Calendar calendar, int first, int last) {
  final from = math.min(first, last), to = math.max(first, last);
  var low = 0, high = partsOf(calendar, to)!.year - partsOf(calendar, from)!.year + 2;
  while (low + 1 < high) {
    final middle = (low + high) ~/ 2;
    final shifted = shift(calendar, from, middle, 0);
    if (shifted != null && shifted <= to) {
      low = middle;
    } else {
      high = middle;
    }
  }
  final years = low;
  low = 0;
  high = 32;
  while (low + 1 < high) {
    final middle = (low + high) ~/ 2;
    final shifted = shift(calendar, from, years, middle);
    if (shifted != null && shifted <= to) {
      low = middle;
    } else {
      high = middle;
    }
  }
  final months = low;
  final days = to - shift(calendar, from, years, months)!;
  return '${first > last ? '-' : ''}${years}y ${months}m ${days}d';
}

String roundDate(Calendar calendar, int fixed, int number, String tzName, int day, String month) {
  final targetTz = tzolkinNames.indexOf(tzName);
  final targetHaab = haabNames.indexOf(month) * 20 + day;
  var candidate = fixed;
  while ((candidate + 1137142 + 3) % 13 + 1 != number || (candidate + 1137142 + 19) % 20 != targetTz) {
    candidate++;
  }
  for (; candidate <= fixed + 18979; candidate += 260) {
    if ((candidate + 1137142 + 348) % 365 == targetHaab) return formatDate(calendar, candidate);
  }
  return 'NONE';
}

List<String> execute(String command, List<String> args) {
  validateArguments(command, args);
  if (command == 'EASTER' || command == 'COMPUTUS') {
    final year = int.parse(args[0]);
    if (year > 9999) return ['OUT OF RANGE'];
    final kind = calendarNamed(args[1]);
    final (:epact, :letters, :moon, :sunday) = easter(year, kind);
    if (command == 'EASTER') return [formatDate(Calendar.gregorian, sunday)];
    return [
      'golden=${year % 19 + 1} epact=$epact letters=$letters '
          'moon=${formatDate(kind, moon)} easter=${formatDate(kind, sunday)}',
    ];
  }
  if (const {'PASSOVER', 'HOLIDAYS', 'MOLAD'}.contains(command)) {
    final year = int.parse(args[0]);
    if (command == 'MOLAD') {
      final (:day, :parts, :start, :rules) = molad(year);
      if (!inRange(start)) return ['OUT OF RANGE'];
      final applied = rules.isEmpty ? 'NONE' : rules.join('+');
      return [
        '${weekdayName(day - 1373427)} ${parts ~/ 1080}h ${parts % 1080}p $applied '
            '${weekdayName(start)} ${formatDate(Calendar.gregorian, start)}',
      ];
    }
    if (year > 9999) return ['OUT OF RANGE'];
    if (command == 'HOLIDAYS') return holidayLines(year);
    final hebrewYear = year + 3760;
    final month = names(Calendar.hebrew, hebrewYear).indexOf('Nisan') + 1;
    final fixed = fixedDate(Calendar.hebrew, hebrewYear, month, 15);
    return ['${formatDate(Calendar.gregorian, fixed)} ${weekdayName(fixed)}'];
  }
  final calendar = calendarNamed(args[0]);
  if (const {'LEAP', 'MONTHS', 'MONTHCAL', 'NTH', 'NEWYEAR'}.contains(command)) {
    final year = int.parse(args[1]);
    switch (command) {
      case 'LEAP':
        var text = '${leap(calendar, year) ? 'YES' : 'NO'} ${start(calendar, year + 1) - start(calendar, year)}';
        if (calendar == Calendar.hebrew) text += ' ${yearType(year)}';
        return [text];
      case 'MONTHS':
        final days = lengths(calendar, year);
        return [[for (final (index, name) in names(calendar, year).indexed) '$name=${days[index]}'].join(' ')];
      case 'NEWYEAR':
        if (year > 9999) return ['OUT OF RANGE'];
        final entries = newYears(calendar, start(Calendar.gregorian, year), start(Calendar.gregorian, year + 1) - 1);
        if (entries.isEmpty) return ['NONE'];
        return [entries.map((entry) => '${entry.$1}:${formatDate(Calendar.gregorian, entry.$2)}').join(' ')];
      case 'MONTHCAL':
        return calendarLines(calendar, year, int.parse(args[2]));
      default:
        final (:first, :last) = monthBounds(calendar, year, int.parse(args[2]));
        final weekday = weekdays.indexOf(args[4]);
        final fixed = args[3] == 'LAST'
            ? last - (last - weekday) % 7
            : first + (weekday - first) % 7 + 7 * (int.parse(args[3]) - 1);
        return [fixed > last ? 'NONE' : formatDate(calendar, fixed)];
    }
  }
  if (command == 'VALID') {
    try {
      return ['YES ${formatDate(calendar, parseDate(calendar, args[1]))}'];
    } on DateError catch (error) {
      return ['NO ${error.reason}'];
    }
  }
  final first = parseDate(calendar, args[1]);
  switch (command) {
    case 'DIFF':
      return ['${parseDate(calendarNamed(args[2]), args[3]) - first}'];
    case 'COUNT':
      final last = parseDate(calendar, args[2]);
      final low = math.min(first, last), high = math.max(first, last);
      final occurrence = low + (weekdays.indexOf(args[3]) - low) % 7;
      return ['${occurrence > high ? 0 : (high - occurrence) ~/ 7 + 1}'];
    case 'SPAN':
      return [spanText(calendar, first, parseDate(calendar, args[2]))];
    case 'CONVERT':
      return [formatDate(calendarNamed(args[3]), first)];
    case 'WEEKDAY':
      return [weekdayName(first)];
    case 'ALL':
      final result = <String>[];
      for (final target in Calendar.values) {
        var text = formatDate(target, first);
        if (ymd.contains(target) && text != 'OUT OF RANGE') {
          final parts = partsOf(target, first)!;
          text += ' ${names(target, parts.year)[parts.month - 1]}';
        }
        result.add('${target.label} $text');
      }
      return result;
    case 'INFO':
      final (:year, :month, :day) = partsOf(calendar, first)!;
      var weekday = weekdayName(first);
      if (calendar == Calendar.french) weekday = month <= 12 ? decadeNames[(day - 1) % 10] : festivalNames[day - 1];
      final ordinal = first - start(calendar, year) + 1;
      final length = start(calendar, year + 1) - start(calendar, year);
      return ['$weekday $day ${names(calendar, year)[month - 1]} $year day=$ordinal/$length'];
    case 'ROUND':
      return [roundDate(calendar, first, int.parse(args[2]), args[3], int.parse(args[4]), args[5])];
    default:
      final amount = int.parse(args[2]);
      final result = switch (args[3]) {
        'DAYS' => first + amount,
        'WEEKS' => first + 7 * amount,
        'YEARS' => shift(calendar, first, amount, 0),
        _ => shift(calendar, first, 0, amount),
      };
      return [result == null ? 'OUT OF RANGE' : formatDate(calendar, result)];
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final output = StringBuffer();
  for (var i = 0; i < count; i++) {
    final words = stdin.readLineSync()!.split(' ');
    final command = words.first, args = words.sublist(1);
    List<String> lines;
    if (arity[command] != args.length) {
      lines = ['INVALID COMMAND'];
    } else {
      try {
        lines = execute(command, args);
      } on CommandError {
        lines = ['INVALID COMMAND'];
      } on DateError catch (error) {
        lines = [error.reason == 'RANGE' ? 'OUT OF RANGE' : 'INVALID DATE'];
      }
    }
    for (final line in lines) {
      output.writeln(line);
    }
  }
  stdout.write(output);
}
