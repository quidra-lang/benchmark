function decimal_text(value, digits)
    scale = 10^digits
    p, q = numerator(value), denominator(value)
    rounded = div(2 * scale * abs(p) + q, 2 * q)
    sign = p < 0 && rounded > 0 ? "-" : ""
    sign * string(div(rounded, scale)) * "." * lpad(string(mod(rounded, scale)), digits, '0')
end

hull_area_text(doubled) = "$(div(doubled, 2)).$(iseven(doubled) ? 0 : 5)"

function write_files(directory, files)
    mkpath(directory)
    for (name, lines) in files
        open(joinpath(directory, name), "w") do file
            for line in lines
                println(file, line)
            end
        end
    end
end
