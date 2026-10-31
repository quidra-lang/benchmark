using Printf

function fixed(value::Rational{Int}, places::Int = 4)
    scale = 10^places
    n, d = numerator(value), denominator(value)
    whole, remainder = divrem(abs(n), d)
    digits = 0
    for _ in 1:places
        remainder *= 10
        digits = digits * 10 + remainder ÷ d
        remainder %= d
    end
    2 * remainder >= d && (digits += 1)
    if digits == scale
        whole += 1
        digits = 0
    end
    sign = n < 0 && (whole > 0 || digits > 0) ? "-" : ""
    sign * string(whole) * "." * lpad(string(digits), places, '0')
end
function fixed(value::Real, places::Int = 4)
    text = @sprintf("%.*f", places, Float64(value))
    startswith(text, '-') && parse(Float64, text) == 0 ? text[2:end] : text
end
fraction_text(value::Rational{Int}) = "$(numerator(value))/$(denominator(value))"
fraction_with_real(value::Rational{Int}) = fraction_text(value) * " " * fixed(value)
decimal_value(value::Real, places::Int) = round(Int, value * 10.0^places)
write_lines(path::String, lines::Vector{String}) = write(path, join(lines, '\n') * "\n")
