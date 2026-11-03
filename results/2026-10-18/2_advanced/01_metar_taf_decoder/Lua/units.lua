local U = {}
local sine = { [0] = 0, 174, 342, 500, 643, 766, 866, 940, 985, 1000 }
function U.sin(x)
    local y = x % 360
    if y <= 90 then
        return sine[y // 10]
    end
    if y <= 180 then
        return sine[(180 - y) // 10]
    end
    if y <= 270 then
        return - sine[(y - 180) // 10]
    end
    return - sine[(360 - y) // 10]
end

function U.cos(x)
    return U.sin(x + 90)
end

function U.knots(v)
    return (v * 1944 + 500) // 1000
end

function U.inhg(v)
    return (v * 2953 + 500) // 1000
end

function U.hpa(v)
    return (v * 33864 + 50000) // 100000
end

function U.miles(v)
    if v.kind == 'miles' then
        return v.whole * v.den + v.num, v.den
    end
    return 1000 * v.value, 1609344
end

function U.meters(v)
    if v.kind ~= 'miles' then
        return v.value
    end
    local n, d = U.miles(v)
    return (1609344 * n) // (1000 * d)
end

function U.fraction(n, d)
    if d == 0 then
        return 'undefined'
    end
    local a, b = math.abs(n), d
    while b ~= 0 do
        a, b = b, a % b
    end
    return (n // a) .. '/' .. (d // a)
end

function U.days(y, m)
    if m == 2 then
        return (y % 400 == 0 or (y % 4 == 0 and y % 100 ~= 0)) and 29 or 28
    end
    return (m == 4 or m == 6 or m == 9 or m == 11) and 30 or 31
end

function U.digits(s, a, b)
    return s ~= nil and #s >= a and #s <= (b or a) and s:match('^%d+$') ~= nil
end

function U.calendar(year, month)
    local cal = {year = year, month = month, days = U.days(year, month)}
    cal.nextYear = year + (month == 12 and 1 or 0)
    cal.nextMonth = month == 12 and 1 or month + 1
    function cal:reportTime(s)
        local d, h, m = s:match('^(%d%d)(%d%d)(%d%d)Z$')
        if not d then
            return nil
        end
        d, h, m = tonumber(d), tonumber(h), tonumber(m)
        if d < 1 or d > self.days or h > 23 or m > 59 then
            return nil
        end
        return ((d - 1) * 24 + h) * 60 + m
    end
    function cal:dayTime(d, h, m, issue)
        local nextMonth = d < issue
        if d < 1 or d > (nextMonth and U.days(self.nextYear, self.nextMonth) or self.days) then
            return nil
        end
        return (nextMonth and self.days * 1440 or 0) + ((d - 1) * 24 + h) * 60 + m
    end
    function cal:period(s, issue, limit)
        local d, h, e, j = s:match('^(%d%d)(%d%d)/(%d%d)(%d%d)$')
        if not d then
            return nil
        end
        d, h, e, j = tonumber(d), tonumber(h), tonumber(e), tonumber(j)
        if h > 23 or j < 1 or j > 24 then
            return nil
        end
        local a, b = self:dayTime(d, h, 0, issue), self:dayTime(e, j, 0, issue)
        if not a or not b or a >= b or (limit and b > a + limit) then
            return nil
        end
        return {a, b}
    end
    function cal:stamp(t)
        local y, m = self.year, self.month
        if t >= self.days * 1440 then
            t = t - self.days * 1440
            y, m = self.nextYear, self.nextMonth
        end
        return string.format('%04d-%02d-%02dT%02d:%02dZ', y, m, t // 1440 + 1, t % 1440 // 60, t % 60)
    end
    return cal
end
return U
