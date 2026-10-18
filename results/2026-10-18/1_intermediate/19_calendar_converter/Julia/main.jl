using Printf

const CALENDARS = split(
    "GREGORIAN JULIAN ISO ISLAMIC HEBREW PERSIAN COPTIC ETHIOPIC FRENCH MAYAN JD FIXED"
)
const YMD = Set([
    "GREGORIAN", "JULIAN", "ISLAMIC", "HEBREW", "PERSIAN",
    "COPTIC", "ETHIOPIC", "FRENCH"
])
const YEAR_CALENDARS = union(YMD, Set(["ISO"]))
const WEEKDAYS = split("Sunday Monday Tuesday Wednesday Thursday Friday Saturday")
const TZOLKIN = split(
    "Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau"
)
const HAAB = split(
    "Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb"
)
const DECADES = split("Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi")
const FESTIVALS = split("Vertu Genie Travail Opinion Recompenses Revolution")
const MAX_FIXED = 3652059
const MONTH_NAMES = Dict(
    "GREGORIAN" => split("January February March April May June July August September October November December"),
    "JULIAN" => split("January February March April May June July August September October November December"),
    "ISLAMIC" => split("Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah"),
    "HEBREW" => split("Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul"),
    "PERSIAN" => split("Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand"),
    "COPTIC" => split("Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie"),
    "ETHIOPIC" => split("Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume"),
    "FRENCH" => split("Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides")
)
const HEBREW_LEAP_NAMES = split(
    "Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul"
)
const ARITY = Dict(
    "CONVERT" => 4, "ALL" => 2, "VALID" => 2, "WEEKDAY" => 2,
    "INFO" => 2, "LEAP" => 2, "MONTHS" => 2, "MONTHCAL" => 3,
    "NTH" => 5, "NEWYEAR" => 2, "DIFF" => 4, "COUNT" => 4,
    "ADD" => 4, "SPAN" => 3, "EASTER" => 2, "COMPUTUS" => 2,
    "PASSOVER" => 1, "HOLIDAYS" => 1, "MOLAD" => 1, "ROUND" => 6
)

struct DateError <: Exception
    reason::String
end
struct CommandError <: Exception end

check(condition) = condition || throw(CommandError())
in_range(fixed::Int) = 1 <= fixed <= MAX_FIXED

function is_leap(calendar::String, year::Int)
    if calendar == "GREGORIAN"
        return mod(year, 4) == 0 && (mod(year, 100) != 0 || mod(year, 400) == 0)
    elseif calendar == "JULIAN"
        return mod(year, 4) == 0
    elseif calendar == "ISLAMIC"
        return mod(year, 30) in (2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29)
    elseif calendar == "HEBREW"
        return mod(7 * year + 1, 19) < 7
    elseif calendar == "PERSIAN"
        b = mod(year - 474, 2820) + 474
        return mod((b + 38) * 682, 2816) < 682
    elseif calendar in ("COPTIC", "ETHIOPIC")
        return mod(year, 4) == 3
    elseif calendar == "FRENCH"
        return mod(year, 4) == 0 &&
               !(mod(year, 400) in (100, 200, 300)) && mod(year, 4000) != 0
    end
    div(start_fixed("ISO", year + 1) - start_fixed("ISO", year), 7) == 53
end

months_before(year::Int) = fld(235 * year - 234, 19)

function molad(year::Int)
    quantity = 5604 + 765433 * months_before(year)
    day, parts = fldmod(quantity, 25920)
    weekday = mod(day - 1373427, 7)
    postponed = day
    rules = String[]
    if parts >= 19440
        postponed += 1
        push!(rules, "ZAKEN")
    elseif !is_leap("HEBREW", year) && weekday == 2 && parts >= 9924
        postponed += 2
        push!(rules, "GATARAD")
    elseif is_leap("HEBREW", year - 1) && weekday == 1 && parts >= 16789
        postponed += 1
        push!(rules, "BETUTAKPAT")
    end
    if mod(postponed - 1373427, 7) in (0, 3, 5)
        postponed += 1
        push!(rules, "ADU")
    end
    return (day=day, parts=parts, fixed=postponed - 1373427, rules=rules)
end

