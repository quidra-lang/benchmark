import java.io.*;
import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.LongStream;

public class Main {
    enum Calendar { GREGORIAN, JULIAN, ISO, ISLAMIC, HEBREW, PERSIAN, COPTIC, ETHIOPIC, FRENCH, MAYAN, JD, FIXED }
    record Molad(long day, int parts, long start, List<String> rules) {}
    record Parts(long year, int month, int day) {}
    record Period(long first, long last) {}
    record YearStart(long year, long fixed) {}
    record Easter(int epact, String letters, long moon, long sunday) {}
    record Holiday(String name, Calendar calendar, String month, int day) {}
    record Entry(long fixed, int order, String name, Calendar calendar) {}
    static class DateError extends RuntimeException {
        DateError(String reason) { super(reason); }
    }
    static class CommandError extends RuntimeException {}

    static final Set<Calendar> CALENDARS = EnumSet.allOf(Calendar.class);
    static final Set<Calendar> YMD = EnumSet.complementOf(EnumSet.of(Calendar.ISO, Calendar.MAYAN, Calendar.JD, Calendar.FIXED));
    static final Set<Calendar> YEAR_CALENDARS = EnumSet.complementOf(EnumSet.of(Calendar.MAYAN, Calendar.JD, Calendar.FIXED));
    static final List<String> WEEKDAYS = words("Sunday Monday Tuesday Wednesday Thursday Friday Saturday");
    static final List<String> TZ = words("Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau");
    static final List<String> HB = words("Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb");
    static final List<String> DC = words("Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi");
    static final List<String> FS = words("Vertu Genie Travail Opinion Recompenses Revolution");
    static final long MAX_FIXED = 3652059;
    static final List<String> ROMAN_MONTHS = words("January February March April May June July August September October November December");
    static final Map<Calendar, List<String>> MONTH_NAMES = Map.of(
        Calendar.GREGORIAN, ROMAN_MONTHS,
        Calendar.JULIAN, ROMAN_MONTHS,
        Calendar.ISLAMIC, words("Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah"),
        Calendar.HEBREW, words("Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul"),
        Calendar.PERSIAN, words("Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand"),
        Calendar.COPTIC, words("Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie"),
        Calendar.ETHIOPIC, words("Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume"),
        Calendar.FRENCH, words("Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides"));
    static final List<String> HEBREW_LEAP_NAMES = words("Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul");
    static final List<Holiday> HOLIDAYS = List.of(
        new Holiday("Christmas", Calendar.GREGORIAN, "December", 25),
        new Holiday("OrthodoxChristmas", Calendar.JULIAN, "December", 25),
        new Holiday("RoshHashanah", Calendar.HEBREW, "Tishri", 1),
        new Holiday("YomKippur", Calendar.HEBREW, "Tishri", 10),
        new Holiday("Sukkot", Calendar.HEBREW, "Tishri", 15),
        new Holiday("Hanukkah", Calendar.HEBREW, "Kislev", 25),
        new Holiday("Purim", Calendar.HEBREW, "Adar", 14),
        new Holiday("Passover", Calendar.HEBREW, "Nisan", 15),
        new Holiday("Shavuot", Calendar.HEBREW, "Sivan", 6),
        new Holiday("IslamicNewYear", Calendar.ISLAMIC, "Muharram", 1),
        new Holiday("Ashura", Calendar.ISLAMIC, "Muharram", 10),
        new Holiday("Mawlid", Calendar.ISLAMIC, "RabiI", 12),
        new Holiday("RamadanStart", Calendar.ISLAMIC, "Ramadan", 1),
        new Holiday("EidAlFitr", Calendar.ISLAMIC, "Shawwal", 1),
        new Holiday("EidAlAdha", Calendar.ISLAMIC, "DhuAlHijjah", 10),
        new Holiday("Nowruz", Calendar.PERSIAN, "Farvardin", 1),
        new Holiday("SizdahBedar", Calendar.PERSIAN, "Farvardin", 13),
        new Holiday("Yalda", Calendar.PERSIAN, "Azar", 30),
        new Holiday("Nayrouz", Calendar.COPTIC, "Thout", 1),
        new Holiday("CopticChristmas", Calendar.COPTIC, "Koiak", 29),
        new Holiday("Enkutatash", Calendar.ETHIOPIC, "Meskerem", 1),
        new Holiday("Meskel", Calendar.ETHIOPIC, "Meskerem", 17),
        new Holiday("Timkat", Calendar.ETHIOPIC, "Ter", 11),
        new Holiday("RepublicDay", Calendar.FRENCH, "Vendemiaire", 1),
        new Holiday("RevolutionDay", Calendar.FRENCH, "Sansculottides", 6));
    static final Map<String, Integer> ARITY = Map.ofEntries(
        Map.entry("CONVERT", 4), Map.entry("ALL", 2), Map.entry("VALID", 2), Map.entry("WEEKDAY", 2),
        Map.entry("INFO", 2), Map.entry("LEAP", 2), Map.entry("MONTHS", 2), Map.entry("MONTHCAL", 3),
        Map.entry("NTH", 5), Map.entry("NEWYEAR", 2), Map.entry("DIFF", 4), Map.entry("COUNT", 4),
        Map.entry("ADD", 4), Map.entry("SPAN", 3), Map.entry("EASTER", 2), Map.entry("COMPUTUS", 2),
        Map.entry("PASSOVER", 1), Map.entry("HOLIDAYS", 1), Map.entry("MOLAD", 1), Map.entry("ROUND", 6));

