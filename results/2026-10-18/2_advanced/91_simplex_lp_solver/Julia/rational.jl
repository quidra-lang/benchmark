const Fraction = Rational{Int64}
const ZERO = Fraction(0)
function read_number(word;signed=false)
    pattern = signed ? r"^-?[0-9]+(?:\.[0-9]+|/[0-9]+)?$" : r"^[0-9]+(?:\.[0-9]+|/[0-9]+)?$"
    occursin(pattern,word) || return nothing
    if occursin('/',word)
        numerator,denominator = parse.(Int64,split(word,'/'))
        denominator == 0 && return nothing
        return numerator // denominator
    elseif occursin('.',word)
        integer,decimal = split(word,'.')
        sign = startswith(word,"-") ? -1 : 1
        return sign * parse(Int64,replace(word,"-"=>"","."=>"")) // Int64(10)^length(decimal)
    end
    Fraction(parse(Int64,word))
end
fraction_text(value) = denominator(value) == 1 ? string(numerator(value)) : "$(numerator(value))/$(denominator(value))"
shown(value) = value === nothing ? "-" : fraction_text(value)
endpoint(value,lower) = value === nothing ? (lower ? "-inf" : "inf") : fraction_text(value)
function approximate(value)
    scaled = floor(Int64,abs(value)*1000000+1//2)
    sign = value < 0 && scaled > 0 ? "-" : ""
    sign * string(scaled ÷ 1000000) * "." * lpad(string(scaled % 1000000),6,'0')
end