function start_fixed(calendar::String, year::Int)
    previous = year - 1
    if calendar == "GREGORIAN"
        return 365 * previous + fld(previous, 4) - fld(previous, 100) +
               fld(previous, 400) + 1
    elseif calendar == "JULIAN"
        return 365 * previous + fld(previous, 4) - 1
    elseif calendar == "ISLAMIC"
        return 227015 + 354 * previous + fld(3 + 11 * year, 30)
    elseif calendar == "HEBREW"
        return molad(year).fixed
    elseif calendar == "PERSIAN"
        a = year - 474
        b = mod(a, 2820) + 474
        return 226896 + 1029983 * fld(a, 2820) + 365 * (b - 1) +
               fld(682 * b - 110, 2816)
    elseif calendar == "COPTIC"
        return 103605 + 365 * previous + fld(year, 4)
    elseif calendar == "ETHIOPIC"
        return 2796 + 365 * previous + fld(year, 4)
    elseif calendar == "FRENCH"
        return 654415 + 365 * previous + fld(previous, 4) -
               fld(previous, 100) + fld(previous, 400) - fld(previous, 4000)
    end
    january_four = start_fixed("GREGORIAN", year) + 3
    january_four - mod(january_four - 1, 7)
end

function year_type(year::Int)
    length = start_fixed("HEBREW", year + 1) - start_fixed("HEBREW", year)
    if length in (353, 383)
        return "DEFICIENT"
    elseif length in (354, 384)
        return "REGULAR"
    end
    "COMPLETE"
end

function names_for(calendar::String, year::Int)
    calendar == "HEBREW" && is_leap(calendar, year) ?
        HEBREW_LEAP_NAMES : MONTH_NAMES[calendar]
end

