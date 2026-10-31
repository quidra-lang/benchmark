import re
import sys


CALENDARS = (
    "GREGORIAN", "JULIAN", "ISO", "ISLAMIC", "HEBREW", "PERSIAN",
    "COPTIC", "ETHIOPIC", "FRENCH", "MAYAN", "JD", "FIXED",
)
YMD = set(CALENDARS) - {"ISO", "MAYAN", "JD", "FIXED"}
YEAR_CALENDARS = YMD | {"ISO"}
WEEKDAYS = "Sunday Monday Tuesday Wednesday Thursday Friday Saturday".split()
TZ = "Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau".split()
HB = "Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb".split()
DC = "Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi".split()
FS = "Vertu Genie Travail Opinion Recompenses Revolution".split()
MAX_FIXED = 3652059
MONTH_NAMES = {
    "GREGORIAN": "January February March April May June July August September October November December".split(),
    "JULIAN": "January February March April May June July August September October November December".split(),
    "ISLAMIC": "Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah".split(),
    "HEBREW": "Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul".split(),
    "PERSIAN": "Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand".split(),
    "COPTIC": "Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie".split(),
    "ETHIOPIC": "Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume".split(),
    "FRENCH": "Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides".split(),
}
HEBREW_LEAP_NAMES = "Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul".split()


class DateError(Exception):
    pass


class CommandError(Exception):
    pass


def require(condition):
    if not condition:
        raise CommandError


def in_range(fixed):
    return 1 <= fixed <= MAX_FIXED


def leap(calendar, year):
    if calendar == "GREGORIAN":
        return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
    if calendar == "JULIAN":
        return year % 4 == 0
    if calendar == "ISLAMIC":
        return year % 30 in (2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29)
    if calendar == "HEBREW":
        return (7 * year + 1) % 19 < 7
    if calendar == "PERSIAN":
        b = (year - 474) % 2820 + 474
        return ((b + 38) * 682) % 2816 < 682
    if calendar in ("COPTIC", "ETHIOPIC"):
        return year % 4 == 3
    if calendar == "FRENCH":
        return year % 4 == 0 and year % 400 not in (100, 200, 300) and year % 4000 != 0
    return (start("ISO", year + 1) - start("ISO", year)) // 7 == 53


def months_before(year):
    return (235 * year - 234) // 19


def molad(year):
    quantity = 5604 + 765433 * months_before(year)
    day, parts = divmod(quantity, 25920)
    weekday = (day - 1373427) % 7
    rules = []
    postponed = day
    if parts >= 19440:
        postponed += 1
        rules.append("ZAKEN")
    elif not leap("HEBREW", year) and weekday == 2 and parts >= 9924:
        postponed += 2
        rules.append("GATARAD")
    elif leap("HEBREW", year - 1) and weekday == 1 and parts >= 16789:
        postponed += 1
        rules.append("BETUTAKPAT")
    if (postponed - 1373427) % 7 in (0, 3, 5):
        postponed += 1
        rules.append("ADU")
    return day, parts, postponed - 1373427, rules


