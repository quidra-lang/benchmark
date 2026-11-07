fraction(value::Integer) = string(value)
fraction(value::Rational) = denominator(value) == 1 ? string(numerator(value)) : string(
    numerator(value),
    "/",
    denominator(value)
)
function bundle_text(mask, items)
    names = [items[i] for i in eachindex(items) if has_item(mask, i)]
    return isempty(names) ? "-" : join(names, "+")
end
number_text(values) = isempty(values) ? "-" : join(sort(values), "+")
function write_reports(reports)
    mkpath("output")
    for (name, lines) in reports
        open(joinpath("output", name), "w") do stream
            for line in lines
                println(stream, line)
            end
        end
    end
end