function month_lengths(calendar::String, year::Int)
    extra = Int(is_leap(calendar, year))
    if calendar in ("GREGORIAN", "JULIAN")
        return [31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    elseif calendar == "ISLAMIC"
        return vcat(repeat([30, 29], 5), [30, 29 + extra])
    elseif calendar == "PERSIAN"
        return vcat(fill(31, 6), fill(30, 5), [29 + extra])
    elseif calendar in ("COPTIC", "ETHIOPIC", "FRENCH")
        return vcat(fill(30, 12), [5 + extra])
    end
    kind = year_type(year)
    heshvan = kind == "COMPLETE" ? 30 : 29
    kislev = kind == "DEFICIENT" ? 29 : 30
    if extra == 1
        return [30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29]
    end
    [30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29]
end

function fixed_date(calendar::String, year::Int, month::Int, day::Int)
    if calendar == "ISO"
        return start_fixed(calendar, year) + 7 * (month - 1) + day - 1
    end
    lengths = month_lengths(calendar, year)
    start_fixed(calendar, year) + sum(lengths[1:month-1]; init=0) + day - 1
end

function year_of(calendar::String, fixed::Int)
    fixed < start_fixed(calendar, 1) && return 0
    low, high = 1, 100000
    while low + 1 < high
        middle = fld(low + high, 2)
        if start_fixed(calendar, middle) <= fixed
            low = middle
        else
            high = middle
        end
    end
    low
end

function parts_of(calendar::String, fixed::Int)
    year = year_of(calendar, fixed)
    year == 0 && return nothing
    offset = fixed - start_fixed(calendar, year)
    if calendar == "ISO"
        return (year, fld(offset, 7) + 1, mod(offset, 7) + 1)
    end
    for (month, days) in enumerate(month_lengths(calendar, year))
        if offset < days
            return (year, month, offset + 1)
        end
        offset -= days
    end
    error("Calendar year has an inconsistent length")
end

function format_date(calendar::String, fixed::Int)
    in_range(fixed) || return "OUT OF RANGE"
    if calendar in YEAR_CALENDARS
        fields = parts_of(calendar, fixed)
        fields === nothing && return "OUT OF RANGE"
        year, month, day = fields
        if calendar == "ISO"
            return @sprintf("%04d-W%02d-%d", year, month, day)
        end
        return @sprintf("%04d-%02d-%02d", year, month, day)
    elseif calendar == "JD"
        return string(fixed + 1721425)
    elseif calendar == "FIXED"
        return string(fixed)
    end
    count = fixed + 1137142
    long_count = [
        fld(count, 144000), mod(fld(count, 7200), 20),
        mod(fld(count, 360), 20), mod(fld(count, 20), 18), mod(count, 20)
    ]
    tz_number = mod(count + 3, 13) + 1
    tz_name = TZOLKIN[mod(count + 19, 20) + 1]
    haab = mod(count + 348, 365)
    join(long_count, ".") * " $tz_number $tz_name " *
        string(mod(haab, 20)) * " " * HAAB[fld(haab, 20) + 1]
end

function parse_date(calendar::String, text::String)
    fixed = 0
    if calendar in YMD
        occursin(r"^[0-9]{1,5}-[0-9]{1,2}-[0-9]{1,2}$", text) ||
            throw(DateError("FORMAT"))
        year, month, day = parse.(Int, split(text, '-'))
        year != 0 || throw(DateError("YEAR"))
        lengths = month_lengths(calendar, year)
        1 <= month <= length(lengths) || throw(DateError("MONTH"))
        1 <= day <= lengths[month] || throw(DateError("DAY"))
        fixed = fixed_date(calendar, year, month, day)
    elseif calendar == "ISO"
        occursin(r"^[0-9]{1,5}-W[0-9]{1,2}-[0-9]$", text) ||
            throw(DateError("FORMAT"))
        year_text, week_text, day_text = split(text, '-')
        year = parse(Int, year_text)
        week = parse(Int, week_text[2:end])
        day = parse(Int, day_text)
        year != 0 || throw(DateError("YEAR"))
        weeks = div(start_fixed(calendar, year + 1) - start_fixed(calendar, year), 7)
        1 <= week <= weeks || throw(DateError("WEEK"))
        1 <= day <= 7 || throw(DateError("DAY"))
        fixed = fixed_date(calendar, year, week, day)
    elseif calendar == "MAYAN"
        occursin(r"^[0-9]{1,2}(\.[0-9]{1,2}){4}$", text) ||
            throw(DateError("FORMAT"))
        b, k, t, u, n = parse.(Int, split(text, '.'))
        k <= 19 && t <= 19 && u <= 17 && n <= 19 || throw(DateError("FIELD"))
        fixed = (((b * 20 + k) * 20 + t) * 18 + u) * 20 + n - 1137142
    else
        occursin(r"^-?[0-9]{1,8}$", text) || throw(DateError("FORMAT"))
        fixed = parse(Int, text) - (calendar == "JD" ? 1721425 : 0)
    end
    in_range(fixed) || throw(DateError("RANGE"))
    fixed
end

function month_index(calendar::String, year::Int)
    if calendar == "HEBREW"
        return months_before(year)
    end
    (calendar in ("COPTIC", "ETHIOPIC", "FRENCH") ? 13 : 12) * (year - 1)
end

function shift_date(calendar::String, fixed::Int, years::Int, months::Int)
    parts = parts_of(calendar, fixed)
    parts === nothing && return nothing
    year, month, day = parts
    target_year = year + years
    if calendar == "ISO"
        1 <= target_year <= 99999 || return nothing
        weeks = div(start_fixed(calendar, target_year + 1) -
                    start_fixed(calendar, target_year), 7)
        return fixed_date(calendar, target_year, min(month, weeks), day)
    end
    if calendar == "HEBREW"
        old_name = names_for(calendar, year)[month]
        new_names = names_for(calendar, target_year)
        if !(old_name in new_names)
            old_name = old_name == "Adar" ? "AdarII" : "Adar"
        end
        month = findfirst(==(old_name), new_names)
    end
    absolute = month_index(calendar, target_year) + month - 1 + months
    if calendar == "HEBREW"
        final_year = fld(19 * absolute + 234, 235)
        while month_index(calendar, final_year) > absolute
            final_year -= 1
        end
        while month_index(calendar, final_year + 1) <= absolute
            final_year += 1
        end
    else
        count = length(names_for(calendar, target_year))
        final_year = fld(absolute, count) + 1
    end
    1 <= final_year <= 99999 || return nothing
    final_month = absolute - month_index(calendar, final_year) + 1
    final_day = min(day, month_lengths(calendar, final_year)[final_month])
    fixed_date(calendar, final_year, final_month, final_day)
end

function month_bounds(calendar::String, year::Int, month::Int)
    lengths = month_lengths(calendar, year)
    1 <= month <= length(lengths) || throw(DateError("MONTH"))
    first = fixed_date(calendar, year, month, 1)
    (first, first + lengths[month] - 1)
end

function new_years(calendar::String, first::Int, last::Int)
    year = max(1, year_of(calendar, first))
    while start_fixed(calendar, year) < first
        year += 1
    end
    entries = String[]
    while start_fixed(calendar, year) <= last
        push!(entries, "$year:" * format_date("GREGORIAN", start_fixed(calendar, year)))
        year += 1
    end
    entries
end

function easter(year::Int, calendar::String)
    golden = mod(year, 19)
    if calendar == "GREGORIAN"
        century = fld(year, 100) + 1
        epact = mod(14 + 11 * golden - fld(3 * century, 4) +
                    fld(5 + 8 * century, 25), 30)
        if epact == 0 || (epact == 1 && golden > 10)
            epact += 1
        end
    else
        epact = mod(14 + 11 * golden, 30)
    end
    moon = fixed_date(calendar, year, 4, 19) - epact
    sunday = moon + 7 - mod(moon, 7)
    index = mod(-start_fixed(calendar, year), 7)
    letters = string("ABCDEFG"[index + 1])
    if is_leap(calendar, year)
        letters *= string("ABCDEFG"[mod(index - 1, 7) + 1])
    end
    (epact, letters, moon, sunday)
end

const HOLIDAYS = [
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
    ("RevolutionDay", "FRENCH", "Sansculottides", 6)
]

function holiday_lines(year::Int)
    first = start_fixed("GREGORIAN", year)
    last = start_fixed("GREGORIAN", year + 1) - 1
    western_easter = easter(year, "GREGORIAN")[4]
    orthodox_easter = easter(year, "JULIAN")[4]
    entries = Tuple{Int, Int, String, String}[]
    movable = [
        ("AshWednesday", -46), ("GoodFriday", -2), ("Easter", 0),
        ("Ascension", 39), ("Pentecost", 49)
    ]
    for (order, (name, offset)) in enumerate(movable)
        push!(entries, (western_easter + offset, order - 1, name, "GREGORIAN"))
    end
    push!(entries, (orthodox_easter, 5, "OrthodoxEaster", "JULIAN"))
    for (order, (name, calendar, month_name, day)) in enumerate(HOLIDAYS)
        candidate_year = max(1, year_of(calendar, first))
        while start_fixed(calendar, candidate_year) <= last
            name_in_year = calendar == "HEBREW" && month_name == "Adar" &&
                           is_leap(calendar, candidate_year) ? "AdarII" : month_name
            month = findfirst(==(name_in_year), names_for(calendar, candidate_year))
            if day <= month_lengths(calendar, candidate_year)[month]
                fixed = fixed_date(calendar, candidate_year, month, day)
                if first <= fixed <= last
                    push!(entries, (fixed, order + 5, name, calendar))
                end
            end
            candidate_year += 1
        end
    end
    sort!(entries)
    [
        format_date("GREGORIAN", fixed) * " " * WEEKDAYS[mod(fixed, 7) + 1] *
        " " * name * " " * calendar * " " * format_date(calendar, fixed)
        for (fixed, _, name, calendar) in entries
    ]
end

valid_year(text::String) = occursin(r"^[0-9]{1,5}$", text) && parse(Int, text) >= 1

function validate_arguments(command::String, args::Vector{String})
    if command in ("EASTER", "COMPUTUS")
        check(valid_year(args[1]) && args[2] in ("GREGORIAN", "JULIAN"))
        return
    elseif command in ("PASSOVER", "HOLIDAYS", "MOLAD")
        check(valid_year(args[1]))
        return
    end
    calendar = args[1]
    allowed = if command in ("INFO", "MONTHS", "MONTHCAL", "NTH", "SPAN")
        YMD
    elseif command in ("LEAP", "NEWYEAR")
        YEAR_CALENDARS
    else
        Set(CALENDARS)
    end
    check(calendar in allowed)
    if command == "CONVERT"
        check(args[3] == "TO" && args[4] in CALENDARS)
    elseif command == "DIFF"
        check(args[3] in CALENDARS)
    elseif command in ("LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR")
        check(valid_year(args[2]))
        if command in ("MONTHCAL", "NTH")
            check(occursin(r"^[0-9]{1,2}$", args[3]))
        end
        if command == "NTH"
            check(args[4] in ("1", "2", "3", "4", "5", "LAST"))
            check(args[5] in WEEKDAYS)
        end
    elseif command == "COUNT"
        check(args[4] in WEEKDAYS)
    elseif command == "ADD"
        check(occursin(r"^-?[0-9]{1,7}$", args[3]))
        check(args[4] in ("DAYS", "WEEKS", "MONTHS", "YEARS"))
        if args[4] == "MONTHS"
            check(calendar in YMD)
        elseif args[4] == "YEARS"
            check(calendar in YEAR_CALENDARS)
        end
    elseif command == "ROUND"
        check(occursin(r"^[0-9]{1,2}$", args[3]))
        check(1 <= parse(Int, args[3]) <= 13 && args[4] in TZOLKIN)
        check(occursin(r"^[0-9]{1,2}$", args[5]))
        check(args[6] in HAAB)
        check(parse(Int, args[5]) <= (args[6] == "Uayeb" ? 4 : 19))
    end
end

function calendar_lines(calendar::String, year::Int, month::Int)
    first, last = month_bounds(calendar, year, month)
    if !in_range(first) || !in_range(last)
        return ["OUT OF RANGE"]
    end
    title = string(names_for(calendar, year)[month], " ", year, " (",
                   format_date("GREGORIAN", first), " to ",
                   format_date("GREGORIAN", last), ")")
    result = [title, "Mo Tu We Th Fr Sa Su"]
    cursor = first - mod(first - 1, 7)
    while cursor <= last
        fields = [first <= fixed <= last ? @sprintf("%2d", fixed - first + 1) : "  "
                  for fixed in cursor:(cursor + 6)]
        push!(result, rstrip(join(fields, " ")))
        cursor += 7
    end
    result
end

function span_text(calendar::String, first::Int, last::Int)
    negative = first > last
    if negative
        first, last = last, first
    end
    start_year = parts_of(calendar, first)[1]
    end_year = parts_of(calendar, last)[1]
    low = 0
    high = end_year - start_year + 2
    while low + 1 < high
        middle = fld(low + high, 2)
        shifted = shift_date(calendar, first, middle, 0)
        if shifted !== nothing && shifted <= last
            low = middle
        else
            high = middle
        end
    end
    years = low
    low = 0
    high = 32
    while low + 1 < high
        middle = fld(low + high, 2)
        shifted = shift_date(calendar, first, years, middle)
        if shifted !== nothing && shifted <= last
            low = middle
        else
            high = middle
        end
    end
    months = low
    days = last - shift_date(calendar, first, years, months)
    string(negative ? "-" : "", years, "y ", months, "m ", days, "d")
end

function round_date(calendar::String, fixed::Int, number::Int,
                    tz_name::String, day::Int, month::String)
    target_tz = findfirst(==(tz_name), TZOLKIN) - 1
    target_haab = (findfirst(==(month), HAAB) - 1) * 20 + day
    candidate = fixed
    while true
        count = candidate + 1137142
        if mod(count + 3, 13) + 1 == number && mod(count + 19, 20) == target_tz
            break
        end
        candidate += 1
    end
    while candidate <= fixed + 18979
        if mod(candidate + 1137142 + 348, 365) == target_haab
            return format_date(calendar, candidate)
        end
        candidate += 260
    end
    "NONE"
end

function execute(command::String, args::Vector{String})
    validate_arguments(command, args)
    if command in ("EASTER", "COMPUTUS")
        year = parse(Int, args[1])
        year > 9999 && return ["OUT OF RANGE"]
        calendar = args[2]
        epact, letters, moon, sunday = easter(year, calendar)
        if command == "EASTER"
            return [format_date("GREGORIAN", sunday)]
        end
        return [
            "golden=$(mod(year, 19) + 1) epact=$epact letters=$letters " *
            "moon=$(format_date(calendar, moon)) easter=$(format_date(calendar, sunday))"
        ]
    end

    if command in ("PASSOVER", "HOLIDAYS", "MOLAD")
        year = parse(Int, args[1])
        if command == "MOLAD"
            record = molad(year)
            in_range(record.fixed) || return ["OUT OF RANGE"]
            applied = isempty(record.rules) ? "NONE" : join(record.rules, "+")
            return [
                string(WEEKDAYS[mod(record.day - 1373427, 7) + 1], " ",
                       fld(record.parts, 1080), "h ", mod(record.parts, 1080), "p ",
                       applied, " ", WEEKDAYS[mod(record.fixed, 7) + 1], " ",
                       format_date("GREGORIAN", record.fixed))
            ]
        end
        year > 9999 && return ["OUT OF RANGE"]
        command == "HOLIDAYS" && return holiday_lines(year)
        hebrew_year = year + 3760
        month = findfirst(==("Nisan"), names_for("HEBREW", hebrew_year))
        fixed = fixed_date("HEBREW", hebrew_year, month, 15)
        return [format_date("GREGORIAN", fixed) * " " * WEEKDAYS[mod(fixed, 7) + 1]]
    end

    calendar = args[1]
    if command in ("LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR")
        year = parse(Int, args[2])
        if command == "LEAP"
            result = string(is_leap(calendar, year) ? "YES" : "NO", " ",
                            start_fixed(calendar, year + 1) - start_fixed(calendar, year))
            calendar == "HEBREW" && (result *= " " * year_type(year))
            return [result]
        elseif command == "MONTHS"
            return [join(["$name=$days"
                          for (name, days) in zip(names_for(calendar, year),
                                                  month_lengths(calendar, year))], " ")]
        elseif command == "NEWYEAR"
            year > 9999 && return ["OUT OF RANGE"]
            first = start_fixed("GREGORIAN", year)
            last = start_fixed("GREGORIAN", year + 1) - 1
            entries = new_years(calendar, first, last)
            return [isempty(entries) ? "NONE" : join(entries, " ")]
        end
        month = parse(Int, args[3])
        command == "MONTHCAL" && return calendar_lines(calendar, year, month)
        first, last = month_bounds(calendar, year, month)
        weekday = findfirst(==(args[5]), WEEKDAYS) - 1
        fixed = if args[4] == "LAST"
            last - mod(last - weekday, 7)
        else
            first + mod(weekday - first, 7) + 7 * (parse(Int, args[4]) - 1)
        end
        return [fixed > last ? "NONE" : format_date(calendar, fixed)]
    end

    if command == "VALID"
        try
            fixed = parse_date(calendar, args[2])
            return ["YES " * format_date(calendar, fixed)]
        catch e
            if e isa DateError
                return ["NO " * e.reason]
            end
            rethrow()
        end
    end

    first = parse_date(calendar, args[2])
    if command == "DIFF"
        last = parse_date(args[3], args[4])
        return [string(last - first)]
    elseif command in ("COUNT", "SPAN")
        last = parse_date(calendar, args[3])
        command == "SPAN" && return [span_text(calendar, first, last)]
        low, high = minmax(first, last)
        occurrence = low + mod(findfirst(==(args[4]), WEEKDAYS) - 1 - low, 7)
        return [string(occurrence > high ? 0 : fld(high - occurrence, 7) + 1)]
    elseif command == "CONVERT"
        return [format_date(args[4], first)]
    elseif command == "WEEKDAY"
        return [WEEKDAYS[mod(first, 7) + 1]]
    elseif command == "ALL"
        result = String[]
        for target in CALENDARS
            text = format_date(target, first)
            if target in YMD && text != "OUT OF RANGE"
                year, month, _ = parts_of(target, first)
                text *= " " * names_for(target, year)[month]
            end
            push!(result, target * " " * text)
        end
        return result
    elseif command == "INFO"
        year, month, day = parts_of(calendar, first)
        weekday = WEEKDAYS[mod(first, 7) + 1]
        if calendar == "FRENCH"
            weekday = month <= 12 ? DECADES[mod(day - 1, 10) + 1] : FESTIVALS[day]
        end
        ordinal = first - start_fixed(calendar, year) + 1
        length = start_fixed(calendar, year + 1) - start_fixed(calendar, year)
        return [string(weekday, " ", day, " ", names_for(calendar, year)[month],
                       " ", year, " day=", ordinal, "/", length)]
    elseif command == "ROUND"
        return [round_date(calendar, first, parse(Int, args[3]), args[4],
                           parse(Int, args[5]), args[6])]
    end

    amount = parse(Int, args[3])
    unit = args[4]
    result = if unit == "DAYS"
        first + amount
    elseif unit == "WEEKS"
        first + 7 * amount
    elseif unit == "YEARS"
        shift_date(calendar, first, amount, 0)
    else
        shift_date(calendar, first, 0, amount)
    end
    [result === nothing ? "OUT OF RANGE" : format_date(calendar, result)]
end

function main()
    count = parse(Int, readline(stdin))
    output = String[]
    for _ in 1:count
        fields = String.(split(readline(stdin), ' '; keepempty=true))
        command = first(fields)
        arguments = fields[2:end]
        if !haskey(ARITY, command) || length(arguments) != ARITY[command]
            push!(output, "INVALID COMMAND")
            continue
        end
        try
            append!(output, execute(command, arguments))
        catch error
            if error isa CommandError
                push!(output, "INVALID COMMAND")
            elseif error isa DateError
                push!(output, error.reason == "RANGE" ? "OUT OF RANGE" : "INVALID DATE")
            else
                rethrow()
            end
        end
    end
    println(join(output, "\n"))
end

main()