def start(calendar, year):
    previous = year - 1
    if calendar == "GREGORIAN":
        return 365 * previous + previous // 4 - previous // 100 + previous // 400 + 1
    if calendar == "JULIAN":
        return 365 * previous + previous // 4 - 1
    if calendar == "ISLAMIC":
        return 227015 + 354 * previous + (3 + 11 * year) // 30
    if calendar == "HEBREW":
        return molad(year)[2]
    if calendar == "PERSIAN":
        a = year - 474
        b = a % 2820 + 474
        return 226896 + 1029983 * (a // 2820) + 365 * (b - 1) + (682 * b - 110) // 2816
    if calendar == "COPTIC":
        return 103605 + 365 * previous + year // 4
    if calendar == "ETHIOPIC":
        return 2796 + 365 * previous + year // 4
    if calendar == "FRENCH":
        return 654415 + 365 * previous + previous // 4 - previous // 100 + previous // 400 - previous // 4000
    january_four = start("GREGORIAN", year) + 3
    return january_four - (january_four - 1) % 7


def year_type(year):
    length = start("HEBREW", year + 1) - start("HEBREW", year)
    if length in (353, 383):
        return "DEFICIENT"
    if length in (354, 384):
        return "REGULAR"
    return "COMPLETE"


def names(calendar, year):
    if calendar == "HEBREW" and leap(calendar, year):
        return HEBREW_LEAP_NAMES
    return MONTH_NAMES[calendar]


def lengths(calendar, year):
    extra = int(leap(calendar, year))
    if calendar in ("GREGORIAN", "JULIAN"):
        return [31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if calendar == "ISLAMIC":
        return [30, 29] * 5 + [30, 29 + extra]
    if calendar == "PERSIAN":
        return [31] * 6 + [30] * 5 + [29 + extra]
    if calendar in ("COPTIC", "ETHIOPIC", "FRENCH"):
        return [30] * 12 + [5 + extra]
    kind = year_type(year)
    heshvan = 30 if kind == "COMPLETE" else 29
    kislev = 29 if kind == "DEFICIENT" else 30
    if extra:
        return [30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29]
    return [30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29]


def fixed_date(calendar, year, month, day):
    if calendar == "ISO":
        return start(calendar, year) + 7 * (month - 1) + day - 1
    return start(calendar, year) + sum(lengths(calendar, year)[:month - 1]) + day - 1


def year_of(calendar, fixed):
    if fixed < start(calendar, 1):
        return 0
    low = 1
    high = 100000
    while low + 1 < high:
        middle = (low + high) // 2
        if start(calendar, middle) <= fixed:
            low = middle
        else:
            high = middle
    return low


def parts_of(calendar, fixed):
    year = year_of(calendar, fixed)
    if year == 0:
        return None
    offset = fixed - start(calendar, year)
    if calendar == "ISO":
        return year, offset // 7 + 1, offset % 7 + 1
    for month, days in enumerate(lengths(calendar, year), 1):
        if offset < days:
            return year, month, offset + 1
        offset -= days
    raise ValueError("calendar year length")


def format_date(calendar, fixed):
    if not in_range(fixed):
        return "OUT OF RANGE"
    if calendar in YEAR_CALENDARS:
        parts = parts_of(calendar, fixed)
        if parts is None:
            return "OUT OF RANGE"
        year, month, day = parts
        if calendar == "ISO":
            return f"{year:04d}-W{month:02d}-{day}"
        return f"{year:04d}-{month:02d}-{day:02d}"
    if calendar == "JD":
        return str(fixed + 1721425)
    if calendar == "FIXED":
        return str(fixed)
    count = fixed + 1137142
    long_count = [
        count // 144000,
        count // 7200 % 20,
        count // 360 % 20,
        count // 20 % 18,
        count % 20,
    ]
    tz_number = (count + 3) % 13 + 1
    tz_name = TZ[(count + 19) % 20]
    haab = (count + 348) % 365
    return ".".join(map(str, long_count)) + f" {tz_number} {tz_name} {haab % 20} {HB[haab // 20]}"


def parse_date(calendar, text):
    if calendar in YMD:
        if not re.fullmatch(r"[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}", text):
            raise DateError("FORMAT")
        year, month, day = map(int, text.split("-"))
        if year == 0:
            raise DateError("YEAR")
        days = lengths(calendar, year)
        if not 1 <= month <= len(days):
            raise DateError("MONTH")
        if not 1 <= day <= days[month - 1]:
            raise DateError("DAY")
        fixed = fixed_date(calendar, year, month, day)
    elif calendar == "ISO":
        if not re.fullmatch(r"[0-9]{1,5}-W[0-9]{1,2}-[0-9]", text):
            raise DateError("FORMAT")
        year_text, week_text, day_text = text.split("-")
        year, week, day = int(year_text), int(week_text[1:]), int(day_text)
        if year == 0:
            raise DateError("YEAR")
        weeks = (start(calendar, year + 1) - start(calendar, year)) // 7
        if not 1 <= week <= weeks:
            raise DateError("WEEK")
        if not 1 <= day <= 7:
            raise DateError("DAY")
        fixed = fixed_date(calendar, year, week, day)
    elif calendar == "MAYAN":
        if not re.fullmatch(r"[0-9]{1,2}(?:\.[0-9]{1,2}){4}", text):
            raise DateError("FORMAT")
        b, k, t, u, n = map(int, text.split("."))
        if k > 19 or t > 19 or u > 17 or n > 19:
            raise DateError("FIELD")
        fixed = (((b * 20 + k) * 20 + t) * 18 + u) * 20 + n - 1137142
    else:
        if not re.fullmatch(r"-?[0-9]{1,8}", text):
            raise DateError("FORMAT")
        fixed = int(text) - (1721425 if calendar == "JD" else 0)
    if not in_range(fixed):
        raise DateError("RANGE")
    return fixed


def month_index(calendar, year):
    if calendar == "HEBREW":
        return months_before(year)
    count = 13 if calendar in ("COPTIC", "ETHIOPIC", "FRENCH") else 12
    return count * (year - 1)


def shift(calendar, fixed, years, months):
    year, month, day = parts_of(calendar, fixed)
    target_year = year + years
    if calendar == "ISO":
        if not 1 <= target_year <= 99999:
            return None
        weeks = (start(calendar, target_year + 1) - start(calendar, target_year)) // 7
        return fixed_date(calendar, target_year, min(month, weeks), day)
    if calendar == "HEBREW":
        old_name = names(calendar, year)[month - 1]
        new_names = names(calendar, target_year)
        if old_name not in new_names:
            old_name = "AdarII" if old_name == "Adar" else "Adar"
        month = new_names.index(old_name) + 1
    absolute = month_index(calendar, target_year) + month - 1 + months
    if calendar == "HEBREW":
        final_year = (19 * absolute + 234) // 235
        while month_index(calendar, final_year) > absolute:
            final_year -= 1
        while month_index(calendar, final_year + 1) <= absolute:
            final_year += 1
    else:
        count = len(names(calendar, target_year))
        final_year = absolute // count + 1
    if not 1 <= final_year <= 99999:
        return None
    final_month = absolute - month_index(calendar, final_year) + 1
    final_day = min(day, lengths(calendar, final_year)[final_month - 1])
    return fixed_date(calendar, final_year, final_month, final_day)


def month_bounds(calendar, year, month):
    days = lengths(calendar, year)
    if not 1 <= month <= len(days):
        raise DateError("MONTH")
    first = fixed_date(calendar, year, month, 1)
    return first, first + days[month - 1] - 1


def new_years(calendar, first, last):
    year = max(1, year_of(calendar, first))
    while start(calendar, year) < first:
        year += 1
    result = []
    while start(calendar, year) <= last:
        result.append((year, start(calendar, year)))
        year += 1
    return result


def easter(year, calendar):
    golden = year % 19
    if calendar == "GREGORIAN":
        century = year // 100 + 1
        epact = (14 + 11 * golden - 3 * century // 4 + (5 + 8 * century) // 25) % 30
        if epact == 0 or (epact == 1 and golden > 10):
            epact += 1
    else:
        epact = (14 + 11 * golden) % 30
    moon = fixed_date(calendar, year, 4, 19) - epact
    sunday = moon + 7 - moon % 7
    index = -start(calendar, year) % 7
    letters = "ABCDEFG"[index]
    if leap(calendar, year):
        letters += "ABCDEFG"[(index - 1) % 7]
    return epact, letters, moon, sunday


HOLIDAYS = [
    ("Christmas", "GREGORIAN", "December", 25),
    ("OrthodoxChristmas", "JULIAN", "December", 25),
    ("RoshHashanah", "HEBREW", "Tishri", 1),
    ("YomKippur", "HEBREW", "Tishri", 10),
    ("Sukkot", "HEBREW", "Tishri", 15),
    ("Hanukkah", "HEBREW", "Kislev", 25),
    ("Purim", "HEBREW", "Adar", 14),
    ("Passover", "HEBREW", "Nisan", 15),
    ("Shavuot", "HEBREW", "Sivan", 6),
    ("IslamicNewYear", "ISLAMIC", "Muharram", 1),
    ("Ashura", "ISLAMIC", "Muharram", 10),
    ("Mawlid", "ISLAMIC", "RabiI", 12),
    ("RamadanStart", "ISLAMIC", "Ramadan", 1),
    ("EidAlFitr", "ISLAMIC", "Shawwal", 1),
    ("EidAlAdha", "ISLAMIC", "DhuAlHijjah", 10),
    ("Nowruz", "PERSIAN", "Farvardin", 1),
    ("SizdahBedar", "PERSIAN", "Farvardin", 13),
    ("Yalda", "PERSIAN", "Azar", 30),
    ("Nayrouz", "COPTIC", "Thout", 1),
    ("CopticChristmas", "COPTIC", "Koiak", 29),
    ("Enkutatash", "ETHIOPIC", "Meskerem", 1),
    ("Meskel", "ETHIOPIC", "Meskerem", 17),
    ("Timkat", "ETHIOPIC", "Ter", 11),
    ("RepublicDay", "FRENCH", "Vendemiaire", 1),
    ("RevolutionDay", "FRENCH", "Sansculottides", 6),
]


def holiday_lines(year):
    first = start("GREGORIAN", year)
    last = start("GREGORIAN", year + 1) - 1
    gregorian_easter = easter(year, "GREGORIAN")[3]
    orthodox_easter = easter(year, "JULIAN")[3]
    entries = []
    movable = [
        ("AshWednesday", -46), ("GoodFriday", -2), ("Easter", 0),
        ("Ascension", 39), ("Pentecost", 49),
    ]
    for order, (name, offset) in enumerate(movable):
        entries.append((gregorian_easter + offset, order, name, "GREGORIAN"))
    entries.append((orthodox_easter, 5, "OrthodoxEaster", "JULIAN"))
    for order, (name, calendar, month_name, day) in enumerate(HOLIDAYS, 6):
        candidate_year = max(1, year_of(calendar, first))
        while start(calendar, candidate_year) <= last:
            month_names = names(calendar, candidate_year)
            actual_name = month_name
            if calendar == "HEBREW" and month_name == "Adar" and leap(calendar, candidate_year):
                actual_name = "AdarII"
            month = month_names.index(actual_name) + 1
            if day <= lengths(calendar, candidate_year)[month - 1]:
                fixed = fixed_date(calendar, candidate_year, month, day)
                if first <= fixed <= last:
                    entries.append((fixed, order, name, calendar))
            candidate_year += 1
    entries.sort(key=lambda entry: (entry[0], entry[1]))
    return [
        f"{format_date('GREGORIAN', fixed)} {WEEKDAYS[fixed % 7]} "
        f"{name} {calendar} {format_date(calendar, fixed)}"
        for fixed, _, name, calendar in entries
    ]


ARITY = {
    "CONVERT": 4, "ALL": 2, "VALID": 2, "WEEKDAY": 2, "INFO": 2,
    "LEAP": 2, "MONTHS": 2, "MONTHCAL": 3, "NTH": 5, "NEWYEAR": 2,
    "DIFF": 4, "COUNT": 4, "ADD": 4, "SPAN": 3, "EASTER": 2,
    "COMPUTUS": 2, "PASSOVER": 1, "HOLIDAYS": 1, "MOLAD": 1, "ROUND": 6,
}


def valid_year(text):
    return re.fullmatch(r"[0-9]{1,5}", text) is not None and int(text) >= 1


def validate_arguments(command, args):
    if command in ("EASTER", "COMPUTUS"):
        require(valid_year(args[0]) and args[1] in ("GREGORIAN", "JULIAN"))
        return
    if command in ("PASSOVER", "HOLIDAYS", "MOLAD"):
        require(valid_year(args[0]))
        return
    calendar = args[0]
    allowed = CALENDARS
    if command in ("INFO", "MONTHS", "MONTHCAL", "NTH", "SPAN"):
        allowed = YMD
    elif command in ("LEAP", "NEWYEAR"):
        allowed = YEAR_CALENDARS
    require(calendar in allowed)
    if command == "CONVERT":
        require(args[2] == "TO" and args[3] in CALENDARS)
    elif command == "DIFF":
        require(args[2] in CALENDARS)
    elif command in ("LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR"):
        require(valid_year(args[1]))
        if command in ("MONTHCAL", "NTH"):
            require(re.fullmatch(r"[0-9]{1,2}", args[2]) is not None)
        if command == "NTH":
            require(args[3] in ("1", "2", "3", "4", "5", "LAST"))
            require(args[4] in WEEKDAYS)
    elif command == "COUNT":
        require(args[3] in WEEKDAYS)
    elif command == "ADD":
        require(re.fullmatch(r"-?[0-9]{1,7}", args[2]) is not None)
        require(args[3] in ("DAYS", "WEEKS", "MONTHS", "YEARS"))
        if args[3] == "MONTHS":
            require(calendar in YMD)
        if args[3] == "YEARS":
            require(calendar in YEAR_CALENDARS)
    elif command == "ROUND":
        require(re.fullmatch(r"[0-9]{1,2}", args[2]) is not None)
        require(1 <= int(args[2]) <= 13 and args[3] in TZ)
        require(re.fullmatch(r"[0-9]{1,2}", args[4]) is not None)
        require(args[5] in HB)
        require(int(args[4]) <= (4 if args[5] == "Uayeb" else 19))


def calendar_lines(calendar, year, month):
    first, last = month_bounds(calendar, year, month)
    if not in_range(first) or not in_range(last):
        return ["OUT OF RANGE"]
    title = f"{names(calendar, year)[month - 1]} {year} "
    title += f"({format_date('GREGORIAN', first)} to {format_date('GREGORIAN', last)})"
    result = [title, "Mo Tu We Th Fr Sa Su"]
    cursor = first - (first - 1) % 7
    while cursor <= last:
        fields = [f"{fixed - first + 1:2d}" if first <= fixed <= last else "  "
                  for fixed in range(cursor, cursor + 7)]
        result.append(" ".join(fields).rstrip())
        cursor += 7
    return result


def span_text(calendar, first, last):
    negative = first > last
    if negative:
        first, last = last, first
    start_year = parts_of(calendar, first)[0]
    end_year = parts_of(calendar, last)[0]
    low = 0
    high = end_year - start_year + 2
    while low + 1 < high:
        middle = (low + high) // 2
        shifted = shift(calendar, first, middle, 0)
        if shifted is not None and shifted <= last:
            low = middle
        else:
            high = middle
    years = low
    low = 0
    high = 32
    while low + 1 < high:
        middle = (low + high) // 2
        shifted = shift(calendar, first, years, middle)
        if shifted is not None and shifted <= last:
            low = middle
        else:
            high = middle
    months = low
    days = last - shift(calendar, first, years, months)
    sign = "-" if negative else ""
    return f"{sign}{years}y {months}m {days}d"


def round_date(calendar, fixed, number, tz_name, day, month):
    target_tz = TZ.index(tz_name)
    target_haab = HB.index(month) * 20 + day
    candidate = fixed
    while True:
        count = candidate + 1137142
        if (count + 3) % 13 + 1 == number and (count + 19) % 20 == target_tz:
            break
        candidate += 1
    while candidate <= fixed + 18979:
        if (candidate + 1137142 + 348) % 365 == target_haab:
            return format_date(calendar, candidate)
        candidate += 260
    return "NONE"


def execute(command, args):
    validate_arguments(command, args)
    if command in ("EASTER", "COMPUTUS"):
        year = int(args[0])
        if year > 9999:
            return ["OUT OF RANGE"]
        kind = args[1]
        epact, letters, moon, sunday = easter(year, kind)
        if command == "EASTER":
            return [format_date("GREGORIAN", sunday)]
        return [
            f"golden={year % 19 + 1} epact={epact} letters={letters} "
            f"moon={format_date(kind, moon)} easter={format_date(kind, sunday)}"
        ]
    if command in ("PASSOVER", "HOLIDAYS", "MOLAD"):
        year = int(args[0])
        if command == "MOLAD":
            day, parts, fixed, rules = molad(year)
            if not in_range(fixed):
                return ["OUT OF RANGE"]
            applied = "+".join(rules) if rules else "NONE"
            return [
                f"{WEEKDAYS[(day - 1373427) % 7]} {parts // 1080}h "
                f"{parts % 1080}p {applied} {WEEKDAYS[fixed % 7]} "
                f"{format_date('GREGORIAN', fixed)}"
            ]
        if year > 9999:
            return ["OUT OF RANGE"]
        if command == "HOLIDAYS":
            return holiday_lines(year)
        hebrew_year = year + 3760
        month = names("HEBREW", hebrew_year).index("Nisan") + 1
        fixed = fixed_date("HEBREW", hebrew_year, month, 15)
        return [f"{format_date('GREGORIAN', fixed)} {WEEKDAYS[fixed % 7]}"]
    calendar = args[0]
    if command in ("LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR"):
        year = int(args[1])
        if command == "LEAP":
            text = f"{'YES' if leap(calendar, year) else 'NO'} "
            text += str(start(calendar, year + 1) - start(calendar, year))
            if calendar == "HEBREW":
                text += " " + year_type(year)
            return [text]
        if command == "MONTHS":
            return [" ".join(
                f"{name}={days}" for name, days in zip(names(calendar, year), lengths(calendar, year))
            )]
        if command == "NEWYEAR":
            if year > 9999:
                return ["OUT OF RANGE"]
            first = start("GREGORIAN", year)
            last = start("GREGORIAN", year + 1) - 1
            entries = new_years(calendar, first, last)
            return [" ".join(f"{y}:{format_date('GREGORIAN', f)}" for y, f in entries) or "NONE"]
        month = int(args[2])
        if command == "MONTHCAL":
            return calendar_lines(calendar, year, month)
        first, last = month_bounds(calendar, year, month)
        weekday = WEEKDAYS.index(args[4])
        if args[3] == "LAST":
            fixed = last - (last - weekday) % 7
        else:
            fixed = first + (weekday - first) % 7 + 7 * (int(args[3]) - 1)
        return ["NONE" if fixed > last else format_date(calendar, fixed)]
    if command == "VALID":
        try:
            fixed = parse_date(calendar, args[1])
        except DateError as error:
            return ["NO " + str(error)]
        return ["YES " + format_date(calendar, fixed)]
    first = parse_date(calendar, args[1])
    if command == "DIFF":
        last = parse_date(args[2], args[3])
        return [str(last - first)]
    if command in ("COUNT", "SPAN"):
        last = parse_date(calendar, args[2])
        if command == "SPAN":
            return [span_text(calendar, first, last)]
        low, high = sorted((first, last))
        occurrence = low + (WEEKDAYS.index(args[3]) - low) % 7
        return [str(0 if occurrence > high else (high - occurrence) // 7 + 1)]
    if command == "CONVERT":
        return [format_date(args[3], first)]
    if command == "WEEKDAY":
        return [WEEKDAYS[first % 7]]
    if command == "ALL":
        result = []
        for target in CALENDARS:
            text = format_date(target, first)
            if target in YMD and text != "OUT OF RANGE":
                year, month, _ = parts_of(target, first)
                text += " " + names(target, year)[month - 1]
            result.append(target + " " + text)
        return result
    if command == "INFO":
        year, month, day = parts_of(calendar, first)
        weekday = WEEKDAYS[first % 7]
        if calendar == "FRENCH":
            weekday = DC[(day - 1) % 10] if month <= 12 else FS[day - 1]
        ordinal = first - start(calendar, year) + 1
        length = start(calendar, year + 1) - start(calendar, year)
        return [f"{weekday} {day} {names(calendar, year)[month - 1]} {year} day={ordinal}/{length}"]
    if command == "ROUND":
        return [round_date(calendar, first, int(args[2]), args[3], int(args[4]), args[5])]
    amount = int(args[2])
    unit = args[3]
    if unit == "DAYS":
        result = first + amount
    elif unit == "WEEKS":
        result = first + 7 * amount
    elif unit == "YEARS":
        result = shift(calendar, first, amount, 0)
    else:
        result = shift(calendar, first, 0, amount)
    return ["OUT OF RANGE" if result is None else format_date(calendar, result)]


def main():
    lines = sys.stdin.read().splitlines()
    count = int(lines[0])
    output = []
    for line in lines[1:count + 1]:
        command, *args = line.split(" ")
        if command not in ARITY or len(args) != ARITY[command]:
            output.append("INVALID COMMAND")
            continue
        try:
            output.extend(execute(command, args))
        except CommandError:
            output.append("INVALID COMMAND")
        except DateError as error:
            output.append("OUT OF RANGE" if str(error) == "RANGE" else "INVALID DATE")
    sys.stdout.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()
