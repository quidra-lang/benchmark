struct ColumnSchema
    name::String
    kind::String
    nullable::Bool
end

const COLUMN_TYPES = ("INT", "STRING", "BOOL", "DATE")
is_leap_year(year) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
month_lengths(year) = [31, is_leap_year(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

function day_number(text)
    year, month, day = parse.(Int, split(text, '-'))
    previous = year - 1
    return 365 * previous + previous ÷ 4 - previous ÷ 100 + previous ÷ 400 + sum(month_lengths(year)[1:month - 1]; init=0) + day - 1 - 719162
end

function date_text(number)
    year = 1970
    while number < 0
        year -= 1
        number += is_leap_year(year) ? 366 : 365
    end
    while number >= (is_leap_year(year) ? 366 : 365)
        number -= is_leap_year(year) ? 366 : 365
        year += 1
    end
    month = 1
    lengths = month_lengths(year)
    while number >= lengths[month]
        number -= lengths[month]
        month += 1
    end
    return lpad(string(year), 4, '0') * "-" * lpad(string(month), 2, '0') * "-" * lpad(
        string(number + 1),
        2,
        '0'
    )
end

function parse_value(kind, field)
    isempty(field) && return nothing
    kind == "INT" && return parse(Int, field)
    kind == "DATE" && return day_number(field)
    kind == "BOOL" && return field == "true"
    return String(field)
end

function value_text(kind, value; null="NULL")
    value === nothing && return null
    kind == "DATE" && return date_text(value)
    kind == "BOOL" && return value ? "true" : "false"
    return string(value)
end

function read_inputs()
    columns = ColumnSchema[]
    for line in readlines("input/schema.txt")
        name, kind, nullable = split(line, ' ')
        push!(columns, ColumnSchema(String(name), String(kind), nullable == "NULLABLE"))
    end
    rows = [Any[parse_value(column.kind, field) for (column, field) in zip(
        columns,
        split(line, ','; keepempty=true)
    )] for line in readlines("input/table.csv")[2:end]]
    options = Dict{String,Any}("encoding" => Dict{String,String}())
    for line in readlines("input/options.txt")
        fields = split(line, ' ')
        if fields[1] == "encoding"
            options["encoding"][String(fields[2])] = String(fields[3])
        else
            options[String(fields[1])] = parse(Int, fields[2])
        end
    end
    queries = readlines("input/queries.txt")
    hex = join(readlines("input/damaged.hex"))
    damaged = [parse(Int, hex[index:index + 1]; base=16) for index in 1:2:length(hex)]
    return columns, rows, options, queries, damaged
end

function write_outputs(outputs)
    mkpath("output")
    for (name, lines) in outputs
        write(joinpath("output", name), join((line * "\n" for line in lines)))
    end
end
