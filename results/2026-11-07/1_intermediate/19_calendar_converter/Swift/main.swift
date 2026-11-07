enum Calendar: String, CaseIterable {
    case gregorian = "GREGORIAN", julian = "JULIAN", iso = "ISO", islamic = "ISLAMIC", hebrew = "HEBREW", persian = "PERSIAN"
    case coptic = "COPTIC", ethiopic = "ETHIOPIC", french = "FRENCH", mayan = "MAYAN", jd = "JD", fixed = "FIXED"
}
enum CalendarError: Error {
    case invalidCommand
    case invalidDate(String)
}
typealias Parts = (year: Int, month: Int, day: Int)
typealias Entry = (fixed: Int, order: Int, name: String, calendar: Calendar)

let ymd = Set(Calendar.allCases).subtracting([.iso, .mayan, .jd, .fixed])
let yearCalendars = ymd.union([.iso])
let weekdays = words("Sunday Monday Tuesday Wednesday Thursday Friday Saturday")
let tzolkinNames = words("Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau")
let haabNames = words("Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb")
let decadeNames = words("Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi")
let festivalNames = words("Vertu Genie Travail Opinion Recompenses Revolution")
let maxFixed = 3652059
let romanMonths = words("January February March April May June July August September October November December")
let monthNames: [Calendar: [String]] = [
    .gregorian: romanMonths,
    .julian: romanMonths,
    .islamic: words("Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah"),
    .hebrew: words("Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul"),
    .persian: words("Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand"),
    .coptic: words("Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie"),
    .ethiopic: words("Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume"),
    .french: words("Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides"),
]
let hebrewLeapNames = words("Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul")
let holidays: [(name: String, calendar: Calendar, month: String, day: Int)] = [
    ("Christmas", .gregorian, "December", 25),
    ("OrthodoxChristmas", .julian, "December", 25),
    ("RoshHashanah", .hebrew, "Tishri", 1),
    ("YomKippur", .hebrew, "Tishri", 10),
    ("Sukkot", .hebrew, "Tishri", 15),
    ("Hanukkah", .hebrew, "Kislev", 25),
    ("Purim", .hebrew, "Adar", 14),
    ("Passover", .hebrew, "Nisan", 15),
    ("Shavuot", .hebrew, "Sivan", 6),
    ("IslamicNewYear", .islamic, "Muharram", 1),
    ("Ashura", .islamic, "Muharram", 10),
    ("Mawlid", .islamic, "RabiI", 12),
    ("RamadanStart", .islamic, "Ramadan", 1),
    ("EidAlFitr", .islamic, "Shawwal", 1),
    ("EidAlAdha", .islamic, "DhuAlHijjah", 10),
    ("Nowruz", .persian, "Farvardin", 1),
    ("SizdahBedar", .persian, "Farvardin", 13),
    ("Yalda", .persian, "Azar", 30),
    ("Nayrouz", .coptic, "Thout", 1),
    ("CopticChristmas", .coptic, "Koiak", 29),
    ("Enkutatash", .ethiopic, "Meskerem", 1),
    ("Meskel", .ethiopic, "Meskerem", 17),
    ("Timkat", .ethiopic, "Ter", 11),
    ("RepublicDay", .french, "Vendemiaire", 1),
    ("RevolutionDay", .french, "Sansculottides", 6),
]
let arity = [
    "CONVERT": 4, "ALL": 2, "VALID": 2, "WEEKDAY": 2, "INFO": 2,
    "LEAP": 2, "MONTHS": 2, "MONTHCAL": 3, "NTH": 5, "NEWYEAR": 2,
    "DIFF": 4, "COUNT": 4, "ADD": 4, "SPAN": 3, "EASTER": 2,
    "COMPUTUS": 2, "PASSOVER": 1, "HOLIDAYS": 1, "MOLAD": 1, "ROUND": 6,
]

