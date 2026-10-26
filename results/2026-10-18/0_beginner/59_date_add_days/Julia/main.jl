using Printf

function days_in_month(year, month)
    leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
    return month == 2 && leap ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month]
end

for (original, added) in [
    ("1999-12-25", 10),
    ("2000-02-27", 3),
    ("2021-02-20", 14),
    ("2023-11-15", 120),
    ("2026-10-17", 1500),
]
    year, month, day = parse.(Int, split(original, "-"))
    for step = 1:added
        day += 1
        if day > days_in_month(year, month)
            day = 1
            month += 1
            if month > 12
                month = 1
                year += 1
            end
        end
    end
    @printf("%s + %d days = %04d-%02d-%02d\n", original, added, year, month, day)
end
