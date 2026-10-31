rdiv(a,b) = fld(2a+b,2b)
function two(value)
    string(value < 0 ? "-" : "",abs(value)÷100,".",lpad(abs(value)%100,2,'0'))
end
four(value) = string(value÷10000,".",lpad(value%10000,4,'0'))
function fraction(a,b)
    divisor = gcd(a,b)
    string(a÷divisor,"/",b÷divisor)
end
ratio(a,b) = b == 0 ? "$a/0 none" : "$a/$b reduced=$(fraction(a,b)) percent=$(two(rdiv(10000a,b)))"
missing_dash(value) = isnothing(value) ? "-" : string(value)
maybe_two(value) = isnothing(value) ? "none" : two(value)
