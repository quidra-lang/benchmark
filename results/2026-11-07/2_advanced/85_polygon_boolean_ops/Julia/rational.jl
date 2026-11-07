const Coordinate = Rational{BigInt}
const Point = Tuple{Coordinate,Coordinate}
point(x, y) = (BigInt(x)//BigInt(1), BigInt(y)//BigInt(1))
function along(a, b, t)
    return (a[1]+t*(b[1]-a[1]), a[2]+t*(b[2]-a[2]))
end
cross(o, a, b) = (a[1]-o[1])*(b[2]-o[2])-(a[2]-o[2])*(b[1]-o[1])
point_key(p) = (p[2],p[1])
fraction_text(q) = denominator(q) == 1 ? string(numerator(q)) : string(numerator(q), "/", denominator(q))
point_text(p) = string("(", fraction_text(p[1]), ",", fraction_text(p[2]), ")")
segment_text(a,b) = point_text(a) * "-" * point_text(b)
coordinate_real(q) = Float64(numerator(q))/Float64(denominator(q))
