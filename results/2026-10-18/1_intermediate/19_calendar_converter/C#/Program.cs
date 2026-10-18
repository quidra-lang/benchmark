using System.Globalization;
using System.Text.RegularExpressions;

class Program {
    enum Calendar { GREGORIAN, JULIAN, ISO, ISLAMIC, HEBREW, PERSIAN, COPTIC, ETHIOPIC, FRENCH, MAYAN, JD, FIXED }
    record Molad(long Day, int Parts, long Start, List<string> Rules);
    record DateParts(long Year, int Month, int Day);
    record Easter(int Epact, string Letters, long Moon, long Sunday);
    record Holiday(string Name, Calendar Calendar, string Month, int Day);
    record Entry(long Fixed, int Order, string Name, Calendar Calendar);
    class DateError(string reason) : Exception(reason) {}
    class CommandError : Exception {}

    static readonly Calendar[] CALENDARS = Enum.GetValues<Calendar>();
    static readonly HashSet<Calendar> YMD = [.. CALENDARS.Except([Calendar.ISO, Calendar.MAYAN, Calendar.JD, Calendar.FIXED])];
    static readonly HashSet<Calendar> YEAR_CALENDARS = [.. YMD, Calendar.ISO];
    static readonly List<string> WEEKDAYS = Words("Sunday Monday Tuesday Wednesday Thursday Friday Saturday");
    static readonly List<string> TZ = Words("Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau");
    static readonly List<string> HB = Words("Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb");
    static readonly List<string> DC = Words("Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi");
    static readonly List<string> FS = Words("Vertu Genie Travail Opinion Recompenses Revolution");
    const long MAX_FIXED = 3652059;
    static readonly List<string> ROMAN_MONTHS = Words("January February March April May June July August September October November December");
    static readonly Dictionary<Calendar, List<string>> MONTH_NAMES = new() {
        [Calendar.GREGORIAN] = ROMAN_MONTHS,
        [Calendar.JULIAN] = ROMAN_MONTHS,
        [Calendar.ISLAMIC] = Words("Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah"),
        [Calendar.HEBREW] = Words("Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul"),
        [Calendar.PERSIAN] = Words("Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand"),
        [Calendar.COPTIC] = Words("Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie"),
        [Calendar.ETHIOPIC] = Words("Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume"),
        [Calendar.FRENCH] = Words("Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides"),
    };
    static readonly List<string> HEBREW_LEAP_NAMES = Words("Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul");
    static readonly List<Holiday> HOLIDAYS = [
        new("Christmas", Calendar.GREGORIAN, "December", 25),
        new("OrthodoxChristmas", Calendar.JULIAN, "December", 25),
        new("RoshHashanah", Calendar.HEBREW, "Tishri", 1),
        new("YomKippur", Calendar.HEBREW, "Tishri", 10),
        new("Sukkot", Calendar.HEBREW, "Tishri", 15),
        new("Hanukkah", Calendar.HEBREW, "Kislev", 25),
        new("Purim", Calendar.HEBREW, "Adar", 14),
        new("Passover", Calendar.HEBREW, "Nisan", 15),
        new("Shavuot", Calendar.HEBREW, "Sivan", 6),
        new("IslamicNewYear", Calendar.ISLAMIC, "Muharram", 1),
        new("Ashura", Calendar.ISLAMIC, "Muharram", 10),
        new("Mawlid", Calendar.ISLAMIC, "RabiI", 12),
        new("RamadanStart", Calendar.ISLAMIC, "Ramadan", 1),
        new("EidAlFitr", Calendar.ISLAMIC, "Shawwal", 1),
        new("EidAlAdha", Calendar.ISLAMIC, "DhuAlHijjah", 10),
        new("Nowruz", Calendar.PERSIAN, "Farvardin", 1),
        new("SizdahBedar", Calendar.PERSIAN, "Farvardin", 13),
        new("Yalda", Calendar.PERSIAN, "Azar", 30),
        new("Nayrouz", Calendar.COPTIC, "Thout", 1),
        new("CopticChristmas", Calendar.COPTIC, "Koiak", 29),
        new("Enkutatash", Calendar.ETHIOPIC, "Meskerem", 1),
        new("Meskel", Calendar.ETHIOPIC, "Meskerem", 17),
        new("Timkat", Calendar.ETHIOPIC, "Ter", 11),
        new("RepublicDay", Calendar.FRENCH, "Vendemiaire", 1),
        new("RevolutionDay", Calendar.FRENCH, "Sansculottides", 6),
    ];
    static readonly Dictionary<string, int> ARITY = new() {
        ["CONVERT"] = 4, ["ALL"] = 2, ["VALID"] = 2, ["WEEKDAY"] = 2, ["INFO"] = 2,
        ["LEAP"] = 2, ["MONTHS"] = 2, ["MONTHCAL"] = 3, ["NTH"] = 5, ["NEWYEAR"] = 2,
        ["DIFF"] = 4, ["COUNT"] = 4, ["ADD"] = 4, ["SPAN"] = 3, ["EASTER"] = 2,
        ["COMPUTUS"] = 2, ["PASSOVER"] = 1, ["HOLIDAYS"] = 1, ["MOLAD"] = 1, ["ROUND"] = 6,
    };