    static List<String> words(String text) {
        return List.of(text.split(" "));
    }
    static void require(boolean condition) {
        if (!condition) throw new CommandError();
    }
    static boolean inRange(long fixed) {
        return fixed >= 1 && fixed <= MAX_FIXED;
    }
    static String weekdayName(long fixed) {
        return WEEKDAYS.get(Math.floorMod(fixed, 7));
    }
    static boolean leap(Calendar calendar, long year) {
        return switch (calendar) {
            case GREGORIAN -> year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
            case JULIAN -> year % 4 == 0;
            case ISLAMIC -> Set.of(2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29).contains(Math.floorMod(year, 30));
            case HEBREW -> Math.floorMod(7 * year + 1, 19) < 7;
            case PERSIAN -> (Math.floorMod(year - 474, 2820) + 474 + 38) * 682 % 2816 < 682;
            case COPTIC, ETHIOPIC -> Math.floorMod(year, 4) == 3;
            case FRENCH -> year % 4 == 0 && !Set.of(100, 200, 300).contains(Math.floorMod(year, 400)) && year % 4000 != 0;
            case ISO -> weeks(year) == 53;
            default -> throw new IllegalArgumentException("no years in " + calendar);
        };
    }
    static int weeks(long year) {
        return (int) ((start(Calendar.ISO, year + 1) - start(Calendar.ISO, year)) / 7);
    }
    static long monthsBefore(long year) {
        return Math.floorDiv(235 * year - 234, 19);
    }
    static Molad molad(long year) {
        long quantity = 5604 + 765433 * monthsBefore(year);
        long day = Math.floorDiv(quantity, 25920);
        int parts = Math.floorMod(quantity, 25920);
        int weekday = Math.floorMod(day - 1373427, 7);
        List<String> rules = new ArrayList<>();
        long postponed = day;
        if (parts >= 19440) {
            postponed += 1;
            rules.add("ZAKEN");
        } else if (!leap(Calendar.HEBREW, year) && weekday == 2 && parts >= 9924) {
            postponed += 2;
            rules.add("GATARAD");
        } else if (leap(Calendar.HEBREW, year - 1) && weekday == 1 && parts >= 16789) {
            postponed += 1;
            rules.add("BETUTAKPAT");
        }
        if (Set.of(0, 3, 5).contains(Math.floorMod(postponed - 1373427, 7))) {
            postponed += 1;
            rules.add("ADU");
        }
        return new Molad(day, parts, postponed - 1373427, rules);
    }
    static long start(Calendar calendar, long year) {
        long previous = year - 1;
        return switch (calendar) {
            case GREGORIAN -> 365 * previous + previous / 4 - previous / 100 + previous / 400 + 1;
            case JULIAN -> 365 * previous + previous / 4 - 1;
            case ISLAMIC -> 227015 + 354 * previous + (3 + 11 * year) / 30;
            case HEBREW -> molad(year).start();
            case PERSIAN -> {
                long a = year - 474;
                long b = Math.floorMod(a, 2820) + 474;
                yield 226896 + 1029983 * Math.floorDiv(a, 2820) + 365 * (b - 1) + (682 * b - 110) / 2816;
            }
            case COPTIC -> 103605 + 365 * previous + year / 4;
            case ETHIOPIC -> 2796 + 365 * previous + year / 4;
            case FRENCH -> 654415 + 365 * previous + previous / 4 - previous / 100 + previous / 400 - previous / 4000;
            case ISO -> {
                long januaryFour = start(Calendar.GREGORIAN, year) + 3;
                yield januaryFour - (januaryFour - 1) % 7;
            }
            default -> throw new IllegalArgumentException("no years in " + calendar);
        };
    }
    static String yearType(long year) {
        long length = start(Calendar.HEBREW, year + 1) - start(Calendar.HEBREW, year);
        if (length == 353 || length == 383) return "DEFICIENT";
        if (length == 354 || length == 384) return "REGULAR";
        return "COMPLETE";
    }
    static List<String> names(Calendar calendar, long year) {
        if (calendar == Calendar.HEBREW && leap(calendar, year)) return HEBREW_LEAP_NAMES;
        return MONTH_NAMES.get(calendar);
    }
    static int[] lengths(Calendar calendar, long year) {
        int extra = leap(calendar, year) ? 1 : 0;
        return switch (calendar) {
            case GREGORIAN, JULIAN -> new int[]{31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
            case ISLAMIC -> new int[]{30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra};
            case PERSIAN -> new int[]{31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29 + extra};
            case COPTIC, ETHIOPIC, FRENCH -> new int[]{30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 5 + extra};
            case HEBREW -> {
                String kind = yearType(year);
                int heshvan = kind.equals("COMPLETE") ? 30 : 29;
                int kislev = kind.equals("DEFICIENT") ? 29 : 30;
                if (extra == 1) yield new int[]{30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29};
                yield new int[]{30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29};
            }
            default -> throw new IllegalArgumentException("no months in " + calendar);
        };
    }
    static long fixedDate(Calendar calendar, long year, int month, int day) {
        if (calendar == Calendar.ISO) return start(calendar, year) + 7 * (month - 1) + day - 1;
        return start(calendar, year) + Arrays.stream(lengths(calendar, year), 0, month - 1).sum() + day - 1;
    }
    static long yearOf(Calendar calendar, long fixed) {
        if (fixed < start(calendar, 1)) return 0;
        long low = 1, high = 100000;
        while (low + 1 < high) {
            long middle = (low + high) / 2;
            if (start(calendar, middle) <= fixed) low = middle;
            else high = middle;
        }
        return low;
    }
    static Parts partsOf(Calendar calendar, long fixed) {
        long year = yearOf(calendar, fixed);
        if (year == 0) return null;
        int offset = (int) (fixed - start(calendar, year));
        if (calendar == Calendar.ISO) return new Parts(year, offset / 7 + 1, offset % 7 + 1);
        int[] days = lengths(calendar, year);
        int month = 0;
        while (offset >= days[month]) {
            offset -= days[month];
            month++;
        }
        return new Parts(year, month + 1, offset + 1);
    }
    static String formatDate(Calendar calendar, long fixed) {
        if (!inRange(fixed)) return "OUT OF RANGE";
        if (YEAR_CALENDARS.contains(calendar)) {
            Parts parts = partsOf(calendar, fixed);
            if (parts == null) return "OUT OF RANGE";
            String pattern = calendar == Calendar.ISO ? "%04d-W%02d-%d" : "%04d-%02d-%02d";
            return String.format(Locale.ROOT, pattern, parts.year(), parts.month(), parts.day());
        }
        if (calendar == Calendar.JD) return Long.toString(fixed + 1721425);
        if (calendar == Calendar.FIXED) return Long.toString(fixed);
        long count = fixed + 1137142;
        String longCount = LongStream.of(count / 144000, count / 7200 % 20, count / 360 % 20, count / 20 % 18, count % 20)
            .mapToObj(Long::toString).collect(Collectors.joining("."));
        long haab = (count + 348) % 365;
        return longCount + " " + ((count + 3) % 13 + 1) + " " + TZ.get((int) ((count + 19) % 20)) + " " +
            haab % 20 + " " + HB.get((int) (haab / 20));
    }
    static long parseDate(Calendar calendar, String text) {
        long fixed;
        if (YMD.contains(calendar)) {
            if (!text.matches("[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}")) throw new DateError("FORMAT");
            String[] fields = text.split("-");
            long year = Long.parseLong(fields[0]);
            int month = Integer.parseInt(fields[1]), day = Integer.parseInt(fields[2]);
            if (year == 0) throw new DateError("YEAR");
            int[] days = lengths(calendar, year);
            if (month < 1 || month > days.length) throw new DateError("MONTH");
            if (day < 1 || day > days[month - 1]) throw new DateError("DAY");
            fixed = fixedDate(calendar, year, month, day);
        } else if (calendar == Calendar.ISO) {
            if (!text.matches("[0-9]{1,5}-W[0-9]{1,2}-[0-9]")) throw new DateError("FORMAT");
            String[] fields = text.split("-");
            long year = Long.parseLong(fields[0]);
            int week = Integer.parseInt(fields[1].substring(1)), day = Integer.parseInt(fields[2]);
            if (year == 0) throw new DateError("YEAR");
            if (week < 1 || week > weeks(year)) throw new DateError("WEEK");
            if (day < 1 || day > 7) throw new DateError("DAY");
            fixed = fixedDate(calendar, year, week, day);
        } else if (calendar == Calendar.MAYAN) {
            if (!text.matches("[0-9]{1,2}(?:\\.[0-9]{1,2}){4}")) throw new DateError("FORMAT");
            int[] v = Arrays.stream(text.split("\\.")).mapToInt(Integer::parseInt).toArray();
            if (v[1] > 19 || v[2] > 19 || v[3] > 17 || v[4] > 19) throw new DateError("FIELD");
            fixed = (((v[0] * 20L + v[1]) * 20 + v[2]) * 18 + v[3]) * 20 + v[4] - 1137142;
        } else {
            if (!text.matches("-?[0-9]{1,8}")) throw new DateError("FORMAT");
            fixed = Long.parseLong(text) - (calendar == Calendar.JD ? 1721425 : 0);
        }
        if (!inRange(fixed)) throw new DateError("RANGE");
        return fixed;
    }
    static long monthIndex(Calendar calendar, long year) {
        if (calendar == Calendar.HEBREW) return monthsBefore(year);
        return MONTH_NAMES.get(calendar).size() * (year - 1);
    }
    static OptionalLong shift(Calendar calendar, long fixed, long years, long months) {
        Parts parts = partsOf(calendar, fixed);
        long targetYear = parts.year() + years;
        if (calendar == Calendar.ISO) {
            if (targetYear < 1 || targetYear > 99999) return OptionalLong.empty();
            return OptionalLong.of(fixedDate(calendar, targetYear, Math.min(parts.month(), weeks(targetYear)), parts.day()));
        }
        int month = parts.month();
        if (calendar == Calendar.HEBREW) {
            String oldName = names(calendar, parts.year()).get(month - 1);
            List<String> newNames = names(calendar, targetYear);
            if (!newNames.contains(oldName)) oldName = oldName.equals("Adar") ? "AdarII" : "Adar";
            month = newNames.indexOf(oldName) + 1;
        }
        long absolute = monthIndex(calendar, targetYear) + month - 1 + months;
        long finalYear;
        if (calendar == Calendar.HEBREW) {
            finalYear = Math.floorDiv(19 * absolute + 234, 235);
            while (monthIndex(calendar, finalYear) > absolute) finalYear--;
            while (monthIndex(calendar, finalYear + 1) <= absolute) finalYear++;
        } else {
            finalYear = Math.floorDiv(absolute, MONTH_NAMES.get(calendar).size()) + 1;
        }
        if (finalYear < 1 || finalYear > 99999) return OptionalLong.empty();
        int finalMonth = (int) (absolute - monthIndex(calendar, finalYear) + 1);
        int finalDay = Math.min(parts.day(), lengths(calendar, finalYear)[finalMonth - 1]);
        return OptionalLong.of(fixedDate(calendar, finalYear, finalMonth, finalDay));
    }
    static Period monthBounds(Calendar calendar, long year, int month) {
        int[] days = lengths(calendar, year);
        if (month < 1 || month > days.length) throw new DateError("MONTH");
        long first = fixedDate(calendar, year, month, 1);
        return new Period(first, first + days[month - 1] - 1);
    }
    static List<YearStart> newYears(Calendar calendar, long first, long last) {
        long year = Math.max(1, yearOf(calendar, first));
        while (start(calendar, year) < first) year++;
        List<YearStart> result = new ArrayList<>();
        for (; start(calendar, year) <= last; year++) result.add(new YearStart(year, start(calendar, year)));
        return result;
    }
    static Easter easter(int year, Calendar calendar) {
        int golden = year % 19;
        int epact;
        if (calendar == Calendar.GREGORIAN) {
            int century = year / 100 + 1;
            epact = Math.floorMod(14 + 11 * golden - 3 * century / 4 + (5 + 8 * century) / 25, 30);
            if (epact == 0 || epact == 1 && golden > 10) epact++;
        } else {
            epact = (14 + 11 * golden) % 30;
        }
        long moon = fixedDate(calendar, year, 4, 19) - epact;
        long sunday = moon + 7 - moon % 7;
        int index = Math.floorMod(-start(calendar, year), 7);
        String letters = String.valueOf("ABCDEFG".charAt(index));
        if (leap(calendar, year)) letters += "ABCDEFG".charAt(Math.floorMod(index - 1, 7));
        return new Easter(epact, letters, moon, sunday);
    }
    static List<String> holidayLines(int year) {
        long first = start(Calendar.GREGORIAN, year), last = start(Calendar.GREGORIAN, year + 1) - 1;
        long gregorianEaster = easter(year, Calendar.GREGORIAN).sunday();
        long orthodoxEaster = easter(year, Calendar.JULIAN).sunday();
        List<Entry> entries = new ArrayList<>();
        List<Map.Entry<String, Integer>> movable = List.of(Map.entry("AshWednesday", -46), Map.entry("GoodFriday", -2),
            Map.entry("Easter", 0), Map.entry("Ascension", 39), Map.entry("Pentecost", 49));
        for (int order = 0; order < movable.size(); order++) {
            entries.add(new Entry(gregorianEaster + movable.get(order).getValue(), order, movable.get(order).getKey(), Calendar.GREGORIAN));
        }
        entries.add(new Entry(orthodoxEaster, 5, "OrthodoxEaster", Calendar.JULIAN));
        for (int order = 0; order < HOLIDAYS.size(); order++) {
            Holiday holiday = HOLIDAYS.get(order);
            Calendar calendar = holiday.calendar();
            for (long candidateYear = Math.max(1, yearOf(calendar, first)); start(calendar, candidateYear) <= last; candidateYear++) {
                String actualName = holiday.month();
                if (calendar == Calendar.HEBREW && actualName.equals("Adar") && leap(calendar, candidateYear)) actualName = "AdarII";
                int month = names(calendar, candidateYear).indexOf(actualName) + 1;
                if (holiday.day() <= lengths(calendar, candidateYear)[month - 1]) {
                    long fixed = fixedDate(calendar, candidateYear, month, holiday.day());
                    if (first <= fixed && fixed <= last) entries.add(new Entry(fixed, order + 6, holiday.name(), calendar));
                }
            }
        }
        entries.sort(Comparator.comparingLong(Entry::fixed).thenComparingInt(Entry::order));
        return entries.stream().map(entry -> formatDate(Calendar.GREGORIAN, entry.fixed()) + " " + weekdayName(entry.fixed()) + " " +
            entry.name() + " " + entry.calendar() + " " + formatDate(entry.calendar(), entry.fixed())).toList();
    }
    static boolean validYear(String text) {
        return text.matches("[0-9]{1,5}") && Integer.parseInt(text) >= 1;
    }
    static boolean isCalendar(String text, Set<Calendar> allowed) {
        return allowed.stream().anyMatch(calendar -> calendar.name().equals(text));
    }
    static void validateArguments(String command, String[] args) {
        if (command.equals("EASTER") || command.equals("COMPUTUS")) {
            require(validYear(args[0]) && (args[1].equals("GREGORIAN") || args[1].equals("JULIAN")));
            return;
        }
        if (List.of("PASSOVER", "HOLIDAYS", "MOLAD").contains(command)) {
            require(validYear(args[0]));
            return;
        }
        Set<Calendar> allowed = CALENDARS;
        if (List.of("INFO", "MONTHS", "MONTHCAL", "NTH", "SPAN").contains(command)) allowed = YMD;
        else if (command.equals("LEAP") || command.equals("NEWYEAR")) allowed = YEAR_CALENDARS;
        require(isCalendar(args[0], allowed));
        switch (command) {
            case "CONVERT" -> require(args[2].equals("TO") && isCalendar(args[3], CALENDARS));
            case "DIFF" -> require(isCalendar(args[2], CALENDARS));
            case "LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR" -> {
                require(validYear(args[1]));
                if (command.equals("MONTHCAL") || command.equals("NTH")) require(args[2].matches("[0-9]{1,2}"));
                if (command.equals("NTH")) {
                    require(List.of("1", "2", "3", "4", "5", "LAST").contains(args[3]));
                    require(WEEKDAYS.contains(args[4]));
                }
            }
            case "COUNT" -> require(WEEKDAYS.contains(args[3]));
            case "ADD" -> {
                require(args[2].matches("-?[0-9]{1,7}"));
                require(List.of("DAYS", "WEEKS", "MONTHS", "YEARS").contains(args[3]));
                Calendar calendar = Calendar.valueOf(args[0]);
                if (args[3].equals("MONTHS")) require(YMD.contains(calendar));
                if (args[3].equals("YEARS")) require(YEAR_CALENDARS.contains(calendar));
            }
            case "ROUND" -> {
                require(args[2].matches("[0-9]{1,2}"));
                int number = Integer.parseInt(args[2]);
                require(number >= 1 && number <= 13 && TZ.contains(args[3]));
                require(args[4].matches("[0-9]{1,2}"));
                require(HB.contains(args[5]));
                require(Integer.parseInt(args[4]) <= (args[5].equals("Uayeb") ? 4 : 19));
            }
            default -> {}
        }
    }
    static List<String> calendarLines(Calendar calendar, long year, int month) {
        Period bounds = monthBounds(calendar, year, month);
        long first = bounds.first(), last = bounds.last();
        if (!inRange(first) || !inRange(last)) return List.of("OUT OF RANGE");
        List<String> result = new ArrayList<>();
        result.add(names(calendar, year).get(month - 1) + " " + year + " (" + formatDate(Calendar.GREGORIAN, first) + " to " +
            formatDate(Calendar.GREGORIAN, last) + ")");
        result.add("Mo Tu We Th Fr Sa Su");
        for (long cursor = first - (first - 1) % 7; cursor <= last; cursor += 7) {
            result.add(LongStream.range(cursor, cursor + 7)
                .mapToObj(fixed -> first <= fixed && fixed <= last ? String.format(Locale.ROOT, "%2d", fixed - first + 1) : "  ")
                .collect(Collectors.joining(" ")).stripTrailing());
        }
        return result;
    }
    static String spanText(Calendar calendar, long first, long last) {
        long from = Math.min(first, last), to = Math.max(first, last);
        long low = 0, high = partsOf(calendar, to).year() - partsOf(calendar, from).year() + 2;
        while (low + 1 < high) {
            long middle = (low + high) / 2;
            OptionalLong shifted = shift(calendar, from, middle, 0);
            if (shifted.isPresent() && shifted.getAsLong() <= to) low = middle;
            else high = middle;
        }
        long years = low;
        low = 0;
        high = 32;
        while (low + 1 < high) {
            long middle = (low + high) / 2;
            OptionalLong shifted = shift(calendar, from, years, middle);
            if (shifted.isPresent() && shifted.getAsLong() <= to) low = middle;
            else high = middle;
        }
        long months = low;
        long days = to - shift(calendar, from, years, months).getAsLong();
        return (first > last ? "-" : "") + years + "y " + months + "m " + days + "d";
    }
    static String roundDate(Calendar calendar, long fixed, int number, String tzName, int day, String month) {
        int targetTz = TZ.indexOf(tzName);
        int targetHaab = HB.indexOf(month) * 20 + day;
        long candidate = fixed;
        while ((candidate + 1137142 + 3) % 13 + 1 != number || (candidate + 1137142 + 19) % 20 != targetTz) candidate++;
        for (; candidate <= fixed + 18979; candidate += 260) {
            if ((candidate + 1137142 + 348) % 365 == targetHaab) return formatDate(calendar, candidate);
        }
        return "NONE";
    }
    static List<String> execute(String command, String[] args) {
        validateArguments(command, args);
        if (command.equals("EASTER") || command.equals("COMPUTUS")) {
            int year = Integer.parseInt(args[0]);
            if (year > 9999) return List.of("OUT OF RANGE");
            Calendar kind = Calendar.valueOf(args[1]);
            Easter easter = easter(year, kind);
            if (command.equals("EASTER")) return List.of(formatDate(Calendar.GREGORIAN, easter.sunday()));
            return List.of("golden=" + (year % 19 + 1) + " epact=" + easter.epact() + " letters=" + easter.letters() +
                " moon=" + formatDate(kind, easter.moon()) + " easter=" + formatDate(kind, easter.sunday()));
        }
        if (List.of("PASSOVER", "HOLIDAYS", "MOLAD").contains(command)) {
            int year = Integer.parseInt(args[0]);
            if (command.equals("MOLAD")) {
                Molad molad = molad(year);
                if (!inRange(molad.start())) return List.of("OUT OF RANGE");
                String applied = molad.rules().isEmpty() ? "NONE" : String.join("+", molad.rules());
                return List.of(weekdayName(molad.day() - 1373427) + " " + molad.parts() / 1080 + "h " + molad.parts() % 1080 + "p " +
                    applied + " " + weekdayName(molad.start()) + " " + formatDate(Calendar.GREGORIAN, molad.start()));
            }
            if (year > 9999) return List.of("OUT OF RANGE");
            if (command.equals("HOLIDAYS")) return holidayLines(year);
            long hebrewYear = year + 3760;
            int month = names(Calendar.HEBREW, hebrewYear).indexOf("Nisan") + 1;
            long fixed = fixedDate(Calendar.HEBREW, hebrewYear, month, 15);
            return List.of(formatDate(Calendar.GREGORIAN, fixed) + " " + weekdayName(fixed));
        }
        Calendar calendar = Calendar.valueOf(args[0]);
        if (List.of("LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR").contains(command)) {
            long year = Long.parseLong(args[1]);
            return switch (command) {
                case "LEAP" -> {
                    String text = (leap(calendar, year) ? "YES " : "NO ") + (start(calendar, year + 1) - start(calendar, year));
                    yield List.of(calendar == Calendar.HEBREW ? text + " " + yearType(year) : text);
                }
                case "MONTHS" -> {
                    List<String> monthNames = names(calendar, year);
                    int[] days = lengths(calendar, year);
                    List<String> items = new ArrayList<>();
                    for (int i = 0; i < days.length; i++) items.add(monthNames.get(i) + "=" + days[i]);
                    yield List.of(String.join(" ", items));
                }
                case "NEWYEAR" -> {
                    if (year > 9999) yield List.of("OUT OF RANGE");
                    List<YearStart> entries = newYears(calendar, start(Calendar.GREGORIAN, year), start(Calendar.GREGORIAN, year + 1) - 1);
                    if (entries.isEmpty()) yield List.of("NONE");
                    yield List.of(entries.stream().map(entry -> entry.year() + ":" + formatDate(Calendar.GREGORIAN, entry.fixed()))
                        .collect(Collectors.joining(" ")));
                }
                case "MONTHCAL" -> calendarLines(calendar, year, Integer.parseInt(args[2]));
                default -> {
                    Period bounds = monthBounds(calendar, year, Integer.parseInt(args[2]));
                    int weekday = WEEKDAYS.indexOf(args[4]);
                    long fixed;
                    if (args[3].equals("LAST")) fixed = bounds.last() - Math.floorMod(bounds.last() - weekday, 7);
                    else fixed = bounds.first() + Math.floorMod(weekday - bounds.first(), 7) + 7L * (Integer.parseInt(args[3]) - 1);
                    yield List.of(fixed > bounds.last() ? "NONE" : formatDate(calendar, fixed));
                }
            };
        }
        if (command.equals("VALID")) {
            try {
                return List.of("YES " + formatDate(calendar, parseDate(calendar, args[1])));
            } catch (DateError error) {
                return List.of("NO " + error.getMessage());
            }
        }
        long first = parseDate(calendar, args[1]);
        return switch (command) {
            case "DIFF" -> List.of(Long.toString(parseDate(Calendar.valueOf(args[2]), args[3]) - first));
            case "COUNT" -> {
                long last = parseDate(calendar, args[2]);
                long low = Math.min(first, last), high = Math.max(first, last);
                long occurrence = low + Math.floorMod(WEEKDAYS.indexOf(args[3]) - low, 7);
                yield List.of(Long.toString(occurrence > high ? 0 : (high - occurrence) / 7 + 1));
            }
            case "SPAN" -> List.of(spanText(calendar, first, parseDate(calendar, args[2])));
            case "CONVERT" -> List.of(formatDate(Calendar.valueOf(args[3]), first));
            case "WEEKDAY" -> List.of(weekdayName(first));
            case "ALL" -> {
                List<String> result = new ArrayList<>();
                for (Calendar target : Calendar.values()) {
                    String text = formatDate(target, first);
                    if (YMD.contains(target) && !text.equals("OUT OF RANGE")) {
                        Parts parts = partsOf(target, first);
                        text += " " + names(target, parts.year()).get(parts.month() - 1);
                    }
                    result.add(target + " " + text);
                }
                yield result;
            }
            case "INFO" -> {
                Parts parts = partsOf(calendar, first);
                String weekday = weekdayName(first);
                if (calendar == Calendar.FRENCH) weekday = parts.month() <= 12 ? DC.get((parts.day() - 1) % 10) : FS.get(parts.day() - 1);
                long ordinal = first - start(calendar, parts.year()) + 1;
                long length = start(calendar, parts.year() + 1) - start(calendar, parts.year());
                yield List.of(weekday + " " + parts.day() + " " + names(calendar, parts.year()).get(parts.month() - 1) + " " +
                    parts.year() + " day=" + ordinal + "/" + length);
            }
            case "ROUND" -> List.of(roundDate(calendar, first, Integer.parseInt(args[2]), args[3], Integer.parseInt(args[4]), args[5]));
            default -> {
                int amount = Integer.parseInt(args[2]);
                OptionalLong result = switch (args[3]) {
                    case "DAYS" -> OptionalLong.of(first + amount);
                    case "WEEKS" -> OptionalLong.of(first + 7L * amount);
                    case "YEARS" -> shift(calendar, first, amount, 0);
                    default -> shift(calendar, first, 0, amount);
                };
                yield List.of(result.isPresent() ? formatDate(calendar, result.getAsLong()) : "OUT OF RANGE");
            }
        };
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int count = Integer.parseInt(input.readLine());
        for (int i = 0; i < count; i++) {
            String[] words = input.readLine().split(" ");
            String command = words[0];
            String[] arguments = Arrays.copyOfRange(words, 1, words.length);
            List<String> lines;
            if (ARITY.getOrDefault(command, -1) != arguments.length) {
                lines = List.of("INVALID COMMAND");
            } else {
                try {
                    lines = execute(command, arguments);
                } catch (CommandError error) {
                    lines = List.of("INVALID COMMAND");
                } catch (DateError error) {
                    lines = List.of(error.getMessage().equals("RANGE") ? "OUT OF RANGE" : "INVALID DATE");
                }
            }
            lines.forEach(output::println);
        }
        output.flush();
    }
}
