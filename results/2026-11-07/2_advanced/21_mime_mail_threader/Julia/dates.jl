const WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
const MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const NAMED_ZONES = Dict("ut" => 0, "gmt" => 0, "z" => 0, "est" => -300, "edt" => -240, "cst" => -360, "cdt" => -300, "mst" => -420, "mdt" => -360, "pst" => -480, "pdt" => -420)
struct DateProblem <: Exception
    text::String
end
is_leap(year::Int) = year % 4 == 0 && year % 100 != 0 || year % 400 == 0
days_in_month(year::Int, month::Int) = month == 2 && is_leap(year) ? 29 : MONTH_DAYS[month]
days_in_year(year::Int) = is_leap(year) ? 366 : 365
has_digits(text::AbstractString, lengths::Tuple) = length(text) in lengths && all(byte -> 48 <= byte <= 57, codeunits(text))
function parse_date(value::String)
    syntax = DateProblem("bad Date syntax")
    range = DateProblem("Date out of range")
    text = remove_comments(value)
    isnothing(text) && throw(syntax)
    tokens = split_words(replace(text, "," => " , "))
    weekday = nothing
    if length(tokens) >= 3 && lowercase(tokens[1]) in WEEKDAYS && tokens[2] == ","
        weekday = findfirst(==(lowercase(tokens[1])), WEEKDAYS) - 1
        tokens = tokens[3:end]
    end
    length(tokens) == 5 || throw(syntax)
    day_text, month_text, year_text, time, zone = tokens
    pieces = split(time, ':'; keepempty=true)
    numeric = (startswith(zone, '+') || startswith(zone, '-')) && has_digits(zone[2:end], (4,))
    if !has_digits(day_text, (1, 2)) || lowercase(month_text) ∉ MONTHS || !has_digits(year_text, (2, 4)) || length(pieces) ∉ (2, 3) || !all(piece -> has_digits(piece, (2,)), pieces) || !(numeric || haskey(NAMED_ZONES, lowercase(zone)))
        throw(syntax)
    end
    day = parse(Int, day_text)
    month = findfirst(==(lowercase(month_text)), MONTHS)
    year = parse(Int, year_text)
    length(year_text) == 2 && (year += year < 50 ? 2000 : 1900)
    hour, minute = parse(Int, pieces[1]), parse(Int, pieces[2])
    second = length(pieces) == 3 ? parse(Int, pieces[3]) : 0
    offset = if numeric
        hours, minutes = parse(Int, zone[2:3]), parse(Int, zone[4:5])
        (hours > 23 || minutes > 59) && throw(range)
        (hours * 60 + minutes) * (startswith(zone, '-') ? -1 : 1)
    else
        NAMED_ZONES[lowercase(zone)]
    end
    if !(1970 <= year <= 2099) || day < 1 || day > days_in_month(year, month) || hour > 23 || minute > 59 || second > 59
        throw(range)
    end
    days = day - 1
    for current in 1970:(year - 1)
        days += days_in_year(current)
    end
    for current in 1:(month - 1)
        days += days_in_month(year, current)
    end
    seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset * 60
    seconds >= 0 || throw(range)
    !isnothing(weekday) && (days + 3) % 7 != weekday && throw(DateProblem("Date weekday mismatch"))
    seconds
end
function format_utc(seconds::Int)
    days, rest = divrem(seconds, 86400)
    year = 1970
    month = 1
    while days >= days_in_year(year)
        days -= days_in_year(year)
        year += 1
    end
    while days >= days_in_month(year, month)
        days -= days_in_month(year, month)
        month += 1
    end
    pad(value, width) = lpad(string(value), width, '0')
    "$(pad(year, 4))-$(pad(month, 2))-$(pad(days + 1, 2)) $(pad(rest ÷ 3600, 2)):$(pad(rest % 3600 ÷ 60, 2)):$(pad(rest % 60, 2))"
end
