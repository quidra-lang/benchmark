const MIN_YEAR = 1800
const MAX_YEAR = 2099
struct DefinitionFieldError <: Exception
    message::String
end
struct Until
    year_text::String
    month_text::String
    day_text::String
    time::Int
    time_type::Char
    value::Int
end
line_content(raw::String) = rstrip(first(split(raw, '#'; limit = 2)), ' ')
split_fields(content::AbstractString) = String.(split(content, ' '; keepempty = false))
is_number(text::AbstractString, low::Int, high::Int) = low <= ncodeunits(text) <= high && all(character -> '0' <= character <= '9', text)
function hms_value(text::AbstractString, max_parts::Int = 3)
    isempty(text) && return nothing
    parts = split(text, ':'; keepempty = true)
    (length(parts) > max_parts || !is_number(parts[1], 1, 2)) && return nothing
    value = parse(Int, parts[1]) * 3600
    for (part, unit) in zip(parts[2:end], (60, 1))
        (!is_number(part, 2, 2) || parse(Int, part) > 59) && return nothing
        value += parse(Int, part) * unit
    end
    value
end
function parse_year(text::AbstractString)
    if is_number(text, 4, 4)
        value = parse(Int, text)
        MIN_YEAR <= value <= MAX_YEAR && return value
    end
    throw(DefinitionFieldError("bad year"))
end
function parse_to(text::AbstractString, from::Int)
    text == "only" && return from
    text == "max" && return MAX_YEAR
    if is_number(text, 4, 4)
        value = parse(Int, text)
        from <= value <= MAX_YEAR && return value
    end
    throw(DefinitionFieldError("bad year"))
end
function parse_month(text::AbstractString)
    index = findfirst(==(text), MONTH_NAMES)
    index === nothing && throw(DefinitionFieldError("bad month"))
    index
end
function parse_weekday(text::AbstractString)
    index = findfirst(==(text), WEEKDAY_NAMES)
    index === nothing && throw(DefinitionFieldError("bad day spec"))
    index - 1
end
function parse_day(text::AbstractString, month::Int)
    if is_number(text, 1, 2) && !startswith(text, '0')
        value = parse(Int, text)
        value <= COMMON_MONTH_DAYS[month] && return value
    end
    throw(DefinitionFieldError("bad day spec"))
end
function parse_day_spec(text::AbstractString, month::Int)
    startswith(text, "last") && return DaySpec(:last, parse_weekday(text[5:end]), 0)
    for (operator, kind) in ((">=", :after), ("<=", :before))
        if occursin(operator, text)
            fields = split(text, operator; limit = 2)
            return DaySpec(kind, parse_weekday(fields[1]), parse_day(fields[2], month))
        end
    end
    DaySpec(:day, 0, parse_day(text, month))
end
function parse_time(text::AbstractString)
    kind = 'w'
    clock = text
    if !isempty(text) && last(text) in "wsu"
        kind = last(text)
        clock = text[1:end-1]
    end
    value = hms_value(clock)
    (value === nothing || value > SECONDS_PER_DAY) && throw(DefinitionFieldError("bad time"))
    value, kind
end
function parse_save(text::AbstractString)
    value = hms_value(text, 2)
    (value === nothing || value > 7200) && throw(DefinitionFieldError("bad save"))
    value
end
function parse_letter(text::AbstractString)
    text == "-" && return ""
    if !isempty(text) && ncodeunits(text) <= 5 && all(character -> 'A' <= character <= 'Z', text)
        return String(text)
    end
    throw(DefinitionFieldError("bad letter"))
end
function parse_stdoff(text::AbstractString)
    negative = startswith(text, '-')
    value = hms_value(negative ? text[2:end] : text)
    (value === nothing || value >= 57600) && throw(DefinitionFieldError("bad offset"))
    negative ? -value : value
end
function check_format(text::String, uses_rule_set::Bool)
    placeholders = length(findall("%s", text))
    slashes = count(==('/'), text)
    characters = all(character -> 'A' <= character <= 'Z' || 'a' <= character <= 'z' || '0' <= character <= '9' || character in "+-/%", text)
    valid = characters && count(==('%'), text) == placeholders && placeholders <= 1 && slashes <= 1 &&
        !(placeholders > 0 && slashes > 0) && (uses_rule_set || placeholders == 0) &&
        !(slashes == 1 && (startswith(text, '/') || endswith(text, '/')))
    valid || throw(DefinitionFieldError("bad format"))
end
function parse_until(fields::Vector{String})
    year = parse_year(fields[1])
    month_text = length(fields) > 1 ? fields[2] : "Jan"
    month = parse_month(month_text)
    day_text = length(fields) > 2 ? fields[3] : "1"
    day = parse_day_spec(day_text, month)
    time, kind = length(fields) > 3 ? parse_time(fields[4]) : (0, 'w')
    Until(fields[1], month_text, day_text, time, kind, day_value(day, year, month) * SECONDS_PER_DAY + time)
end
