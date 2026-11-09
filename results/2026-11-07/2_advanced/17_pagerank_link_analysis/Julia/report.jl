using Printf

function fixed(value, places=6)
    result = Printf.format(Printf.Format("%.$(places)f"), value)
    startswith(result, "-") && parse(Float64, result) == 0 ? result[2:end] : result
end

scaled(value, places=6) = round(Int, value * 10^places)

function fraction(numerator, denominator)
    divisor = gcd(abs(numerator), denominator)
    numerator, denominator = div(numerator, divisor), div(denominator, divisor)
    "$numerator/$denominator $(fixed(numerator / denominator, 4))"
end

function write_lines(path, lines)
    open(path, "w") do file
        for line in lines
            write(file, line, '\n')
        end
    end
end
