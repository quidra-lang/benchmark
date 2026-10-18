import java.util.Locale

private enum class Calendar { GREGORIAN, JULIAN, ISO, ISLAMIC, HEBREW, PERSIAN, COPTIC, ETHIOPIC, FRENCH, MAYAN, JD, FIXED }
private data class Molad(val day: Long, val parts: Int, val start: Long, val rules: List<String>)
private data class Parts(val year: Long, val month: Int, val day: Int)
private data class Easter(val epact: Int, val letters: String, val moon: Long, val sunday: Long)
private data class Holiday(val name: String, val calendar: Calendar, val month: String, val day: Int)
private data class Entry(val fixed: Long, val order: Int, val name: String, val calendar: Calendar)
private class DateError(val reason: String) : Exception(reason)
private class CommandError : Exception()

private val CALENDARS = Calendar.entries.toSet()
private val YMD = CALENDARS - setOf(Calendar.ISO, Calendar.MAYAN, Calendar.JD, Calendar.FIXED)
private val YEAR_CALENDARS = YMD + Calendar.ISO
private val WEEKDAYS = words("Sunday Monday Tuesday Wednesday Thursday Friday Saturday")
private val TZ = words("Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau")
private val HB = words("Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb")
private val DC = words("Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi")
private val FS = words("Vertu Genie Travail Opinion Recompenses Revolution")
private const val MAX_FIXED = 3652059L
private val ROMAN_MONTHS = words("January February March April May June July August September October November December")
private val MONTH_NAMES = mapOf(
    Calendar.GREGORIAN to ROMAN_MONTHS,
    Calendar.JULIAN to ROMAN_MONTHS,
    Calendar.ISLAMIC to words("Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah"),
    Calendar.HEBREW to words("Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul"),
    Calendar.PERSIAN to words("Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand"),
    Calendar.COPTIC to words("Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie"),
    Calendar.ETHIOPIC to words("Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume"),
    Calendar.FRENCH to words("Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides"),
)
private val HEBREW_LEAP_NAMES = words("Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul")
private val HOLIDAYS = listOf(
    Holiday("Christmas", Calendar.GREGORIAN, "December", 25),
    Holiday("OrthodoxChristmas", Calendar.JULIAN, "December", 25),
    Holiday("RoshHashanah", Calendar.HEBREW, "Tishri", 1),
    Holiday("YomKippur", Calendar.HEBREW, "Tishri", 10),
    Holiday("Sukkot", Calendar.HEBREW, "Tishri", 15),
    Holiday("Hanukkah", Calendar.HEBREW, "Kislev", 25),
    Holiday("Purim", Calendar.HEBREW, "Adar", 14),
    Holiday("Passover", Calendar.HEBREW, "Nisan", 15),
    Holiday("Shavuot", Calendar.HEBREW, "Sivan", 6),
    Holiday("IslamicNewYear", Calendar.ISLAMIC, "Muharram", 1),
    Holiday("Ashura", Calendar.ISLAMIC, "Muharram", 10),
    Holiday("Mawlid", Calendar.ISLAMIC, "RabiI", 12),
    Holiday("RamadanStart", Calendar.ISLAMIC, "Ramadan", 1),
    Holiday("EidAlFitr", Calendar.ISLAMIC, "Shawwal", 1),
    Holiday("EidAlAdha", Calendar.ISLAMIC, "DhuAlHijjah", 10),
    Holiday("Nowruz", Calendar.PERSIAN, "Farvardin", 1),
    Holiday("SizdahBedar", Calendar.PERSIAN, "Farvardin", 13),
    Holiday("Yalda", Calendar.PERSIAN, "Azar", 30),
    Holiday("Nayrouz", Calendar.COPTIC, "Thout", 1),
    Holiday("CopticChristmas", Calendar.COPTIC, "Koiak", 29),
    Holiday("Enkutatash", Calendar.ETHIOPIC, "Meskerem", 1),
    Holiday("Meskel", Calendar.ETHIOPIC, "Meskerem", 17),
    Holiday("Timkat", Calendar.ETHIOPIC, "Ter", 11),
    Holiday("RepublicDay", Calendar.FRENCH, "Vendemiaire", 1),
    Holiday("RevolutionDay", Calendar.FRENCH, "Sansculottides", 6),
)
private val ARITY = mapOf(
    "CONVERT" to 4, "ALL" to 2, "VALID" to 2, "WEEKDAY" to 2, "INFO" to 2,
    "LEAP" to 2, "MONTHS" to 2, "MONTHCAL" to 3, "NTH" to 5, "NEWYEAR" to 2,
    "DIFF" to 4, "COUNT" to 4, "ADD" to 4, "SPAN" to 3, "EASTER" to 2,
    "COMPUTUS" to 2, "PASSOVER" to 1, "HOLIDAYS" to 1, "MOLAD" to 1, "ROUND" to 6,
)

