module Schedule

using ..DatesCalendar: civil, number, monthlength

function build(issue, maturity, frequency, eom=false, long=false)
    year, month, day = civil(maturity)
    endrule = eom && day == monthlength(year, month)
    dates = Int[]
    boundary = maturity
    while boundary > issue
        push!(dates, boundary)
        index = year * 12 + month - 1 - (12 ÷ frequency) * length(dates)
        y, m = index ÷ 12, index % 12 + 1
        d = endrule ? monthlength(y, m) : min(day, monthlength(y, m))
        boundary = number(y, m, d)
    end
    long && boundary != issue && length(dates) >= 2 && pop!(dates)
    push!(dates, issue)
    return reverse!(dates)
end

end
