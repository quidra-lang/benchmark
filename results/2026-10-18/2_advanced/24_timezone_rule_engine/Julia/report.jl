padded(value::Int, width::Int) = lpad(string(value), width, '0')
function local_text(time::Int)
    year, month, day, hour, minute, second = split_time(time)
    "$(padded(year, 4))-$(padded(month, 2))-$(padded(day, 2))T$(padded(hour, 2)):$(padded(minute, 2)):$(padded(second, 2))"
end
ut_text(time::Int) = local_text(time) * "Z"
function offset_text(value::Int)
    magnitude = abs(value)
    text = (value < 0 ? "-" : "+") * padded(magnitude ÷ 3600, 2) * ":" * padded(magnitude ÷ 60 % 60, 2)
    magnitude % 60 != 0 && (text *= ":" * padded(magnitude % 60, 2))
    text
end
function duration_text(value::Int)
    magnitude = abs(value)
    (value < 0 ? "-" : "") * string(magnitude ÷ 3600) * ":" * padded(magnitude ÷ 60 % 60, 2) * ":" * padded(magnitude % 60, 2)
end
function clock_text(value::Int)
    text = string(value ÷ 3600) * ":" * padded(value ÷ 60 % 60, 2)
    value % 60 != 0 && (text *= ":" * padded(value % 60, 2))
    text
end
state_text(period::Period) = "$(offset_text(period.offset)) $(period.dst ? "DST" : "STD") $(period.abbreviation)"
change_text(time::Int, before::Period, after::Period) = "$(ut_text(time)) $(state_text(before)) -> $(state_text(after))"
write_lines(path::String, lines::Vector{String}) = write(path, isempty(lines) ? "" : join(lines, '\n') * "\n")
function write_blocks(path::String, blocks::Vector{Vector{String}})
    lines = String[]
    for (index, block) in enumerate(blocks)
        index > 1 && push!(lines, "")
        append!(lines, block)
    end
    write_lines(path, lines)
end