private fun words(text: String) = text.split(" ")

private fun ensure(condition: Boolean) {
    if (!condition) throw CommandError()
}

private fun inRange(fixed: Long) = fixed in 1..MAX_FIXED

private fun weekdayName(fixed: Long) = WEEKDAYS[fixed.mod(7)]

private fun leap(calendar: Calendar, year: Long): Boolean = when (calendar) {
    Calendar.GREGORIAN -> year.mod(4) == 0 && (year.mod(100) != 0 || year.mod(400) == 0)
    Calendar.JULIAN -> year.mod(4) == 0
    Calendar.ISLAMIC -> year.mod(30) in setOf(2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29)
    Calendar.HEBREW -> (7 * year + 1).mod(19) < 7
    Calendar.PERSIAN -> ((year - 474).mod(2820) + 474 + 38) * 682 % 2816 < 682
    Calendar.COPTIC, Calendar.ETHIOPIC -> year.mod(4) == 3
    Calendar.FRENCH -> year.mod(4) == 0 && year.mod(400) !in setOf(100, 200, 300) && year.mod(4000) != 0
    Calendar.ISO -> weeks(year) == 53
    else -> throw IllegalArgumentException("no years in $calendar")
}

private fun weeks(year: Long) = ((start(Calendar.ISO, year + 1) - start(Calendar.ISO, year)) / 7).toInt()

private fun monthsBefore(year: Long) = (235 * year - 234).floorDiv(19)

private fun molad(year: Long): Molad {
    val quantity = 5604 + 765433 * monthsBefore(year)
    val day = quantity.floorDiv(25920)
    val parts = quantity.mod(25920)
    val weekday = (day - 1373427).mod(7)
    val rules = mutableListOf<String>()
    var postponed = day
    if (parts >= 19440) {
        postponed += 1
        rules.add("ZAKEN")
    } else if (!leap(Calendar.HEBREW, year) && weekday == 2 && parts >= 9924) {
        postponed += 2
        rules.add("GATARAD")
    } else if (leap(Calendar.HEBREW, year - 1) && weekday == 1 && parts >= 16789) {
        postponed += 1
        rules.add("BETUTAKPAT")
    }
    if ((postponed - 1373427).mod(7) in setOf(0, 3, 5)) {
        postponed += 1
        rules.add("ADU")
    }
    return Molad(day, parts, postponed - 1373427, rules)
}

private fun start(calendar: Calendar, year: Long): Long {
    val previous = year - 1
    return when (calendar) {
        Calendar.GREGORIAN -> 365 * previous + previous / 4 - previous / 100 + previous / 400 + 1
        Calendar.JULIAN -> 365 * previous + previous / 4 - 1
        Calendar.ISLAMIC -> 227015 + 354 * previous + (3 + 11 * year) / 30
        Calendar.HEBREW -> molad(year).start
        Calendar.PERSIAN -> {
            val a = year - 474
            val b = a.mod(2820) + 474
            226896 + 1029983 * a.floorDiv(2820) + 365 * (b - 1) + (682 * b - 110) / 2816
        }
        Calendar.COPTIC -> 103605 + 365 * previous + year / 4
        Calendar.ETHIOPIC -> 2796 + 365 * previous + year / 4
        Calendar.FRENCH -> 654415 + 365 * previous + previous / 4 - previous / 100 + previous / 400 - previous / 4000
        Calendar.ISO -> {
            val januaryFour = start(Calendar.GREGORIAN, year) + 3
            januaryFour - (januaryFour - 1) % 7
        }
        else -> throw IllegalArgumentException("no years in $calendar")
    }
}

