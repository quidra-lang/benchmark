module Curve

using ..Daycount: fraction
using ..Schedule: build
using ..Pricing: bisect

struct Pillar
    maturity::Int
    coupon::Int
    frequency::Int
end

struct ZeroCurve
    days::Vector{Int}
    rates::Vector{Float64}
end

function zerorate(curve, day)
    day <= first(curve.days) && return first(curve.rates)
    day >= last(curve.days) && return last(curve.rates)
    index = findfirst(boundary -> boundary >= day, curve.days)
    curve.days[index] == day && return curve.rates[index]
    return curve.rates[index - 1] + (curve.rates[index] - curve.rates[index - 1]) * ((day - curve.days[index - 1]) / (curve.days[index] - curve.days[index - 1]))
end

function discount(curve, day, spread=0.0)
    rate = zerorate(curve, day) + spread
    years, remainder = divrem(day, 365)
    growth = 1.0
    for _ in 1:years
        growth *= 1 + rate
    end
    return 1 / (growth * (1 + rate * remainder / 365))
end

function presentvalue(curve, flows, spread=0.0)
    total = 0.0
    for (day, value) in flows
        total += value * discount(curve, day, spread)
    end
    return total
end

forward(curve, start, finish) = (discount(curve, start) / discount(curve, finish) - 1) * 365 / (finish - start)
shifted(curve, deltas) = ZeroCurve(curve.days, curve.rates .+ deltas)
zspread(curve, flows, target) = bisect(spread -> presentvalue(curve, flows, spread), -0.5, 0.5, target)

function bootstrap(settlement, pillars)
    days, rates = Int[], Float64[]
    for pillar in pillars
        dates = build(settlement, pillar.maturity, pillar.frequency)
        flows = Tuple{Int,Float64}[]
        for i in 2:length(dates)
            n, m = fraction("30/360", dates[i - 1], dates[i])
            amount = pillar.coupon * n / (10000 * m)
            i == length(dates) && (amount += 1)
            push!(flows, (dates[i] - settlement, amount))
        end
        push!(days, pillar.maturity - settlement)
        rate = bisect(trial -> presentvalue(ZeroCurve(days, [rates; trial]), flows), 0.0, 1.0, 1.0)
        push!(rates, rate)
    end
    return ZeroCurve(days, rates)
end

end
