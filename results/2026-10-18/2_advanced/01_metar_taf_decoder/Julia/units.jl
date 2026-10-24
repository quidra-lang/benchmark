const SINE = (0, 174, 342, 500, 643, 766, 866, 940, 985, 1000)
function isin(x)
    y = mod(x, 360)
    y <= 90 && return SINE[div(y, 10)+1]
    y <= 180 && return SINE[div(180-y, 10)+1]
    y <= 270 && return -SINE[div(y-180, 10)+1]
    -SINE[div(360-y, 10)+1]
end
icos(x) = isin(x+90)
knots(v, u) = u == "MPS" ? fld(1944*v+500, 1000) : v
inhg(q) = fld(2953*q+500, 1000)
hpa(a) = fld(33864*a+50000, 100000)
monthdays(y, m) = m == 2 ? (y%4 == 0 && (y%100 != 0 || y%400 == 0) ? 29 : 28) : (m in (1, 3, 5, 7, 8, 10, 12) ? 31 : 30)
struct Calendar
    year::Int
    month::Int
    days::Int
    nextyear::Int
    nextmonth::Int
    nextdays::Int
end
function Calendar(y, m)
    ny, nm = m == 12 ? (y+1, 1) : (y, m+1)
    Calendar(y, m, monthdays(y, m), ny, nm, monthdays(ny, nm))
end
dayminutes(d, h, m) = ((d-1)*24+h)*60+m
dayof(t) = fld(t, 1440)+1
hourmark(t) = t-mod(t, 60)
function forecasttime(c, d, h, m, issueday)
    n = d >= issueday ? c.days : c.nextdays
    1 <= d <= n || return nothing
    (d >= issueday ? 0 : c.days*1440) + dayminutes(d, h, m)
end
pad(n, w) = lpad(string(n), w, '0')
function stamp(c, t)
    y, m = c.year, c.month
    if t >= c.days*1440
        y, m = c.nextyear, c.nextmonth
        t -= c.days*1440
    end
    "$(pad(y,4))-$(pad(m,2))-$(pad(fld(t,1440)+1,2))T$(pad(fld(mod(t,1440),60),2)):$(pad(mod(t,60),2))Z"
end
miles(v) = v.kind == :miles ? (v.den == 0 ? v.whole//1 : (v.whole*v.den+v.num)//v.den) : (1000*v.meters)//1609344
meters(v) = v.kind == :miles ? fld(1609344*numerator(miles(v)), 1000*denominator(miles(v))) : v.meters
function fraction(p, q)
    q == 0 && return "undefined"
    g = gcd(p, q)
    "$(div(p,g))/$(div(q,g))"
end