private fun yearType(year: Long) = when (start(Calendar.HEBREW, year + 1) - start(Calendar.HEBREW, year)) {
    353L, 383L -> "DEFICIENT"
    354L, 384L -> "REGULAR"
    else -> "COMPLETE"
}

private fun names(calendar: Calendar, year: Long): List<String> =
    if (calendar == Calendar.HEBREW && leap(calendar, year)) HEBREW_LEAP_NAMES else MONTH_NAMES.getValue(calendar)

private fun lengths(calendar: Calendar, year: Long): List<Int> {
    val extra = if (leap(calendar, year)) 1 else 0
    return when (calendar) {
        Calendar.GREGORIAN, Calendar.JULIAN -> listOf(31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
        Calendar.ISLAMIC -> listOf(30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra)
        Calendar.PERSIAN -> List(6) { 31 } + List(5) { 30 } + (29 + extra)
        Calendar.COPTIC, Calendar.ETHIOPIC, Calendar.FRENCH -> List(12) { 30 } + (5 + extra)
        Calendar.HEBREW -> {
            val kind = yearType(year)
            val heshvan = if (kind == "COMPLETE") 30 else 29
            val kislev = if (kind == "DEFICIENT") 29 else 30
            if (extra == 1) listOf(30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29)
            else listOf(30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29)
        }
        else -> throw IllegalArgumentException("no months in $calendar")
    }
}

private fun fixedDate(calendar: Calendar, year: Long, month: Int, day: Int): Long {
    if (calendar == Calendar.ISO) return start(calendar, year) + 7 * (month - 1) + day - 1
    return start(calendar, year) + lengths(calendar, year).take(month - 1).sum() + day - 1
}

private fun yearOf(calendar: Calendar, fixed: Long): Long {
    if (fixed < start(calendar, 1)) return 0
    var low = 1L
    var high = 100000L
    while (low + 1 < high) {
        val middle = (low + high) / 2
        if (start(calendar, middle) <= fixed) low = middle else high = middle
    }
    return low
}

private fun partsOf(calendar: Calendar, fixed: Long): Parts? {
    val year = yearOf(calendar, fixed)
    if (year == 0L) return null
    var offset = (fixed - start(calendar, year)).toInt()
    if (calendar == Calendar.ISO) return Parts(year, offset / 7 + 1, offset % 7 + 1)
    for ((index, days) in lengths(calendar, year).withIndex()) {
        if (offset < days) return Parts(year, index + 1, offset + 1)
        offset -= days
    }
    error("calendar year length")
}

private fun formatDate(calendar: Calendar, fixed: Long): String {
    if (!inRange(fixed)) return "OUT OF RANGE"
    if (calendar in YEAR_CALENDARS) {
        val (year, month, day) = partsOf(calendar, fixed) ?: return "OUT OF RANGE"
        val pattern = if (calendar == Calendar.ISO) "%04d-W%02d-%d" else "%04d-%02d-%02d"
        return pattern.format(Locale.ROOT, year, month, day)
    }
    if (calendar == Calendar.JD) return (fixed + 1721425).toString()
    if (calendar == Calendar.FIXED) return fixed.toString()
    val count = fixed + 1137142
    val longCount = listOf(count / 144000, count / 7200 % 20, count / 360 % 20, count / 20 % 18, count % 20).joinToString(".")
    val haab = (count + 348).mod(365)
    return "$longCount ${(count + 3) % 13 + 1} ${TZ[(count + 19).mod(20)]} ${haab % 20} ${HB[haab / 20]}"
}

private fun parseDate(calendar: Calendar, text: String): Long {
    val fixed = when (calendar) {
        in YMD -> {
            if (!Regex("[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}").matches(text)) throw DateError("FORMAT")
            val (yearText, monthText, dayText) = text.split("-")
            val year = yearText.toLong()
            val month = monthText.toInt()
            val day = dayText.toInt()
            if (year == 0L) throw DateError("YEAR")
            val days = lengths(calendar, year)
            if (month !in 1..days.size) throw DateError("MONTH")
            if (day !in 1..days[month - 1]) throw DateError("DAY")
            fixedDate(calendar, year, month, day)
        }
        Calendar.ISO -> {
            if (!Regex("[0-9]{1,5}-W[0-9]{1,2}-[0-9]").matches(text)) throw DateError("FORMAT")
            val (yearText, weekText, dayText) = text.split("-")
            val year = yearText.toLong()
            val week = weekText.drop(1).toInt()
            val day = dayText.toInt()
            if (year == 0L) throw DateError("YEAR")
            if (week !in 1..weeks(year)) throw DateError("WEEK")
            if (day !in 1..7) throw DateError("DAY")
            fixedDate(calendar, year, week, day)
        }
        Calendar.MAYAN -> {
            if (!Regex("[0-9]{1,2}(?:\\.[0-9]{1,2}){4}").matches(text)) throw DateError("FORMAT")
            val (b, k, t, u, n) = text.split(".").map { it.toLong() }
            if (k > 19 || t > 19 || u > 17 || n > 19) throw DateError("FIELD")
            (((b * 20 + k) * 20 + t) * 18 + u) * 20 + n - 1137142
        }
        else -> {
            if (!Regex("-?[0-9]{1,8}").matches(text)) throw DateError("FORMAT")
            text.toLong() - (if (calendar == Calendar.JD) 1721425 else 0)
        }
    }
    if (!inRange(fixed)) throw DateError("RANGE")
    return fixed
}

private fun monthIndex(calendar: Calendar, year: Long): Long =
    if (calendar == Calendar.HEBREW) monthsBefore(year) else MONTH_NAMES.getValue(calendar).size * (year - 1)

private fun shift(calendar: Calendar, fixed: Long, years: Int, months: Int): Long? {
    val (year, month, day) = partsOf(calendar, fixed)!!
    val targetYear = year + years
    if (calendar == Calendar.ISO) {
        if (targetYear !in 1L..99999L) return null
        return fixedDate(calendar, targetYear, minOf(month, weeks(targetYear)), day)
    }
    var targetMonth = month
    if (calendar == Calendar.HEBREW) {
        var name = names(calendar, year)[month - 1]
        val newNames = names(calendar, targetYear)
        if (name !in newNames) name = if (name == "Adar") "AdarII" else "Adar"
        targetMonth = newNames.indexOf(name) + 1
    }
    val absolute = monthIndex(calendar, targetYear) + targetMonth - 1 + months
    var finalYear: Long
    if (calendar == Calendar.HEBREW) {
        finalYear = (19 * absolute + 234).floorDiv(235)
        while (monthIndex(calendar, finalYear) > absolute) finalYear--
        while (monthIndex(calendar, finalYear + 1) <= absolute) finalYear++
    } else {
        finalYear = absolute.floorDiv(MONTH_NAMES.getValue(calendar).size) + 1
    }
    if (finalYear !in 1L..99999L) return null
    val finalMonth = (absolute - monthIndex(calendar, finalYear) + 1).toInt()
    val finalDay = minOf(day, lengths(calendar, finalYear)[finalMonth - 1])
    return fixedDate(calendar, finalYear, finalMonth, finalDay)
}

private fun monthBounds(calendar: Calendar, year: Long, month: Int): LongRange {
    val days = lengths(calendar, year)
    if (month !in 1..days.size) throw DateError("MONTH")
    val first = fixedDate(calendar, year, month, 1)
    return first..first + days[month - 1] - 1
}

private fun newYears(calendar: Calendar, first: Long, last: Long): List<Pair<Long, Long>> {
    var year = maxOf(1, yearOf(calendar, first))
    while (start(calendar, year) < first) year++
    val result = mutableListOf<Pair<Long, Long>>()
    while (start(calendar, year) <= last) {
        result.add(year to start(calendar, year))
        year++
    }
    return result
}

private fun easter(year: Long, calendar: Calendar): Easter {
    val golden = year.mod(19)
    var epact: Int
    if (calendar == Calendar.GREGORIAN) {
        val century = year / 100 + 1
        epact = (14 + 11 * golden - 3 * century / 4 + (5 + 8 * century) / 25).mod(30)
        if (epact == 0 || epact == 1 && golden > 10) epact++
    } else {
        epact = (14 + 11 * golden) % 30
    }
    val moon = fixedDate(calendar, year, 4, 19) - epact
    val sunday = moon + 7 - moon % 7
    val index = (-start(calendar, year)).mod(7)
    var letters = "ABCDEFG"[index].toString()
    if (leap(calendar, year)) letters += "ABCDEFG"[(index - 1).mod(7)]
    return Easter(epact, letters, moon, sunday)
}

private fun holidayLines(year: Long): List<String> {
    val first = start(Calendar.GREGORIAN, year)
    val last = start(Calendar.GREGORIAN, year + 1) - 1
    val gregorianEaster = easter(year, Calendar.GREGORIAN).sunday
    val orthodoxEaster = easter(year, Calendar.JULIAN).sunday
    val movable = listOf("AshWednesday" to -46, "GoodFriday" to -2, "Easter" to 0, "Ascension" to 39, "Pentecost" to 49)
    val entries = movable.mapIndexed { order, (name, offset) ->
        Entry(gregorianEaster + offset, order, name, Calendar.GREGORIAN)
    }.toMutableList()
    entries.add(Entry(orthodoxEaster, 5, "OrthodoxEaster", Calendar.JULIAN))
    for ((index, holiday) in HOLIDAYS.withIndex()) {
        val calendar = holiday.calendar
        var candidateYear = maxOf(1, yearOf(calendar, first))
        while (start(calendar, candidateYear) <= last) {
            var actualName = holiday.month
            if (calendar == Calendar.HEBREW && actualName == "Adar" && leap(calendar, candidateYear)) actualName = "AdarII"
            val month = names(calendar, candidateYear).indexOf(actualName) + 1
            if (holiday.day <= lengths(calendar, candidateYear)[month - 1]) {
                val fixed = fixedDate(calendar, candidateYear, month, holiday.day)
                if (fixed in first..last) entries.add(Entry(fixed, index + 6, holiday.name, calendar))
            }
            candidateYear++
        }
    }
    return entries.sortedWith(compareBy({ it.fixed }, { it.order })).map {
        "${formatDate(Calendar.GREGORIAN, it.fixed)} ${weekdayName(it.fixed)} ${it.name} ${it.calendar} ${formatDate(it.calendar, it.fixed)}"
    }
}

private fun validYear(text: String) = Regex("[0-9]{1,5}").matches(text) && text.toInt() >= 1

private fun isCalendar(text: String, allowed: Set<Calendar>) = allowed.any { it.name == text }

private fun validateArguments(command: String, args: List<String>) {
    if (command == "EASTER" || command == "COMPUTUS") {
        ensure(validYear(args[0]) && args[1] in setOf("GREGORIAN", "JULIAN"))
        return
    }
    if (command in setOf("PASSOVER", "HOLIDAYS", "MOLAD")) {
        ensure(validYear(args[0]))
        return
    }
    val allowed = when (command) {
        "INFO", "MONTHS", "MONTHCAL", "NTH", "SPAN" -> YMD
        "LEAP", "NEWYEAR" -> YEAR_CALENDARS
        else -> CALENDARS
    }
    ensure(isCalendar(args[0], allowed))
    when (command) {
        "CONVERT" -> ensure(args[2] == "TO" && isCalendar(args[3], CALENDARS))
        "DIFF" -> ensure(isCalendar(args[2], CALENDARS))
        "LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR" -> {
            ensure(validYear(args[1]))
            if (command == "MONTHCAL" || command == "NTH") ensure(Regex("[0-9]{1,2}").matches(args[2]))
            if (command == "NTH") {
                ensure(args[3] in setOf("1", "2", "3", "4", "5", "LAST"))
                ensure(args[4] in WEEKDAYS)
            }
        }
        "COUNT" -> ensure(args[3] in WEEKDAYS)
        "ADD" -> {
            ensure(Regex("-?[0-9]{1,7}").matches(args[2]))
            ensure(args[3] in setOf("DAYS", "WEEKS", "MONTHS", "YEARS"))
            val calendar = Calendar.valueOf(args[0])
            if (args[3] == "MONTHS") ensure(calendar in YMD)
            if (args[3] == "YEARS") ensure(calendar in YEAR_CALENDARS)
        }
        "ROUND" -> {
            ensure(Regex("[0-9]{1,2}").matches(args[2]))
            ensure(args[2].toInt() in 1..13 && args[3] in TZ)
            ensure(Regex("[0-9]{1,2}").matches(args[4]))
            ensure(args[5] in HB)
            ensure(args[4].toInt() <= (if (args[5] == "Uayeb") 4 else 19))
        }
    }
}

private fun calendarLines(calendar: Calendar, year: Long, month: Int): List<String> {
    val bounds = monthBounds(calendar, year, month)
    if (!inRange(bounds.first) || !inRange(bounds.last)) return listOf("OUT OF RANGE")
    val result = mutableListOf(
        "${names(calendar, year)[month - 1]} $year " +
            "(${formatDate(Calendar.GREGORIAN, bounds.first)} to ${formatDate(Calendar.GREGORIAN, bounds.last)})",
        "Mo Tu We Th Fr Sa Su",
    )
    var cursor = bounds.first - (bounds.first - 1) % 7
    while (cursor <= bounds.last) {
        val fields = (cursor until cursor + 7).map { if (it in bounds) (it - bounds.first + 1).toString().padStart(2) else "  " }
        result.add(fields.joinToString(" ").trimEnd())
        cursor += 7
    }
    return result
}

private fun spanText(calendar: Calendar, first: Long, last: Long): String {
    val from = minOf(first, last)
    val to = maxOf(first, last)
    var low = 0
    var high = (partsOf(calendar, to)!!.year - partsOf(calendar, from)!!.year + 2).toInt()
    while (low + 1 < high) {
        val middle = (low + high) / 2
        val shifted = shift(calendar, from, middle, 0)
        if (shifted != null && shifted <= to) low = middle else high = middle
    }
    val years = low
    low = 0
    high = 32
    while (low + 1 < high) {
        val middle = (low + high) / 2
        val shifted = shift(calendar, from, years, middle)
        if (shifted != null && shifted <= to) low = middle else high = middle
    }
    val months = low
    val days = to - shift(calendar, from, years, months)!!
    val sign = if (first > last) "-" else ""
    return "$sign${years}y ${months}m ${days}d"
}

private fun roundDate(calendar: Calendar, fixed: Long, number: Int, tzName: String, day: Int, month: String): String {
    val targetTz = TZ.indexOf(tzName)
    val targetHaab = HB.indexOf(month) * 20 + day
    var candidate = fixed
    while ((candidate + 1137142 + 3).mod(13) + 1 != number || (candidate + 1137142 + 19).mod(20) != targetTz) candidate++
    while (candidate <= fixed + 18979) {
        if ((candidate + 1137142 + 348).mod(365) == targetHaab) return formatDate(calendar, candidate)
        candidate += 260
    }
    return "NONE"
}

private fun execute(command: String, args: List<String>): List<String> {
    validateArguments(command, args)
    if (command == "EASTER" || command == "COMPUTUS") {
        val year = args[0].toLong()
        if (year > 9999) return listOf("OUT OF RANGE")
        val kind = Calendar.valueOf(args[1])
        val (epact, letters, moon, sunday) = easter(year, kind)
        if (command == "EASTER") return listOf(formatDate(Calendar.GREGORIAN, sunday))
        return listOf(
            "golden=${year % 19 + 1} epact=$epact letters=$letters " +
                "moon=${formatDate(kind, moon)} easter=${formatDate(kind, sunday)}"
        )
    }
    if (command in setOf("PASSOVER", "HOLIDAYS", "MOLAD")) {
        val year = args[0].toLong()
        if (command == "MOLAD") {
            val (day, parts, fixed, rules) = molad(year)
            if (!inRange(fixed)) return listOf("OUT OF RANGE")
            val applied = if (rules.isEmpty()) "NONE" else rules.joinToString("+")
            return listOf(
                "${weekdayName(day - 1373427)} ${parts / 1080}h ${parts % 1080}p $applied " +
                    "${weekdayName(fixed)} ${formatDate(Calendar.GREGORIAN, fixed)}"
            )
        }
        if (year > 9999) return listOf("OUT OF RANGE")
        if (command == "HOLIDAYS") return holidayLines(year)
        val hebrewYear = year + 3760
        val month = names(Calendar.HEBREW, hebrewYear).indexOf("Nisan") + 1
        val fixed = fixedDate(Calendar.HEBREW, hebrewYear, month, 15)
        return listOf("${formatDate(Calendar.GREGORIAN, fixed)} ${weekdayName(fixed)}")
    }
    val calendar = Calendar.valueOf(args[0])
    if (command in setOf("LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR")) {
        val year = args[1].toLong()
        return when (command) {
            "LEAP" -> {
                var text = "${if (leap(calendar, year)) "YES" else "NO"} ${start(calendar, year + 1) - start(calendar, year)}"
                if (calendar == Calendar.HEBREW) text += " ${yearType(year)}"
                listOf(text)
            }
            "MONTHS" -> listOf(names(calendar, year).zip(lengths(calendar, year)).joinToString(" ") { (name, days) -> "$name=$days" })
            "NEWYEAR" -> {
                if (year > 9999) return listOf("OUT OF RANGE")
                val entries = newYears(calendar, start(Calendar.GREGORIAN, year), start(Calendar.GREGORIAN, year + 1) - 1)
                listOf(entries.joinToString(" ") { (y, f) -> "$y:${formatDate(Calendar.GREGORIAN, f)}" }.ifEmpty { "NONE" })
            }
            "MONTHCAL" -> calendarLines(calendar, year, args[2].toInt())
            else -> {
                val bounds = monthBounds(calendar, year, args[2].toInt())
                val weekday = WEEKDAYS.indexOf(args[4])
                val fixed = if (args[3] == "LAST") bounds.last - (bounds.last - weekday).mod(7)
                else bounds.first + (weekday - bounds.first).mod(7) + 7 * (args[3].toInt() - 1)
                listOf(if (fixed > bounds.last) "NONE" else formatDate(calendar, fixed))
            }
        }
    }
    if (command == "VALID") {
        return try {
            listOf("YES " + formatDate(calendar, parseDate(calendar, args[1])))
        } catch (error: DateError) {
            listOf("NO " + error.reason)
        }
    }
    val first = parseDate(calendar, args[1])
    return when (command) {
        "DIFF" -> listOf((parseDate(Calendar.valueOf(args[2]), args[3]) - first).toString())
        "COUNT" -> {
            val last = parseDate(calendar, args[2])
            val low = minOf(first, last)
            val high = maxOf(first, last)
            val occurrence = low + (WEEKDAYS.indexOf(args[3]) - low).mod(7)
            listOf((if (occurrence > high) 0 else (high - occurrence) / 7 + 1).toString())
        }
        "SPAN" -> listOf(spanText(calendar, first, parseDate(calendar, args[2])))
        "CONVERT" -> listOf(formatDate(Calendar.valueOf(args[3]), first))
        "WEEKDAY" -> listOf(weekdayName(first))
        "ALL" -> Calendar.entries.map { target ->
            var text = formatDate(target, first)
            if (target in YMD && text != "OUT OF RANGE") {
                val parts = partsOf(target, first)!!
                text += " " + names(target, parts.year)[parts.month - 1]
            }
            "$target $text"
        }
        "INFO" -> {
            val (year, month, day) = partsOf(calendar, first)!!
            var weekday = weekdayName(first)
            if (calendar == Calendar.FRENCH) weekday = if (month <= 12) DC[(day - 1) % 10] else FS[day - 1]
            val ordinal = first - start(calendar, year) + 1
            val length = start(calendar, year + 1) - start(calendar, year)
            listOf("$weekday $day ${names(calendar, year)[month - 1]} $year day=$ordinal/$length")
        }
        "ROUND" -> listOf(roundDate(calendar, first, args[2].toInt(), args[3], args[4].toInt(), args[5]))
        else -> {
            val amount = args[2].toInt()
            val result = when (args[3]) {
                "DAYS" -> first + amount
                "WEEKS" -> first + 7L * amount
                "YEARS" -> shift(calendar, first, amount, 0)
                else -> shift(calendar, first, 0, amount)
            }
            listOf(if (result == null) "OUT OF RANGE" else formatDate(calendar, result))
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    repeat(input.readLine().toInt()) {
        val words = input.readLine().split(" ")
        val command = words[0]
        val args = words.drop(1)
        val lines = if (ARITY[command] != args.size) {
            listOf("INVALID COMMAND")
        } else {
            try {
                execute(command, args)
            } catch (error: CommandError) {
                listOf("INVALID COMMAND")
            } catch (error: DateError) {
                listOf(if (error.reason == "RANGE") "OUT OF RANGE" else "INVALID DATE")
            }
        }
        for (line in lines) {
            output.write(line)
            output.newLine()
        }
    }
    output.flush()
}
