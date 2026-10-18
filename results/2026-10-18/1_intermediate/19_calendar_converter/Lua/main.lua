local function words(text)
    local result = {}
    for word in text:gmatch("[^ ]+") do
        result[#result + 1] = word
    end
    return result
end

local CALENDARS = words("GREGORIAN JULIAN ISO ISLAMIC HEBREW PERSIAN COPTIC ETHIOPIC FRENCH MAYAN JD FIXED")
local YMD = words("GREGORIAN JULIAN ISLAMIC HEBREW PERSIAN COPTIC ETHIOPIC FRENCH")
local YEAR_CALENDARS = words("GREGORIAN JULIAN ISLAMIC HEBREW PERSIAN COPTIC ETHIOPIC FRENCH ISO")
local WEEKDAYS = words("Sunday Monday Tuesday Wednesday Thursday Friday Saturday")
local TZ = words("Imix Ik Akbal Kan Chicchan Cimi Manik Lamat Muluc Oc Chuen Eb Ben Ix Men Cib Caban Etznab Cauac Ahau")
local HB = words("Pop Uo Zip Zotz Tzec Xul Yaxkin Mol Chen Yax Zac Ceh Mac Kankin Muan Pax Kayab Cumku Uayeb")
local DC = words("Primidi Duodi Tridi Quartidi Quintidi Sextidi Septidi Octidi Nonidi Decadi")
local FS = words("Vertu Genie Travail Opinion Recompenses Revolution")
local MAX_FIXED = 3652059
local MONTH_NAMES = {
    GREGORIAN = words("January February March April May June July August September October November December"),
    JULIAN = words("January February March April May June July August September October November December"),
    ISLAMIC = words("Muharram Safar RabiI RabiII JumadaI JumadaII Rajab Shaban Ramadan Shawwal DhuAlQidah DhuAlHijjah"),
    HEBREW = words("Tishri Heshvan Kislev Tevet Shevat Adar Nisan Iyyar Sivan Tammuz Av Elul"),
    PERSIAN = words("Farvardin Ordibehesht Khordad Tir Mordad Shahrivar Mehr Aban Azar Dey Bahman Esfand"),
    COPTIC = words("Thout Paopi Hathor Koiak Tobi Meshir Paremhat Parmouti Pashons Paoni Epip Mesori Nasie"),
    ETHIOPIC = words("Meskerem Tekemt Hedar Tahsas Ter Yekatit Megabit Miazia Genbot Sene Hamle Nehase Pagume"),
    FRENCH = words("Vendemiaire Brumaire Frimaire Nivose Pluviose Ventose Germinal Floreal Prairial Messidor Thermidor Fructidor Sansculottides")
}
local HEBREW_LEAP_NAMES = words("Tishri Heshvan Kislev Tevet Shevat AdarI AdarII Nisan Iyyar Sivan Tammuz Av Elul")

local function date_error(reason)
    error({kind = "date", reason = reason})
end

local function require_valid(condition)
    if not condition then
        error({kind = "command"})
    end
end

local function is_error(value, kind)
    return type(value) == "table" and value.kind == kind
end

local function index_of(values, value)
    for i, other in ipairs(values) do
        if other == value then
            return i
        end
    end
    return nil
end

local function contains(values, value)
    return index_of(values, value) ~= nil
end

local function in_range(fixed)
    return fixed >= 1 and fixed <= MAX_FIXED
end

local start

local function leap(calendar, year)
    if calendar == "GREGORIAN" then
        return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
    elseif calendar == "JULIAN" then
        return year % 4 == 0
    elseif calendar == "ISLAMIC" then
        return contains({2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29}, year % 30)
    elseif calendar == "HEBREW" then
        return (7 * year + 1) % 19 < 7
    elseif calendar == "PERSIAN" then
        local b = (year - 474) % 2820 + 474
        return (b + 38) * 682 % 2816 < 682
    elseif calendar == "COPTIC" or calendar == "ETHIOPIC" then
        return year % 4 == 3
    elseif calendar == "FRENCH" then
        return year % 4 == 0 and not contains({100, 200, 300}, year % 400) and year % 4000 ~= 0
    end
    return (start("ISO", year + 1) - start("ISO", year)) // 7 == 53
end

local function months_before(year)
    return (235 * year - 234) // 19
end

local function molad(year)
    local quantity = 5604 + 765433 * months_before(year)
    local day, parts = quantity // 25920, quantity % 25920
    local weekday = (day - 1373427) % 7
    local rules = {}
    local postponed = day
    if parts >= 19440 then
        postponed = postponed + 1
        rules[#rules + 1] = "ZAKEN"
    elseif not leap("HEBREW", year) and weekday == 2 and parts >= 9924 then
        postponed = postponed + 2
        rules[#rules + 1] = "GATARAD"
    elseif leap("HEBREW", year - 1) and weekday == 1 and parts >= 16789 then
        postponed = postponed + 1
        rules[#rules + 1] = "BETUTAKPAT"
    end
    if contains({0, 3, 5}, (postponed - 1373427) % 7) then
        postponed = postponed + 1
        rules[#rules + 1] = "ADU"
    end
    return day, parts, postponed - 1373427, rules
end

function start(calendar, year)
    local previous = year - 1
    if calendar == "GREGORIAN" then
        return 365 * previous + previous // 4 - previous // 100 + previous // 400 + 1
    elseif calendar == "JULIAN" then
        return 365 * previous + previous // 4 - 1
    elseif calendar == "ISLAMIC" then
        return 227015 + 354 * previous + (3 + 11 * year) // 30
    elseif calendar == "HEBREW" then
        local _, _, fixed = molad(year)
        return fixed
    elseif calendar == "PERSIAN" then
        local a = year - 474
        local b = a % 2820 + 474
        return 226896 + 1029983 * (a // 2820) + 365 * (b - 1) + (682 * b - 110) // 2816
    elseif calendar == "COPTIC" then
        return 103605 + 365 * previous + year // 4
    elseif calendar == "ETHIOPIC" then
        return 2796 + 365 * previous + year // 4
    elseif calendar == "FRENCH" then
        return 654415 + 365 * previous + previous // 4 - previous // 100 + previous // 400 - previous // 4000
    end
    local january_four = start("GREGORIAN", year) + 3
    return january_four - (january_four - 1) % 7
end

local function year_type(year)
    local length = start("HEBREW", year + 1) - start("HEBREW", year)
    if length == 353 or length == 383 then
        return "DEFICIENT"
    elseif length == 354 or length == 384 then
        return "REGULAR"
    end
    return "COMPLETE"
end

local function names(calendar, year)
    if calendar == "HEBREW" and leap(calendar, year) then
        return HEBREW_LEAP_NAMES
    end
    return MONTH_NAMES[calendar]
end

local function lengths(calendar, year)
    local extra = leap(calendar, year) and 1 or 0
    if calendar == "GREGORIAN" or calendar == "JULIAN" then
        return {31, 28 + extra, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    elseif calendar == "ISLAMIC" then
        return {30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 + extra}
    elseif calendar == "PERSIAN" then
        return {31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29 + extra}
    elseif contains({"COPTIC", "ETHIOPIC", "FRENCH"}, calendar) then
        return {30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 5 + extra}
    end
    local kind = year_type(year)
    local heshvan = kind == "COMPLETE" and 30 or 29
    local kislev = kind == "DEFICIENT" and 29 or 30
    if extra == 1 then
        return {30, heshvan, kislev, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29}
    end
    return {30, heshvan, kislev, 29, 30, 29, 30, 29, 30, 29, 30, 29}
end

local function fixed_date(calendar, year, month, day)
    if calendar == "ISO" then
        return start(calendar, year) + 7 * (month - 1) + day - 1
    end
    local days = lengths(calendar, year)
    local before = 0
    for i = 1, month - 1 do
        before = before + days[i]
    end
    return start(calendar, year) + before + day - 1
end

local function year_of(calendar, fixed)
    if fixed < start(calendar, 1) then
        return 0
    end
    local low, high = 1, 100000
    while low + 1 < high do
        local middle = (low + high) // 2
        if start(calendar, middle) <= fixed then
            low = middle
        else
            high = middle
        end
    end
    return low
end

local function parts_of(calendar, fixed)
    local year = year_of(calendar, fixed)
    if year == 0 then
        return nil
    end
    local offset = fixed - start(calendar, year)
    if calendar == "ISO" then
        return year, offset // 7 + 1, offset % 7 + 1
    end
    for month, days in ipairs(lengths(calendar, year)) do
        if offset < days then
            return year, month, offset + 1
        end
        offset = offset - days
    end
    error("calendar year length")
end

local function format_date(calendar, fixed)
    if not in_range(fixed) then
        return "OUT OF RANGE"
    end
    if contains(YEAR_CALENDARS, calendar) then
        local year, month, day = parts_of(calendar, fixed)
        if year == nil then
            return "OUT OF RANGE"
        end
        if calendar == "ISO" then
            return string.format("%04d-W%02d-%d", year, month, day)
        end
        return string.format("%04d-%02d-%02d", year, month, day)
    elseif calendar == "JD" then
        return tostring(fixed + 1721425)
    elseif calendar == "FIXED" then
        return tostring(fixed)
    end
    local count = fixed + 1137142
    local long_count = {count // 144000, count // 7200 % 20, count // 360 % 20, count // 20 % 18, count % 20}
    local tz_number = (count + 3) % 13 + 1
    local tz_name = TZ[(count + 19) % 20 + 1]
    local haab = (count + 348) % 365
    return string.format("%s %d %s %d %s", table.concat(long_count, "."), tz_number, tz_name, haab % 20, HB[haab // 20 + 1])
end

local function parse_date(calendar, text)
    local fixed
    if contains(YMD, calendar) then
        local year_text, month_text, day_text = text:match("^(%d+)%-(%d+)%-(%d+)$")
        if not (year_text and #year_text <= 5 and #month_text <= 2 and #day_text <= 2) then
            date_error("FORMAT")
        end
        local year, month, day = tonumber(year_text), tonumber(month_text), tonumber(day_text)
        if year == 0 then
            date_error("YEAR")
        end
        local days = lengths(calendar, year)
        if month < 1 or month > #days then
            date_error("MONTH")
        end
        if day < 1 or day > days[month] then
            date_error("DAY")
        end
        fixed = fixed_date(calendar, year, month, day)
    elseif calendar == "ISO" then
        local year_text, week_text, day_text = text:match("^(%d+)%-W(%d+)%-(%d)$")
        if not (year_text and #year_text <= 5 and #week_text <= 2) then
            date_error("FORMAT")
        end
        local year, week, day = tonumber(year_text), tonumber(week_text), tonumber(day_text)
        if year == 0 then
            date_error("YEAR")
        end
        local weeks = (start(calendar, year + 1) - start(calendar, year)) // 7
        if week < 1 or week > weeks then
            date_error("WEEK")
        end
        if day < 1 or day > 7 then
            date_error("DAY")
        end
        fixed = fixed_date(calendar, year, week, day)
    elseif calendar == "MAYAN" then
        local fields = {text:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
        if #fields ~= 5 then
            date_error("FORMAT")
        end
        for i, field in ipairs(fields) do
            if #field > 2 then
                date_error("FORMAT")
            end
            fields[i] = tonumber(field)
        end
        local b, k, t, u, n = table.unpack(fields)
        if k > 19 or t > 19 or u > 17 or n > 19 then
            date_error("FIELD")
        end
        fixed = (((b * 20 + k) * 20 + t) * 18 + u) * 20 + n - 1137142
    else
        local digits = text:match("^%-?(%d+)$")
        if not (digits and #digits <= 8) then
            date_error("FORMAT")
        end
        fixed = tonumber(text) - (calendar == "JD" and 1721425 or 0)
    end
    if not in_range(fixed) then
        date_error("RANGE")
    end
    return fixed
end

local function month_index(calendar, year)
    if calendar == "HEBREW" then
        return months_before(year)
    end
    local count = contains({"COPTIC", "ETHIOPIC", "FRENCH"}, calendar) and 13 or 12
    return count * (year - 1)
end

local function shift(calendar, fixed, years, months)
    local year, month, day = parts_of(calendar, fixed)
    local target_year = year + years
    if calendar == "ISO" then
        if target_year < 1 or target_year > 99999 then
            return nil
        end
        local weeks = (start(calendar, target_year + 1) - start(calendar, target_year)) // 7
        return fixed_date(calendar, target_year, math.min(month, weeks), day)
    end
    if calendar == "HEBREW" then
        local old_name = names(calendar, year)[month]
        local new_names = names(calendar, target_year)
        if not contains(new_names, old_name) then
            old_name = old_name == "Adar" and "AdarII" or "Adar"
        end
        month = index_of(new_names, old_name)
    end
    local absolute = month_index(calendar, target_year) + month - 1 + months
    local final_year
    if calendar == "HEBREW" then
        final_year = (19 * absolute + 234) // 235
        while month_index(calendar, final_year) > absolute do
            final_year = final_year - 1
        end
        while month_index(calendar, final_year + 1) <= absolute do
            final_year = final_year + 1
        end
    else
        final_year = absolute // #names(calendar, target_year) + 1
    end
    if final_year < 1 or final_year > 99999 then
        return nil
    end
    local final_month = absolute - month_index(calendar, final_year) + 1
    local final_day = math.min(day, lengths(calendar, final_year)[final_month])
    return fixed_date(calendar, final_year, final_month, final_day)
end

local function month_bounds(calendar, year, month)
    local days = lengths(calendar, year)
    if month < 1 or month > #days then
        date_error("MONTH")
    end
    local first = fixed_date(calendar, year, month, 1)
    return first, first + days[month] - 1
end

local function new_years(calendar, first, last)
    local year = math.max(1, year_of(calendar, first))
    while start(calendar, year) < first do
        year = year + 1
    end
    local result = {}
    while start(calendar, year) <= last do
        result[#result + 1] = {year, start(calendar, year)}
        year = year + 1
    end
    return result
end

local function easter(year, calendar)
    local golden = year % 19
    local epact
    if calendar == "GREGORIAN" then
        local century = year // 100 + 1
        epact = (14 + 11 * golden - 3 * century // 4 + (5 + 8 * century) // 25) % 30
        if epact == 0 or (epact == 1 and golden > 10) then
            epact = epact + 1
        end
    else
        epact = (14 + 11 * golden) % 30
    end
    local moon = fixed_date(calendar, year, 4, 19) - epact
    local sunday = moon + 7 - moon % 7
    local index = -start(calendar, year) % 7
    local letters = ("ABCDEFG"):sub(index + 1, index + 1)
    if leap(calendar, year) then
        local second = (index - 1) % 7
        letters = letters .. ("ABCDEFG"):sub(second + 1, second + 1)
    end
    return epact, letters, moon, sunday
end

local HOLIDAYS = {
    {"Christmas", "GREGORIAN", "December", 25},
    {"OrthodoxChristmas", "JULIAN", "December", 25},
    {"RoshHashanah", "HEBREW", "Tishri", 1},
    {"YomKippur", "HEBREW", "Tishri", 10},
    {"Sukkot", "HEBREW", "Tishri", 15},
    {"Hanukkah", "HEBREW", "Kislev", 25},
    {"Purim", "HEBREW", "Adar", 14},
    {"Passover", "HEBREW", "Nisan", 15},
    {"Shavuot", "HEBREW", "Sivan", 6},
    {"IslamicNewYear", "ISLAMIC", "Muharram", 1},
    {"Ashura", "ISLAMIC", "Muharram", 10},
    {"Mawlid", "ISLAMIC", "RabiI", 12},
    {"RamadanStart", "ISLAMIC", "Ramadan", 1},
    {"EidAlFitr", "ISLAMIC", "Shawwal", 1},
    {"EidAlAdha", "ISLAMIC", "DhuAlHijjah", 10},
    {"Nowruz", "PERSIAN", "Farvardin", 1},
    {"SizdahBedar", "PERSIAN", "Farvardin", 13},
    {"Yalda", "PERSIAN", "Azar", 30},
    {"Nayrouz", "COPTIC", "Thout", 1},
    {"CopticChristmas", "COPTIC", "Koiak", 29},
    {"Enkutatash", "ETHIOPIC", "Meskerem", 1},
    {"Meskel", "ETHIOPIC", "Meskerem", 17},
    {"Timkat", "ETHIOPIC", "Ter", 11},
    {"RepublicDay", "FRENCH", "Vendemiaire", 1},
    {"RevolutionDay", "FRENCH", "Sansculottides", 6}
}

local function holiday_lines(year)
    local first = start("GREGORIAN", year)
    local last = start("GREGORIAN", year + 1) - 1
    local gregorian_easter = select(4, easter(year, "GREGORIAN"))
    local orthodox_easter = select(4, easter(year, "JULIAN"))
    local entries = {}
    local movable = {{"AshWednesday", -46}, {"GoodFriday", -2}, {"Easter", 0}, {"Ascension", 39}, {"Pentecost", 49}}
    for order, item in ipairs(movable) do
        entries[#entries + 1] = {fixed = gregorian_easter + item[2], order = order, name = item[1], calendar = "GREGORIAN"}
    end
    entries[#entries + 1] = {fixed = orthodox_easter, order = 6, name = "OrthodoxEaster", calendar = "JULIAN"}
    for index, holiday in ipairs(HOLIDAYS) do
        local name, calendar, month_name, day = table.unpack(holiday)
        local candidate_year = math.max(1, year_of(calendar, first))
        while start(calendar, candidate_year) <= last do
            local actual_name = month_name
            if calendar == "HEBREW" and month_name == "Adar" and leap(calendar, candidate_year) then
                actual_name = "AdarII"
            end
            local month = index_of(names(calendar, candidate_year), actual_name)
            if day <= lengths(calendar, candidate_year)[month] then
                local fixed = fixed_date(calendar, candidate_year, month, day)
                if first <= fixed and fixed <= last then
                    entries[#entries + 1] = {fixed = fixed, order = index + 6, name = name, calendar = calendar}
                end
            end
            candidate_year = candidate_year + 1
        end
    end
    table.sort(entries, function(a, b)
        if a.fixed ~= b.fixed then
            return a.fixed < b.fixed
        end
        return a.order < b.order
    end)
    local lines = {}
    for i, entry in ipairs(entries) do
        lines[i] = string.format("%s %s %s %s %s", format_date("GREGORIAN", entry.fixed), WEEKDAYS[entry.fixed % 7 + 1],
            entry.name, entry.calendar, format_date(entry.calendar, entry.fixed))
    end
    return lines
end

local ARITY = {
    CONVERT = 4, ALL = 2, VALID = 2, WEEKDAY = 2, INFO = 2,
    LEAP = 2, MONTHS = 2, MONTHCAL = 3, NTH = 5, NEWYEAR = 2,
    DIFF = 4, COUNT = 4, ADD = 4, SPAN = 3, EASTER = 2,
    COMPUTUS = 2, PASSOVER = 1, HOLIDAYS = 1, MOLAD = 1, ROUND = 6
}

local function digit_string(text, longest)
    return text:match("^%d+$") ~= nil and #text <= longest
end

local function valid_year(text)
    return digit_string(text, 5) and tonumber(text) >= 1
end

local function validate_arguments(command, args)
    if command == "EASTER" or command == "COMPUTUS" then
        require_valid(valid_year(args[1]) and (args[2] == "GREGORIAN" or args[2] == "JULIAN"))
        return
    end
    if contains({"PASSOVER", "HOLIDAYS", "MOLAD"}, command) then
        require_valid(valid_year(args[1]))
        return
    end
    local calendar = args[1]
    local allowed = CALENDARS
    if contains({"INFO", "MONTHS", "MONTHCAL", "NTH", "SPAN"}, command) then
        allowed = YMD
    elseif command == "LEAP" or command == "NEWYEAR" then
        allowed = YEAR_CALENDARS
    end
    require_valid(contains(allowed, calendar))
    if command == "CONVERT" then
        require_valid(args[3] == "TO" and contains(CALENDARS, args[4]))
    elseif command == "DIFF" then
        require_valid(contains(CALENDARS, args[3]))
    elseif contains({"LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR"}, command) then
        require_valid(valid_year(args[2]))
        if command == "MONTHCAL" or command == "NTH" then
            require_valid(digit_string(args[3], 2))
        end
        if command == "NTH" then
            require_valid(contains({"1", "2", "3", "4", "5", "LAST"}, args[4]))
            require_valid(contains(WEEKDAYS, args[5]))
        end
    elseif command == "COUNT" then
        require_valid(contains(WEEKDAYS, args[4]))
    elseif command == "ADD" then
        local digits = args[3]:match("^%-?(%d+)$")
        require_valid(digits ~= nil and #digits <= 7)
        require_valid(contains({"DAYS", "WEEKS", "MONTHS", "YEARS"}, args[4]))
        if args[4] == "MONTHS" then
            require_valid(contains(YMD, calendar))
        end
        if args[4] == "YEARS" then
            require_valid(contains(YEAR_CALENDARS, calendar))
        end
    elseif command == "ROUND" then
        require_valid(digit_string(args[3], 2))
        require_valid(tonumber(args[3]) >= 1 and tonumber(args[3]) <= 13 and contains(TZ, args[4]))
        require_valid(digit_string(args[5], 2))
        require_valid(contains(HB, args[6]))
        require_valid(tonumber(args[5]) <= (args[6] == "Uayeb" and 4 or 19))
    end
end

local function calendar_lines(calendar, year, month)
    local first, last = month_bounds(calendar, year, month)
    if not in_range(first) or not in_range(last) then
        return {"OUT OF RANGE"}
    end
    local title = string.format("%s %d (%s to %s)", names(calendar, year)[month], year,
        format_date("GREGORIAN", first), format_date("GREGORIAN", last))
    local result = {title, "Mo Tu We Th Fr Sa Su"}
    for cursor = first - (first - 1) % 7, last, 7 do
        local fields = {}
        for fixed = cursor, cursor + 6 do
            if first <= fixed and fixed <= last then
                fields[#fields + 1] = string.format("%2d", fixed - first + 1)
            else
                fields[#fields + 1] = "  "
            end
        end
        result[#result + 1] = (table.concat(fields, " "):gsub(" +$", ""))
    end
    return result
end

local function span_text(calendar, first, last)
    local negative = first > last
    if negative then
        first, last = last, first
    end
    local start_year = parts_of(calendar, first)
    local end_year = parts_of(calendar, last)
    local low, high = 0, end_year - start_year + 2
    while low + 1 < high do
        local middle = (low + high) // 2
        local shifted = shift(calendar, first, middle, 0)
        if shifted ~= nil and shifted <= last then
            low = middle
        else
            high = middle
        end
    end
    local years = low
    low, high = 0, 32
    while low + 1 < high do
        local middle = (low + high) // 2
        local shifted = shift(calendar, first, years, middle)
        if shifted ~= nil and shifted <= last then
            low = middle
        else
            high = middle
        end
    end
    local months = low
    local days = last - shift(calendar, first, years, months)
    return string.format("%s%dy %dm %dd", negative and "-" or "", years, months, days)
end

local function round_date(calendar, fixed, number, tz_name, day, month)
    local target_tz = index_of(TZ, tz_name) - 1
    local target_haab = (index_of(HB, month) - 1) * 20 + day
    local candidate = fixed
    while true do
        local count = candidate + 1137142
        if (count + 3) % 13 + 1 == number and (count + 19) % 20 == target_tz then
            break
        end
        candidate = candidate + 1
    end
    while candidate <= fixed + 18979 do
        if (candidate + 1137142 + 348) % 365 == target_haab then
            return format_date(calendar, candidate)
        end
        candidate = candidate + 260
    end
    return "NONE"
end

local function execute(command, args)
    validate_arguments(command, args)
    if command == "EASTER" or command == "COMPUTUS" then
        local year = tonumber(args[1])
        if year > 9999 then
            return {"OUT OF RANGE"}
        end
        local kind = args[2]
        local epact, letters, moon, sunday = easter(year, kind)
        if command == "EASTER" then
            return {format_date("GREGORIAN", sunday)}
        end
        return {string.format("golden=%d epact=%d letters=%s moon=%s easter=%s", year % 19 + 1, epact, letters,
            format_date(kind, moon), format_date(kind, sunday))}
    end
    if contains({"PASSOVER", "HOLIDAYS", "MOLAD"}, command) then
        local year = tonumber(args[1])
        if command == "MOLAD" then
            local day, parts, fixed, rules = molad(year)
            if not in_range(fixed) then
                return {"OUT OF RANGE"}
            end
            local applied = #rules > 0 and table.concat(rules, "+") or "NONE"
            return {string.format("%s %dh %dp %s %s %s", WEEKDAYS[(day - 1373427) % 7 + 1], parts // 1080, parts % 1080,
                applied, WEEKDAYS[fixed % 7 + 1], format_date("GREGORIAN", fixed))}
        end
        if year > 9999 then
            return {"OUT OF RANGE"}
        end
        if command == "HOLIDAYS" then
            return holiday_lines(year)
        end
        local hebrew_year = year + 3760
        local month = index_of(names("HEBREW", hebrew_year), "Nisan")
        local fixed = fixed_date("HEBREW", hebrew_year, month, 15)
        return {format_date("GREGORIAN", fixed) .. " " .. WEEKDAYS[fixed % 7 + 1]}
    end
    local calendar = args[1]
    if contains({"LEAP", "MONTHS", "MONTHCAL", "NTH", "NEWYEAR"}, command) then
        local year = tonumber(args[2])
        if command == "LEAP" then
            local text = (leap(calendar, year) and "YES" or "NO") .. " " .. (start(calendar, year + 1) - start(calendar, year))
            if calendar == "HEBREW" then
                text = text .. " " .. year_type(year)
            end
            return {text}
        elseif command == "MONTHS" then
            local days = lengths(calendar, year)
            local items = {}
            for i, name in ipairs(names(calendar, year)) do
                items[i] = name .. "=" .. days[i]
            end
            return {table.concat(items, " ")}
        elseif command == "NEWYEAR" then
            if year > 9999 then
                return {"OUT OF RANGE"}
            end
            local items = {}
            for i, entry in ipairs(new_years(calendar, start("GREGORIAN", year), start("GREGORIAN", year + 1) - 1)) do
                items[i] = entry[1] .. ":" .. format_date("GREGORIAN", entry[2])
            end
            return {#items > 0 and table.concat(items, " ") or "NONE"}
        end
        local month = tonumber(args[3])
        if command == "MONTHCAL" then
            return calendar_lines(calendar, year, month)
        end
        local first, last = month_bounds(calendar, year, month)
        local weekday = index_of(WEEKDAYS, args[5]) - 1
        local fixed
        if args[4] == "LAST" then
            fixed = last - (last - weekday) % 7
        else
            fixed = first + (weekday - first) % 7 + 7 * (tonumber(args[4]) - 1)
        end
        return {fixed > last and "NONE" or format_date(calendar, fixed)}
    end
    if command == "VALID" then
        local ok, result = pcall(parse_date, calendar, args[2])
        if ok then
            return {"YES " .. format_date(calendar, result)}
        elseif is_error(result, "date") then
            return {"NO " .. result.reason}
        end
        error(result, 0)
    end
    local first = parse_date(calendar, args[2])
    if command == "DIFF" then
        local last = parse_date(args[3], args[4])
        return {tostring(last - first)}
    end
    if command == "COUNT" or command == "SPAN" then
        local last = parse_date(calendar, args[3])
        if command == "SPAN" then
            return {span_text(calendar, first, last)}
        end
        local low, high = math.min(first, last), math.max(first, last)
        local occurrence = low + (index_of(WEEKDAYS, args[4]) - 1 - low) % 7
        return {tostring(occurrence > high and 0 or (high - occurrence) // 7 + 1)}
    end
    if command == "CONVERT" then
        return {format_date(args[4], first)}
    elseif command == "WEEKDAY" then
        return {WEEKDAYS[first % 7 + 1]}
    elseif command == "ALL" then
        local result = {}
        for i, target in ipairs(CALENDARS) do
            local text = format_date(target, first)
            if contains(YMD, target) and text ~= "OUT OF RANGE" then
                local year, month = parts_of(target, first)
                text = text .. " " .. names(target, year)[month]
            end
            result[i] = target .. " " .. text
        end
        return result
    elseif command == "INFO" then
        local year, month, day = parts_of(calendar, first)
        local weekday = WEEKDAYS[first % 7 + 1]
        if calendar == "FRENCH" then
            weekday = month <= 12 and DC[(day - 1) % 10 + 1] or FS[day]
        end
        local ordinal = first - start(calendar, year) + 1
        local length = start(calendar, year + 1) - start(calendar, year)
        return {string.format("%s %d %s %d day=%d/%d", weekday, day, names(calendar, year)[month], year, ordinal, length)}
    elseif command == "ROUND" then
        return {round_date(calendar, first, tonumber(args[3]), args[4], tonumber(args[5]), args[6])}
    end
    local amount = tonumber(args[3])
    local unit = args[4]
    local result
    if unit == "DAYS" then
        result = first + amount
    elseif unit == "WEEKS" then
        result = first + 7 * amount
    elseif unit == "YEARS" then
        result = shift(calendar, first, amount, 0)
    else
        result = shift(calendar, first, 0, amount)
    end
    return {result == nil and "OUT OF RANGE" or format_date(calendar, result)}
end

local count = tonumber(io.read("l"))
local output = {}
for _ = 1, count do
    local args = words(io.read("l"))
    local command = table.remove(args, 1)
    if ARITY[command] == nil or #args ~= ARITY[command] then
        output[#output + 1] = "INVALID COMMAND"
    else
        local ok, result = pcall(execute, command, args)
        if ok then
            table.move(result, 1, #result, #output + 1, output)
        elseif is_error(result, "command") then
            output[#output + 1] = "INVALID COMMAND"
        elseif is_error(result, "date") then
            output[#output + 1] = result.reason == "RANGE" and "OUT OF RANGE" or "INVALID DATE"
        else
            error(result, 0)
        end
    end
end
io.write(table.concat(output, "\n"), "\n")