func words(_ text: String) -> [String] {
    text.split(separator: " ").map(String.init)
}
func ensure(_ condition: Bool) throws {
    if !condition { throw CalendarError.invalidCommand }
}
func mod(_ value: Int, _ modulus: Int) -> Int {
    let remainder = value % modulus
    return remainder < 0 ? remainder + modulus : remainder
}
func floorDiv(_ value: Int, _ divisor: Int) -> Int {
    (value - mod(value, divisor)) / divisor
}
func padded(_ value: Int, _ width: Int, with filler: Character = "0") -> String {
    let text = String(value)
    return String(repeating: filler, count: max(0, width - text.count)) + text
}
func inRange(_ fixed: Int) -> Bool {
    (1...maxFixed).contains(fixed)
}
func weekdayName(_ fixed: Int) -> String {
    weekdays[mod(fixed, 7)]
}
func leap(_ calendar: Calendar, _ year: Int) -> Bool {
    switch calendar {
    case .gregorian: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    case .julian: return year % 4 == 0
    case .islamic: return [2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29].contains(mod(year, 30))
    case .hebrew: return mod(7 * year + 1, 19) < 7
    case .persian: return (mod(year - 474, 2820) + 474 + 38) * 682 % 2816 < 682
    case .coptic, .ethiopic: return mod(year, 4) == 3
    case .french: return year % 4 == 0 && ![100, 200, 300].contains(mod(year, 400)) && year % 4000 != 0
    case .iso: return weeks(year) == 53
    case .mayan, .jd, .fixed: preconditionFailure("no years in \(calendar.rawValue)")
    }
}
func weeks(_ year: Int) -> Int {
    (start(.iso, year + 1) - start(.iso, year)) / 7
}
func monthsBefore(_ year: Int) -> Int {
    floorDiv(235 * year - 234, 19)
}
func molad(_ year: Int) -> (day: Int, parts: Int, start: Int, rules: [String]) {
    let quantity = 5604 + 765433 * monthsBefore(year)
    let day = floorDiv(quantity, 25920), parts = mod(quantity, 25920)
    let weekday = mod(day - 1373427, 7)
    var rules: [String] = []
    var postponed = day
    if parts >= 19440 {
        postponed += 1
        rules.append("ZAKEN")
    } else if !leap(.hebrew, year) && weekday == 2 && parts >= 9924 {
        postponed += 2
        rules.append("GATARAD")
    } else if leap(.hebrew, year - 1) && weekday == 1 && parts >= 16789 {
        postponed += 1
        rules.append("BETUTAKPAT")
    }
    if [0, 3, 5].contains(mod(postponed - 1373427, 7)) {
        postponed += 1
        rules.append("ADU")
    }
    return (day, parts, postponed - 1373427, rules)
}
func start(_ calendar: Calendar, _ year: Int) -> Int {
    let previous = year - 1
    switch calendar {
    case .gregorian: return 365 * previous + previous / 4 - previous / 100 + previous / 400 + 1
    case .julian: return 365 * previous + previous / 4 - 1
    case .islamic: return 227015 + 354 * previous + (3 + 11 * year) / 30
    case .hebrew: return molad(year).start
    case .persian:
        let a = year - 474
        let b = mod(a, 2820) + 474
        return 226896 + 1029983 * floorDiv(a, 2820) + 365 * (b - 1) + (682 * b - 110) / 2816
    case .coptic: return 103605 + 365 * previous + year / 4
    case .ethiopic: return 2796 + 365 * previous + year / 4
    case .french: return 654415 + 365 * previous + previous / 4 - previous / 100 + previous / 400 - previous / 4000
    case .iso:
        let januaryFour = start(.gregorian, year) + 3
        return januaryFour - (januaryFour - 1) % 7
    case .mayan, .jd, .fixed: preconditionFailure("no years in \(calendar.rawValue)")
    }
}
func yearType(_ year: Int) -> String {
    switch start(.hebrew, year + 1) - start(.hebrew, year) {
    case 353, 383: return "DEFICIENT"
    case 354, 384: return "REGULAR"
    default: return "COMPLETE"
    }
}
func names(_ calendar: Calendar, _ year: Int) -> [String] {
    calendar == .hebrew && leap(calendar, year) ? hebrewLeapNames : monthNames[calendar]!
}
func lengths(_ calendar: Calendar, _ year: Int) -> [Int] {
    let extra = leap(calendar, year) ? 1 : 0
    switch calendar {
    case .gregorian, .julian: return [31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    case .islamic: return [30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra]
    case .persian: return Array(repeating: 31, count: 6) + Array(repeating: 30, count: 5) + [29 + extra]
    case .coptic, .ethiopic, .french: return Array(repeating: 30, count: 12) + [5 + extra]
    case .hebrew:
        let kind = yearType(year)
        let heshvan = kind == "COMPLETE" ? 30 : 29
        let kislev = kind == "DEFICIENT" ? 29 : 30
        if extra == 1 { return [30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29] }
        return [30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29]
    case .iso, .mayan, .jd, .fixed: preconditionFailure("no months in \(calendar.rawValue)")
    }
}
func fixedDate(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int) -> Int {
    if calendar == .iso { return start(calendar, year) + 7 * (month - 1) + day - 1 }
    return start(calendar, year) + lengths(calendar, year).prefix(month - 1).reduce(0, +) + day - 1
}
func yearOf(_ calendar: Calendar, _ fixed: Int) -> Int {
    if fixed < start(calendar, 1) { return 0 }
    var low = 1, high = 100000
    while low + 1 < high {
        let middle = (low + high) / 2
        if start(calendar, middle) <= fixed { low = middle } else { high = middle }
    }
    return low
}
func partsOf(_ calendar: Calendar, _ fixed: Int) -> Parts? {
    let year = yearOf(calendar, fixed)
    if year == 0 { return nil }
    var offset = fixed - start(calendar, year)
    if calendar == .iso { return (year, offset / 7 + 1, offset % 7 + 1) }
    for (index, days) in lengths(calendar, year).enumerated() {
        if offset < days { return (year, index + 1, offset + 1) }
        offset -= days
    }
    preconditionFailure("calendar year length")
}
func formatDate(_ calendar: Calendar, _ fixed: Int) -> String {
    if !inRange(fixed) { return "OUT OF RANGE" }
    if yearCalendars.contains(calendar) {
        guard let parts = partsOf(calendar, fixed) else { return "OUT OF RANGE" }
        if calendar == .iso { return "\(padded(parts.year, 4))-W\(padded(parts.month, 2))-\(parts.day)" }
        return "\(padded(parts.year, 4))-\(padded(parts.month, 2))-\(padded(parts.day, 2))"
    }
    if calendar == .jd { return String(fixed + 1721425) }
    if calendar == .fixed { return String(fixed) }
    let count = fixed + 1137142
    let longCount = [count / 144000, count / 7200 % 20, count / 360 % 20, count / 20 % 18, count % 20]
    let haab = (count + 348) % 365
    return longCount.map(String.init).joined(separator: ".") +
        " \((count + 3) % 13 + 1) \(tzolkinNames[(count + 19) % 20]) \(haab % 20) \(haabNames[haab / 20])"
}
func parseDate(_ calendar: Calendar, _ text: String) throws -> Int {
    let fixed: Int
    if ymd.contains(calendar) {
        guard text.wholeMatch(of: #/[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}/#) != nil else { throw CalendarError.invalidDate("FORMAT") }
        let fields = text.split(separator: "-").map { Int($0)! }
        let year = fields[0], month = fields[1], day = fields[2]
        if year == 0 { throw CalendarError.invalidDate("YEAR") }
        let days = lengths(calendar, year)
        guard (1...days.count).contains(month) else { throw CalendarError.invalidDate("MONTH") }
        guard (1...days[month - 1]).contains(day) else { throw CalendarError.invalidDate("DAY") }
        fixed = fixedDate(calendar, year, month, day)
    } else if calendar == .iso {
        guard text.wholeMatch(of: #/[0-9]{1,5}-W[0-9]{1,2}-[0-9]/#) != nil else { throw CalendarError.invalidDate("FORMAT") }
        let fields = text.split(separator: "-")
        let year = Int(fields[0])!, week = Int(fields[1].dropFirst())!, day = Int(fields[2])!
        if year == 0 { throw CalendarError.invalidDate("YEAR") }
        guard (1...weeks(year)).contains(week) else { throw CalendarError.invalidDate("WEEK") }
        guard (1...7).contains(day) else { throw CalendarError.invalidDate("DAY") }
        fixed = fixedDate(calendar, year, week, day)
    } else if calendar == .mayan {
        guard text.wholeMatch(of: #/[0-9]{1,2}(?:\.[0-9]{1,2}){4}/#) != nil else { throw CalendarError.invalidDate("FORMAT") }
        let v = text.split(separator: ".").map { Int($0)! }
        if v[1] > 19 || v[2] > 19 || v[3] > 17 || v[4] > 19 { throw CalendarError.invalidDate("FIELD") }
        fixed = (((v[0] * 20 + v[1]) * 20 + v[2]) * 18 + v[3]) * 20 + v[4] - 1137142
    } else {
        guard text.wholeMatch(of: #/-?[0-9]{1,8}/#) != nil else { throw CalendarError.invalidDate("FORMAT") }
        fixed = Int(text)! - (calendar == .jd ? 1721425 : 0)
    }
    guard inRange(fixed) else { throw CalendarError.invalidDate("RANGE") }
    return fixed
}
func monthIndex(_ calendar: Calendar, _ year: Int) -> Int {
    calendar == .hebrew ? monthsBefore(year) : monthNames[calendar]!.count * (year - 1)
}
func shift(_ calendar: Calendar, _ fixed: Int, _ years: Int, _ months: Int) -> Int? {
    let parts = partsOf(calendar, fixed)!
    let targetYear = parts.year + years
    if calendar == .iso {
        guard (1...99999).contains(targetYear) else { return nil }
        return fixedDate(calendar, targetYear, min(parts.month, weeks(targetYear)), parts.day)
    }
    var month = parts.month
    if calendar == .hebrew {
        var name = names(calendar, parts.year)[month - 1]
        let newNames = names(calendar, targetYear)
        if !newNames.contains(name) { name = name == "Adar" ? "AdarII" : "Adar" }
        month = newNames.firstIndex(of: name)! + 1
    }
    let absolute = monthIndex(calendar, targetYear) + month - 1 + months
    var finalYear: Int
    if calendar == .hebrew {
        finalYear = floorDiv(19 * absolute + 234, 235)
        while monthIndex(calendar, finalYear) > absolute { finalYear -= 1 }
        while monthIndex(calendar, finalYear + 1) <= absolute { finalYear += 1 }
    } else {
        finalYear = floorDiv(absolute, monthNames[calendar]!.count) + 1
    }
    guard (1...99999).contains(finalYear) else { return nil }
    let finalMonth = absolute - monthIndex(calendar, finalYear) + 1
    let finalDay = min(parts.day, lengths(calendar, finalYear)[finalMonth - 1])
    return fixedDate(calendar, finalYear, finalMonth, finalDay)
}
func monthBounds(_ calendar: Calendar, _ year: Int, _ month: Int) throws -> (first: Int, last: Int) {
    let days = lengths(calendar, year)
    guard (1...days.count).contains(month) else { throw CalendarError.invalidDate("MONTH") }
    let first = fixedDate(calendar, year, month, 1)
    return (first, first + days[month - 1] - 1)
}
func newYears(_ calendar: Calendar, _ first: Int, _ last: Int) -> [(year: Int, start: Int)] {
    var year = max(1, yearOf(calendar, first))
    while start(calendar, year) < first { year += 1 }
    var result: [(year: Int, start: Int)] = []
    while start(calendar, year) <= last {
        result.append((year, start(calendar, year)))
        year += 1
    }
    return result
}
func easter(_ year: Int, _ calendar: Calendar) -> (epact: Int, letters: String, moon: Int, sunday: Int) {
    let golden = year % 19
    var epact: Int
    if calendar == .gregorian {
        let century = year / 100 + 1
        epact = mod(14 + 11 * golden - 3 * century / 4 + (5 + 8 * century) / 25, 30)
        if epact == 0 || epact == 1 && golden > 10 { epact += 1 }
    } else {
        epact = (14 + 11 * golden) % 30
    }
    let moon = fixedDate(calendar, year, 4, 19) - epact
    let sunday = moon + 7 - moon % 7
    let alphabet = Array("ABCDEFG")
    let index = mod(-start(calendar, year), 7)
    var letters = String(alphabet[index])
    if leap(calendar, year) { letters.append(alphabet[mod(index - 1, 7)]) }
    return (epact, letters, moon, sunday)
}
func holidayLines(_ year: Int) -> [String] {
    let first = start(.gregorian, year), last = start(.gregorian, year + 1) - 1
    let gregorianEaster = easter(year, .gregorian).sunday
    let orthodoxEaster = easter(year, .julian).sunday
    let movable: [(name: String, offset: Int)] = [("AshWednesday", -46), ("GoodFriday", -2), ("Easter", 0), ("Ascension", 39), ("Pentecost", 49)]
    var entries: [Entry] = movable.enumerated().map { order, feast in
        (gregorianEaster + feast.offset, order, feast.name, .gregorian)
    }
    entries.append((orthodoxEaster, 5, "OrthodoxEaster", .julian))
    for (index, holiday) in holidays.enumerated() {
        let calendar = holiday.calendar
        var candidateYear = max(1, yearOf(calendar, first))
        while start(calendar, candidateYear) <= last {
            var actualName = holiday.month
            if calendar == .hebrew && actualName == "Adar" && leap(calendar, candidateYear) { actualName = "AdarII" }
            let month = names(calendar, candidateYear).firstIndex(of: actualName)! + 1
            if holiday.day <= lengths(calendar, candidateYear)[month - 1] {
                let fixed = fixedDate(calendar, candidateYear, month, holiday.day)
                if (first...last).contains(fixed) { entries.append((fixed, index + 6, holiday.name, calendar)) }
            }
            candidateYear += 1
        }
    }
    entries.sort { ($0.fixed, $0.order) < ($1.fixed, $1.order) }
    return entries.map {
        "\(formatDate(.gregorian, $0.fixed)) \(weekdayName($0.fixed)) \($0.name) \($0.calendar.rawValue) \(formatDate($0.calendar, $0.fixed))"
    }
}
func validYear(_ text: String) -> Bool {
    text.wholeMatch(of: #/[0-9]{1,5}/#) != nil && Int(text)! >= 1
}
func isCalendar(_ text: String, _ allowed: Set<Calendar>) -> Bool {
    allowed.contains { $0.rawValue == text }
}
func validateArguments(_ command: String, _ args: [String]) throws {
    if command == "EASTER" || command == "COMPUTUS" {
        try ensure(validYear(args[0]) && ["GREGORIAN", "JULIAN"].contains(args[1]))
        return
    }
    if ["PASSOVER", "HOLIDAYS", "MOLAD"].contains(command) {
        try ensure(validYear(args[0]))
        return
    }
    let allCalendars = Set(Calendar.allCases)
    var allowed = allCalendars
    if ["INFO", "MONTHS", "MONTHCAL", "NTH", "SPAN"].contains(command) {
        allowed = ymd
    } else if command == "LEAP" || command == "NEWYEAR" {
        allowed = yearCalendars
    }
    try ensure(isCalendar(args[0], allowed))
    switch command {
    case "CONVERT":
        try ensure(args[2] == "TO" && isCalendar(args[3], allCalendars))
    case "DIFF":
        try ensure(isCalendar(args[2], allCalendars))
    case "LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR":
        try ensure(validYear(args[1]))
        if command == "MONTHCAL" || command == "NTH" { try ensure(args[2].wholeMatch(of: #/[0-9]{1,2}/#) != nil) }
        if command == "NTH" {
            try ensure(["1", "2", "3", "4", "5", "LAST"].contains(args[3]))
            try ensure(weekdays.contains(args[4]))
        }
    case "COUNT":
        try ensure(weekdays.contains(args[3]))
    case "ADD":
        try ensure(args[2].wholeMatch(of: #/-?[0-9]{1,7}/#) != nil)
        try ensure(["DAYS", "WEEKS", "MONTHS", "YEARS"].contains(args[3]))
        let calendar = Calendar(rawValue: args[0])!
        if args[3] == "MONTHS" { try ensure(ymd.contains(calendar)) }
        if args[3] == "YEARS" { try ensure(yearCalendars.contains(calendar)) }
    case "ROUND":
        try ensure(args[2].wholeMatch(of: #/[0-9]{1,2}/#) != nil)
        try ensure((1...13).contains(Int(args[2])!) && tzolkinNames.contains(args[3]))
        try ensure(args[4].wholeMatch(of: #/[0-9]{1,2}/#) != nil)
        try ensure(haabNames.contains(args[5]))
        try ensure(Int(args[4])! <= (args[5] == "Uayeb" ? 4 : 19))
    default:
        break
    }
}
func calendarLines(_ calendar: Calendar, _ year: Int, _ month: Int) throws -> [String] {
    let (first, last) = try monthBounds(calendar, year, month)
    if !inRange(first) || !inRange(last) { return ["OUT OF RANGE"] }
    var result = [
        "\(names(calendar, year)[month - 1]) \(year) (\(formatDate(.gregorian, first)) to \(formatDate(.gregorian, last)))",
        "Mo Tu We Th Fr Sa Su",
    ]
    for cursor in stride(from: first - (first - 1) % 7, through: last, by: 7) {
        let fields = (cursor..<cursor + 7).map { day in
            (first...last).contains(day) ? padded(day - first + 1, 2, with: " ") : "  "
        }
        var line = fields.joined(separator: " ")
        while line.hasSuffix(" ") { line.removeLast() }
        result.append(line)
    }
    return result
}
func spanText(_ calendar: Calendar, _ first: Int, _ last: Int) -> String {
    let from = min(first, last), to = max(first, last)
    var low = 0, high = partsOf(calendar, to)!.year - partsOf(calendar, from)!.year + 2
    while low + 1 < high {
        let middle = (low + high) / 2
        if let shifted = shift(calendar, from, middle, 0), shifted <= to { low = middle } else { high = middle }
    }
    let years = low
    low = 0
    high = 32
    while low + 1 < high {
        let middle = (low + high) / 2
        if let shifted = shift(calendar, from, years, middle), shifted <= to { low = middle } else { high = middle }
    }
    let months = low
    let days = to - shift(calendar, from, years, months)!
    return "\(first > last ? "-" : "")\(years)y \(months)m \(days)d"
}
func roundDate(_ calendar: Calendar, _ fixed: Int, _ number: Int, _ tzName: String, _ day: Int, _ month: String) -> String {
    let targetTz = tzolkinNames.firstIndex(of: tzName)!
    let targetHaab = haabNames.firstIndex(of: month)! * 20 + day
    var candidate = fixed
    while (candidate + 1137142 + 3) % 13 + 1 != number || (candidate + 1137142 + 19) % 20 != targetTz { candidate += 1 }
    while candidate <= fixed + 18979 {
        if (candidate + 1137142 + 348) % 365 == targetHaab { return formatDate(calendar, candidate) }
        candidate += 260
    }
    return "NONE"
}
func execute(_ command: String, _ args: [String]) throws -> [String] {
    try validateArguments(command, args)
    if command == "EASTER" || command == "COMPUTUS" {
        let year = Int(args[0])!
        if year > 9999 { return ["OUT OF RANGE"] }
        let kind = Calendar(rawValue: args[1])!
        let (epact, letters, moon, sunday) = easter(year, kind)
        if command == "EASTER" { return [formatDate(.gregorian, sunday)] }
        return ["golden=\(year % 19 + 1) epact=\(epact) letters=\(letters) moon=\(formatDate(kind, moon)) easter=\(formatDate(kind, sunday))"]
    }
    if ["PASSOVER", "HOLIDAYS", "MOLAD"].contains(command) {
        let year = Int(args[0])!
        if command == "MOLAD" {
            let (day, parts, fixed, rules) = molad(year)
            if !inRange(fixed) { return ["OUT OF RANGE"] }
            let applied = rules.isEmpty ? "NONE" : rules.joined(separator: "+")
            return ["\(weekdayName(day - 1373427)) \(parts / 1080)h \(parts % 1080)p \(applied) \(weekdayName(fixed)) \(formatDate(.gregorian, fixed))"]
        }
        if year > 9999 { return ["OUT OF RANGE"] }
        if command == "HOLIDAYS" { return holidayLines(year) }
        let hebrewYear = year + 3760
        let month = names(.hebrew, hebrewYear).firstIndex(of: "Nisan")! + 1
        let fixed = fixedDate(.hebrew, hebrewYear, month, 15)
        return ["\(formatDate(.gregorian, fixed)) \(weekdayName(fixed))"]
    }
    let calendar = Calendar(rawValue: args[0])!
    if ["LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR"].contains(command) {
        let year = Int(args[1])!
        switch command {
        case "LEAP":
            var text = "\(leap(calendar, year) ? "YES" : "NO") \(start(calendar, year + 1) - start(calendar, year))"
            if calendar == .hebrew { text += " \(yearType(year))" }
            return [text]
        case "MONTHS":
            return [zip(names(calendar, year), lengths(calendar, year)).map { "\($0)=\($1)" }.joined(separator: " ")]
        case "NEWYEAR":
            if year > 9999 { return ["OUT OF RANGE"] }
            let entries = newYears(calendar, start(.gregorian, year), start(.gregorian, year + 1) - 1)
            if entries.isEmpty { return ["NONE"] }
            return [entries.map { "\($0.year):\(formatDate(.gregorian, $0.start))" }.joined(separator: " ")]
        case "MONTHCAL":
            return try calendarLines(calendar, year, Int(args[2])!)
        default:
            let (first, last) = try monthBounds(calendar, year, Int(args[2])!)
            let weekday = weekdays.firstIndex(of: args[4])!
            let fixed = args[3] == "LAST" ? last - mod(last - weekday, 7) : first + mod(weekday - first, 7) + 7 * (Int(args[3])! - 1)
            return [fixed > last ? "NONE" : formatDate(calendar, fixed)]
        }
    }
    if command == "VALID" {
        do {
            return ["YES " + formatDate(calendar, try parseDate(calendar, args[1]))]
        } catch CalendarError.invalidDate(let reason) {
            return ["NO " + reason]
        }
    }
    let first = try parseDate(calendar, args[1])
    switch command {
    case "DIFF":
        return [String(try parseDate(Calendar(rawValue: args[2])!, args[3]) - first)]
    case "COUNT":
        let last = try parseDate(calendar, args[2])
        let low = min(first, last), high = max(first, last)
        let occurrence = low + mod(weekdays.firstIndex(of: args[3])! - low, 7)
        return [String(occurrence > high ? 0 : (high - occurrence) / 7 + 1)]
    case "SPAN":
        return [spanText(calendar, first, try parseDate(calendar, args[2]))]
    case "CONVERT":
        return [formatDate(Calendar(rawValue: args[3])!, first)]
    case "WEEKDAY":
        return [weekdayName(first)]
    case "ALL":
        return Calendar.allCases.map { target in
            var text = formatDate(target, first)
            if ymd.contains(target) && text != "OUT OF RANGE" {
                let parts = partsOf(target, first)!
                text += " " + names(target, parts.year)[parts.month - 1]
            }
            return "\(target.rawValue) \(text)"
        }
    case "INFO":
        let (year, month, day) = partsOf(calendar, first)!
        var weekday = weekdayName(first)
        if calendar == .french { weekday = month <= 12 ? decadeNames[(day - 1) % 10] : festivalNames[day - 1] }
        let ordinal = first - start(calendar, year) + 1
        let length = start(calendar, year + 1) - start(calendar, year)
        return ["\(weekday) \(day) \(names(calendar, year)[month - 1]) \(year) day=\(ordinal)/\(length)"]
    case "ROUND":
        return [roundDate(calendar, first, Int(args[2])!, args[3], Int(args[4])!, args[5])]
    default:
        let amount = Int(args[2])!
        let result: Int?
        switch args[3] {
        case "DAYS": result = first + amount
        case "WEEKS": result = first + 7 * amount
        case "YEARS": result = shift(calendar, first, amount, 0)
        default: result = shift(calendar, first, 0, amount)
        }
        guard let result else { return ["OUT OF RANGE"] }
        return [formatDate(calendar, result)]
    }
}

let count = Int(readLine()!)!
for _ in 0..<count {
    let words = readLine()!.split(separator: " ").map(String.init)
    let command = words[0]
    let args = Array(words.dropFirst())
    let lines: [String]
    if arity[command] != args.count {
        lines = ["INVALID COMMAND"]
    } else {
        do {
            lines = try execute(command, args)
        } catch CalendarError.invalidCommand {
            lines = ["INVALID COMMAND"]
        } catch CalendarError.invalidDate(let reason) {
            lines = [reason == "RANGE" ? "OUT OF RANGE" : "INVALID DATE"]
        } catch {
            preconditionFailure("Unexpected error \(error)")
        }
    }
    for line in lines { print(line) }
}