    static List<string> Words(string text) => [.. text.Split(' ')];
    static bool FullMatch(string text, string pattern) => Regex.IsMatch(text, $@"\A(?:{pattern})\z");
    static void Require(bool condition) {
        if (!condition) throw new CommandError();
    }
    static int Mod(long value, int modulus) => (int)((value % modulus + modulus) % modulus);
    static long FloorDiv(long value, int divisor) => (value - Mod(value, divisor)) / divisor;
    static bool InRange(long fixedDay) => fixedDay >= 1 && fixedDay <= MAX_FIXED;
    static string WeekdayName(long fixedDay) => WEEKDAYS[Mod(fixedDay, 7)];
    static bool Leap(Calendar calendar, long year) => calendar switch {
        Calendar.GREGORIAN => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0),
        Calendar.JULIAN => year % 4 == 0,
        Calendar.ISLAMIC => Mod(year, 30) is 2 or 5 or 7 or 10 or 13 or 16 or 18 or 21 or 24 or 26 or 29,
        Calendar.HEBREW => Mod(7 * year + 1, 19) < 7,
        Calendar.PERSIAN => (Mod(year - 474, 2820) + 474 + 38) * 682 % 2816 < 682,
        Calendar.COPTIC or Calendar.ETHIOPIC => Mod(year, 4) == 3,
        Calendar.FRENCH => year % 4 == 0 && Mod(year, 400) is not (100 or 200 or 300) && year % 4000 != 0,
        Calendar.ISO => Weeks(year) == 53,
        _ => throw new ArgumentException($"no years in {calendar}"),
    };
    static int Weeks(long year) => (int)((Start(Calendar.ISO, year + 1) - Start(Calendar.ISO, year)) / 7);
    static long MonthsBefore(long year) => FloorDiv(235 * year - 234, 19);
    static Molad MoladOf(long year) {
        long quantity = 5604 + 765433 * MonthsBefore(year);
        long day = FloorDiv(quantity, 25920);
        int parts = Mod(quantity, 25920);
        int weekday = Mod(day - 1373427, 7);
        List<string> rules = [];
        long postponed = day;
        if (parts >= 19440) {
            postponed += 1;
            rules.Add("ZAKEN");
        } else if (!Leap(Calendar.HEBREW, year) && weekday == 2 && parts >= 9924) {
            postponed += 2;
            rules.Add("GATARAD");
        } else if (Leap(Calendar.HEBREW, year - 1) && weekday == 1 && parts >= 16789) {
            postponed += 1;
            rules.Add("BETUTAKPAT");
        }
        if (Mod(postponed - 1373427, 7) is 0 or 3 or 5) {
            postponed += 1;
            rules.Add("ADU");
        }
        return new Molad(day, parts, postponed - 1373427, rules);
    }
    static long Start(Calendar calendar, long year) {
        long previous = year - 1;
        switch (calendar) {
            case Calendar.GREGORIAN: return 365 * previous + previous / 4 - previous / 100 + previous / 400 + 1;
            case Calendar.JULIAN: return 365 * previous + previous / 4 - 1;
            case Calendar.ISLAMIC: return 227015 + 354 * previous + (3 + 11 * year) / 30;
            case Calendar.HEBREW: return MoladOf(year).Start;
            case Calendar.PERSIAN: {
                long a = year - 474;
                long b = Mod(a, 2820) + 474;
                return 226896 + 1029983 * FloorDiv(a, 2820) + 365 * (b - 1) + (682 * b - 110) / 2816;
            }
            case Calendar.COPTIC: return 103605 + 365 * previous + year / 4;
            case Calendar.ETHIOPIC: return 2796 + 365 * previous + year / 4;
            case Calendar.FRENCH: return 654415 + 365 * previous + previous / 4 - previous / 100 + previous / 400 - previous / 4000;
            case Calendar.ISO: {
                long januaryFour = Start(Calendar.GREGORIAN, year) + 3;
                return januaryFour - (januaryFour - 1) % 7;
            }
            default: throw new ArgumentException($"no years in {calendar}");
        }
    }
    static string YearType(long year) => (Start(Calendar.HEBREW, year + 1) - Start(Calendar.HEBREW, year)) switch {
        353 or 383 => "DEFICIENT",
        354 or 384 => "REGULAR",
        _ => "COMPLETE",
    };
    static List<string> Names(Calendar calendar, long year) {
        if (calendar == Calendar.HEBREW && Leap(calendar, year)) return HEBREW_LEAP_NAMES;
        return MONTH_NAMES[calendar];
    }
    static int[] Lengths(Calendar calendar, long year) {
        int extra = Leap(calendar, year) ? 1 : 0;
        switch (calendar) {
            case Calendar.GREGORIAN or Calendar.JULIAN: return [31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
            case Calendar.ISLAMIC: return [30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra];
            case Calendar.PERSIAN: return [31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29 + extra];
            case Calendar.COPTIC or Calendar.ETHIOPIC or Calendar.FRENCH: return [30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 5 + extra];
            case Calendar.HEBREW: {
                string kind = YearType(year);
                int heshvan = kind == "COMPLETE" ? 30 : 29;
                int kislev = kind == "DEFICIENT" ? 29 : 30;
                if (extra == 1) return [30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29];
                return [30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29];
            }
            default: throw new ArgumentException($"no months in {calendar}");
        }
    }
    static long FixedDate(Calendar calendar, long year, int month, int day) {
        if (calendar == Calendar.ISO) return Start(calendar, year) + 7 * (month - 1) + day - 1;
        return Start(calendar, year) + Lengths(calendar, year).Take(month - 1).Sum() + day - 1;
    }
    static long YearOf(Calendar calendar, long fixedDay) {
        if (fixedDay < Start(calendar, 1)) return 0;
        long low = 1, high = 100000;
        while (low + 1 < high) {
            long middle = (low + high) / 2;
            if (Start(calendar, middle) <= fixedDay) low = middle;
            else high = middle;
        }
        return low;
    }
    static DateParts? PartsOf(Calendar calendar, long fixedDay) {
        long year = YearOf(calendar, fixedDay);
        if (year == 0) return null;
        int offset = (int)(fixedDay - Start(calendar, year));
        if (calendar == Calendar.ISO) return new DateParts(year, offset / 7 + 1, offset % 7 + 1);
        int[] days = Lengths(calendar, year);
        int month = 0;
        while (offset >= days[month]) {
            offset -= days[month];
            month++;
        }
        return new DateParts(year, month + 1, offset + 1);
    }
    static string FormatDate(Calendar calendar, long fixedDay) {
        if (!InRange(fixedDay)) return "OUT OF RANGE";
        if (YEAR_CALENDARS.Contains(calendar)) {
            DateParts? parts = PartsOf(calendar, fixedDay);
            if (parts == null) return "OUT OF RANGE";
            if (calendar == Calendar.ISO) return $"{parts.Year:D4}-W{parts.Month:D2}-{parts.Day}";
            return $"{parts.Year:D4}-{parts.Month:D2}-{parts.Day:D2}";
        }
        if (calendar == Calendar.JD) return (fixedDay + 1721425).ToString();
        if (calendar == Calendar.FIXED) return fixedDay.ToString();
        long count = fixedDay + 1137142;
        long[] longCount = [count / 144000, count / 7200 % 20, count / 360 % 20, count / 20 % 18, count % 20];
        int haab = Mod(count + 348, 365);
        return $"{string.Join(".", longCount)} {(count + 3) % 13 + 1} {TZ[Mod(count + 19, 20)]} {haab % 20} {HB[haab / 20]}";
    }
    static long ParseDate(Calendar calendar, string text) {
        long fixedDay;
        if (YMD.Contains(calendar)) {
            if (!FullMatch(text, "[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}")) throw new DateError("FORMAT");
            string[] fields = text.Split('-');
            long year = long.Parse(fields[0]);
            int month = int.Parse(fields[1]), day = int.Parse(fields[2]);
            if (year == 0) throw new DateError("YEAR");
            int[] days = Lengths(calendar, year);
            if (month < 1 || month > days.Length) throw new DateError("MONTH");
            if (day < 1 || day > days[month - 1]) throw new DateError("DAY");
            fixedDay = FixedDate(calendar, year, month, day);
        } else if (calendar == Calendar.ISO) {
            if (!FullMatch(text, "[0-9]{1,5}-W[0-9]{1,2}-[0-9]")) throw new DateError("FORMAT");
            string[] fields = text.Split('-');
            long year = long.Parse(fields[0]);
            int week = int.Parse(fields[1][1..]), day = int.Parse(fields[2]);
            if (year == 0) throw new DateError("YEAR");
            if (week < 1 || week > Weeks(year)) throw new DateError("WEEK");
            if (day < 1 || day > 7) throw new DateError("DAY");
            fixedDay = FixedDate(calendar, year, week, day);
        } else if (calendar == Calendar.MAYAN) {
            if (!FullMatch(text, @"[0-9]{1,2}(?:\.[0-9]{1,2}){4}")) throw new DateError("FORMAT");
            long[] v = [.. text.Split('.').Select(long.Parse)];
            if (v[1] > 19 || v[2] > 19 || v[3] > 17 || v[4] > 19) throw new DateError("FIELD");
            fixedDay = (((v[0] * 20 + v[1]) * 20 + v[2]) * 18 + v[3]) * 20 + v[4] - 1137142;
        } else {
            if (!FullMatch(text, "-?[0-9]{1,8}")) throw new DateError("FORMAT");
            fixedDay = long.Parse(text) - (calendar == Calendar.JD ? 1721425 : 0);
        }
        if (!InRange(fixedDay)) throw new DateError("RANGE");
        return fixedDay;
    }
    static long MonthIndex(Calendar calendar, long year) {
        if (calendar == Calendar.HEBREW) return MonthsBefore(year);
        return MONTH_NAMES[calendar].Count * (year - 1);
    }
    static long? Shift(Calendar calendar, long fixedDay, long years, long months) {
        DateParts parts = PartsOf(calendar, fixedDay)!;
        long targetYear = parts.Year + years;
        if (calendar == Calendar.ISO) {
            if (targetYear < 1 || targetYear > 99999) return null;
            return FixedDate(calendar, targetYear, Math.Min(parts.Month, Weeks(targetYear)), parts.Day);
        }
        int month = parts.Month;
        if (calendar == Calendar.HEBREW) {
            string oldName = Names(calendar, parts.Year)[month - 1];
            List<string> newNames = Names(calendar, targetYear);
            if (!newNames.Contains(oldName)) oldName = oldName == "Adar" ? "AdarII" : "Adar";
            month = newNames.IndexOf(oldName) + 1;
        }
        long absolute = MonthIndex(calendar, targetYear) + month - 1 + months;
        long finalYear;
        if (calendar == Calendar.HEBREW) {
            finalYear = FloorDiv(19 * absolute + 234, 235);
            while (MonthIndex(calendar, finalYear) > absolute) finalYear--;
            while (MonthIndex(calendar, finalYear + 1) <= absolute) finalYear++;
        } else {
            finalYear = FloorDiv(absolute, MONTH_NAMES[calendar].Count) + 1;
        }
        if (finalYear < 1 || finalYear > 99999) return null;
        int finalMonth = (int)(absolute - MonthIndex(calendar, finalYear) + 1);
        int finalDay = Math.Min(parts.Day, Lengths(calendar, finalYear)[finalMonth - 1]);
        return FixedDate(calendar, finalYear, finalMonth, finalDay);
    }
    static (long First, long Last) MonthBounds(Calendar calendar, long year, int month) {
        int[] days = Lengths(calendar, year);
        if (month < 1 || month > days.Length) throw new DateError("MONTH");
        long first = FixedDate(calendar, year, month, 1);
        return (first, first + days[month - 1] - 1);
    }
    static List<(long Year, long Start)> NewYears(Calendar calendar, long first, long last) {
        long year = Math.Max(1, YearOf(calendar, first));
        while (Start(calendar, year) < first) year++;
        List<(long Year, long Start)> result = [];
        for (; Start(calendar, year) <= last; year++) result.Add((year, Start(calendar, year)));
        return result;
    }
    static Easter EasterOf(int year, Calendar calendar) {
        int golden = year % 19;
        int epact;
        if (calendar == Calendar.GREGORIAN) {
            int century = year / 100 + 1;
            epact = Mod(14 + 11 * golden - 3 * century / 4 + (5 + 8 * century) / 25, 30);
            if (epact == 0 || epact == 1 && golden > 10) epact++;
        } else {
            epact = (14 + 11 * golden) % 30;
        }
        long moon = FixedDate(calendar, year, 4, 19) - epact;
        long sunday = moon + 7 - moon % 7;
        int index = Mod(-Start(calendar, year), 7);
        string letters = "ABCDEFG"[index].ToString();
        if (Leap(calendar, year)) letters += "ABCDEFG"[Mod(index - 1, 7)];
        return new Easter(epact, letters, moon, sunday);
    }
    static List<string> HolidayLines(int year) {
        long first = Start(Calendar.GREGORIAN, year), last = Start(Calendar.GREGORIAN, year + 1) - 1;
        long gregorianEaster = EasterOf(year, Calendar.GREGORIAN).Sunday;
        long orthodoxEaster = EasterOf(year, Calendar.JULIAN).Sunday;
        (string Name, int Offset)[] movable = [("AshWednesday", -46), ("GoodFriday", -2), ("Easter", 0), ("Ascension", 39), ("Pentecost", 49)];
        List<Entry> entries = [.. movable.Select((feast, order) => new Entry(gregorianEaster + feast.Offset, order, feast.Name, Calendar.GREGORIAN))];
        entries.Add(new Entry(orthodoxEaster, 5, "OrthodoxEaster", Calendar.JULIAN));
        for (int order = 0; order < HOLIDAYS.Count; order++) {
            Holiday holiday = HOLIDAYS[order];
            Calendar calendar = holiday.Calendar;
            for (long candidateYear = Math.Max(1, YearOf(calendar, first)); Start(calendar, candidateYear) <= last; candidateYear++) {
                string actualName = holiday.Month;
                if (calendar == Calendar.HEBREW && actualName == "Adar" && Leap(calendar, candidateYear)) actualName = "AdarII";
                int month = Names(calendar, candidateYear).IndexOf(actualName) + 1;
                if (holiday.Day <= Lengths(calendar, candidateYear)[month - 1]) {
                    long fixedDay = FixedDate(calendar, candidateYear, month, holiday.Day);
                    if (first <= fixedDay && fixedDay <= last) entries.Add(new Entry(fixedDay, order + 6, holiday.Name, calendar));
                }
            }
        }
        return [.. entries.OrderBy(entry => entry.Fixed).ThenBy(entry => entry.Order).Select(entry =>
            $"{FormatDate(Calendar.GREGORIAN, entry.Fixed)} {WeekdayName(entry.Fixed)} {entry.Name} {entry.Calendar} {FormatDate(entry.Calendar, entry.Fixed)}")];
    }
    static bool ValidYear(string text) => FullMatch(text, "[0-9]{1,5}") && int.Parse(text) >= 1;
    static bool IsCalendar(string text, IEnumerable<Calendar> allowed) => allowed.Any(calendar => calendar.ToString() == text);
    static void ValidateArguments(string command, string[] args) {
        if (command is "EASTER" or "COMPUTUS") {
            Require(ValidYear(args[0]) && (args[1] is "GREGORIAN" or "JULIAN"));
            return;
        }
        if (command is "PASSOVER" or "HOLIDAYS" or "MOLAD") {
            Require(ValidYear(args[0]));
            return;
        }
        IEnumerable<Calendar> allowed = command switch {
            "INFO" or "MONTHS" or "MONTHCAL" or "NTH" or "SPAN" => YMD,
            "LEAP" or "NEWYEAR" => YEAR_CALENDARS,
            _ => CALENDARS,
        };
        Require(IsCalendar(args[0], allowed));
        switch (command) {
            case "CONVERT":
                Require(args[2] == "TO" && IsCalendar(args[3], CALENDARS));
                break;
            case "DIFF":
                Require(IsCalendar(args[2], CALENDARS));
                break;
            case "LEAP" or "MONTHS" or "MONTHCAL" or "NTH" or "NEWYEAR":
                Require(ValidYear(args[1]));
                if (command is "MONTHCAL" or "NTH") Require(FullMatch(args[2], "[0-9]{1,2}"));
                if (command == "NTH") {
                    Require(args[3] is "1" or "2" or "3" or "4" or "5" or "LAST");
                    Require(WEEKDAYS.Contains(args[4]));
                }
                break;
            case "COUNT":
                Require(WEEKDAYS.Contains(args[3]));
                break;
            case "ADD":
                Require(FullMatch(args[2], "-?[0-9]{1,7}"));
                Require(args[3] is "DAYS" or "WEEKS" or "MONTHS" or "YEARS");
                Calendar calendar = Enum.Parse<Calendar>(args[0]);
                if (args[3] == "MONTHS") Require(YMD.Contains(calendar));
                if (args[3] == "YEARS") Require(YEAR_CALENDARS.Contains(calendar));
                break;
            case "ROUND":
                Require(FullMatch(args[2], "[0-9]{1,2}"));
                Require(int.Parse(args[2]) is >= 1 and <= 13 && TZ.Contains(args[3]));
                Require(FullMatch(args[4], "[0-9]{1,2}"));
                Require(HB.Contains(args[5]));
                Require(int.Parse(args[4]) <= (args[5] == "Uayeb" ? 4 : 19));
                break;
        }
    }
    static List<string> CalendarLines(Calendar calendar, long year, int month) {
        (long first, long last) = MonthBounds(calendar, year, month);
        if (!InRange(first) || !InRange(last)) return ["OUT OF RANGE"];
        List<string> result = [
            $"{Names(calendar, year)[month - 1]} {year} ({FormatDate(Calendar.GREGORIAN, first)} to {FormatDate(Calendar.GREGORIAN, last)})",
            "Mo Tu We Th Fr Sa Su",
        ];
        for (long cursor = first - (first - 1) % 7; cursor <= last; cursor += 7) {
            long weekStart = cursor;
            IEnumerable<string> fields = Enumerable.Range(0, 7).Select(i => weekStart + i)
                .Select(day => first <= day && day <= last ? $"{day - first + 1,2}" : "  ");
            result.Add(string.Join(" ", fields).TrimEnd());
        }
        return result;
    }
    static string SpanText(Calendar calendar, long first, long last) {
        long from = Math.Min(first, last), to = Math.Max(first, last);
        long low = 0, high = PartsOf(calendar, to)!.Year - PartsOf(calendar, from)!.Year + 2;
        while (low + 1 < high) {
            long middle = (low + high) / 2;
            long? shifted = Shift(calendar, from, middle, 0);
            if (shifted <= to) low = middle;
            else high = middle;
        }
        long years = low;
        low = 0;
        high = 32;
        while (low + 1 < high) {
            long middle = (low + high) / 2;
            long? shifted = Shift(calendar, from, years, middle);
            if (shifted <= to) low = middle;
            else high = middle;
        }
        long months = low;
        long days = to - Shift(calendar, from, years, months)!.Value;
        return $"{(first > last ? "-" : "")}{years}y {months}m {days}d";
    }
    static string RoundDate(Calendar calendar, long fixedDay, int number, string tzName, int day, string month) {
        int targetTz = TZ.IndexOf(tzName);
        int targetHaab = HB.IndexOf(month) * 20 + day;
        long candidate = fixedDay;
        while ((candidate + 1137142 + 3) % 13 + 1 != number || (candidate + 1137142 + 19) % 20 != targetTz) candidate++;
        for (; candidate <= fixedDay + 18979; candidate += 260) {
            if ((candidate + 1137142 + 348) % 365 == targetHaab) return FormatDate(calendar, candidate);
        }
        return "NONE";
    }
    static List<string> Execute(string command, string[] args) {
        ValidateArguments(command, args);
        if (command is "EASTER" or "COMPUTUS") {
            int year = int.Parse(args[0]);
            if (year > 9999) return ["OUT OF RANGE"];
            Calendar kind = Enum.Parse<Calendar>(args[1]);
            Easter easter = EasterOf(year, kind);
            if (command == "EASTER") return [FormatDate(Calendar.GREGORIAN, easter.Sunday)];
            return [$"golden={year % 19 + 1} epact={easter.Epact} letters={easter.Letters} " +
                $"moon={FormatDate(kind, easter.Moon)} easter={FormatDate(kind, easter.Sunday)}"];
        }
        if (command is "PASSOVER" or "HOLIDAYS" or "MOLAD") {
            int year = int.Parse(args[0]);
            if (command == "MOLAD") {
                Molad molad = MoladOf(year);
                if (!InRange(molad.Start)) return ["OUT OF RANGE"];
                string applied = molad.Rules.Count == 0 ? "NONE" : string.Join("+", molad.Rules);
                return [$"{WeekdayName(molad.Day - 1373427)} {molad.Parts / 1080}h {molad.Parts % 1080}p {applied} " +
                    $"{WeekdayName(molad.Start)} {FormatDate(Calendar.GREGORIAN, molad.Start)}"];
            }
            if (year > 9999) return ["OUT OF RANGE"];
            if (command == "HOLIDAYS") return HolidayLines(year);
            long hebrewYear = year + 3760;
            int month = Names(Calendar.HEBREW, hebrewYear).IndexOf("Nisan") + 1;
            long fixedDay = FixedDate(Calendar.HEBREW, hebrewYear, month, 15);
            return [$"{FormatDate(Calendar.GREGORIAN, fixedDay)} {WeekdayName(fixedDay)}"];
        }
        Calendar calendar = Enum.Parse<Calendar>(args[0]);
        if (command is "LEAP" or "MONTHS" or "MONTHCAL" or "NTH" or "NEWYEAR") {
            long year = long.Parse(args[1]);
            switch (command) {
                case "LEAP": {
                    string text = $"{(Leap(calendar, year) ? "YES" : "NO")} {Start(calendar, year + 1) - Start(calendar, year)}";
                    if (calendar == Calendar.HEBREW) text += " " + YearType(year);
                    return [text];
                }
                case "MONTHS":
                    return [string.Join(" ", Names(calendar, year).Zip(Lengths(calendar, year), (name, days) => $"{name}={days}"))];
                case "NEWYEAR": {
                    if (year > 9999) return ["OUT OF RANGE"];
                    List<(long Year, long Start)> entries = NewYears(calendar, Start(Calendar.GREGORIAN, year), Start(Calendar.GREGORIAN, year + 1) - 1);
                    if (entries.Count == 0) return ["NONE"];
                    return [string.Join(" ", entries.Select(entry => $"{entry.Year}:{FormatDate(Calendar.GREGORIAN, entry.Start)}"))];
                }
                case "MONTHCAL":
                    return CalendarLines(calendar, year, int.Parse(args[2]));
                default: {
                    (long first, long last) = MonthBounds(calendar, year, int.Parse(args[2]));
                    int weekday = WEEKDAYS.IndexOf(args[4]);
                    long fixedDay = args[3] == "LAST" ? last - Mod(last - weekday, 7)
                        : first + Mod(weekday - first, 7) + 7 * (int.Parse(args[3]) - 1);
                    return [fixedDay > last ? "NONE" : FormatDate(calendar, fixedDay)];
                }
            }
        }
        if (command == "VALID") {
            try {
                return ["YES " + FormatDate(calendar, ParseDate(calendar, args[1]))];
            } catch (DateError error) {
                return ["NO " + error.Message];
            }
        }
        long date = ParseDate(calendar, args[1]);
        switch (command) {
            case "DIFF":
                return [(ParseDate(Enum.Parse<Calendar>(args[2]), args[3]) - date).ToString()];
            case "COUNT": {
                long other = ParseDate(calendar, args[2]);
                long low = Math.Min(date, other), high = Math.Max(date, other);
                long occurrence = low + Mod(WEEKDAYS.IndexOf(args[3]) - low, 7);
                return [(occurrence > high ? 0 : (high - occurrence) / 7 + 1).ToString()];
            }
            case "SPAN":
                return [SpanText(calendar, date, ParseDate(calendar, args[2]))];
            case "CONVERT":
                return [FormatDate(Enum.Parse<Calendar>(args[3]), date)];
            case "WEEKDAY":
                return [WeekdayName(date)];
            case "ALL": {
                List<string> result = [];
                foreach (Calendar target in CALENDARS) {
                    string text = FormatDate(target, date);
                    if (YMD.Contains(target) && text != "OUT OF RANGE") {
                        DateParts parts = PartsOf(target, date)!;
                        text += " " + Names(target, parts.Year)[parts.Month - 1];
                    }
                    result.Add($"{target} {text}");
                }
                return result;
            }
            case "INFO": {
                DateParts parts = PartsOf(calendar, date)!;
                string weekday = WeekdayName(date);
                if (calendar == Calendar.FRENCH) weekday = parts.Month <= 12 ? DC[(parts.Day - 1) % 10] : FS[parts.Day - 1];
                long ordinal = date - Start(calendar, parts.Year) + 1;
                long length = Start(calendar, parts.Year + 1) - Start(calendar, parts.Year);
                return [$"{weekday} {parts.Day} {Names(calendar, parts.Year)[parts.Month - 1]} {parts.Year} day={ordinal}/{length}"];
            }
            case "ROUND":
                return [RoundDate(calendar, date, int.Parse(args[2]), args[3], int.Parse(args[4]), args[5])];
            default: {
                int amount = int.Parse(args[2]);
                long? result = args[3] switch {
                    "DAYS" => date + amount,
                    "WEEKS" => date + 7L * amount,
                    "YEARS" => Shift(calendar, date, amount, 0),
                    _ => Shift(calendar, date, 0, amount),
                };
                return [result is long day ? FormatDate(calendar, day) : "OUT OF RANGE"];
            }
        }
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++) {
            string[] words = Console.ReadLine()!.Split(' ');
            string command = words[0];
            string[] args = words[1..];
            List<string> lines;
            if (!ARITY.TryGetValue(command, out int arity) || arity != args.Length) {
                lines = ["INVALID COMMAND"];
            } else {
                try {
                    lines = Execute(command, args);
                } catch (CommandError) {
                    lines = ["INVALID COMMAND"];
                } catch (DateError error) {
                    lines = [error.Message == "RANGE" ? "OUT OF RANGE" : "INVALID DATE"];
                }
            }
            foreach (string line in lines) Console.WriteLine(line);
        }
    }
}
