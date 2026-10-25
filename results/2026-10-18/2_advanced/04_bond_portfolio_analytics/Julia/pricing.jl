module Pricing

function bisect(functionvalue, low, high, target)
    for _ in 1:80
        middle = (low + high) / 2
        if functionvalue(middle) > target
            low = middle
        else
            high = middle
        end
    end
    return (low + high) / 2
end

struct YieldPricer
    flows::Vector{Int}
    fraction::Float64
    frequency::Int
    outstanding::Int
end

function presentvalues(pricer, rate)
    first = 1 + pricer.fraction * rate / pricer.frequency
    growth = 1 + rate / pricer.frequency
    factor = 1.0
    values = Float64[]
    for cashflow in pricer.flows
        push!(values, cashflow / (first * factor))
        factor *= growth
    end
    return values
end

function dirty(pricer, rate)
    total = 0.0
    for value in presentvalues(pricer, rate)
        total += value
    end
    return total * 100 / pricer.outstanding
end

solve(pricer, target) = bisect(rate -> dirty(pricer, rate), 0.0, 1.0, target)

struct Risk
    macaulay::Float64
    modified::Float64
    convexity::Float64
    dv01::Float64
end

function risk(pricer, rate)
    total, weighted, curvature = 0.0, 0.0, 0.0
    growth = 1 + rate / pricer.frequency
    for (index, value) in enumerate(presentvalues(pricer, rate))
        years = (index - 1 + pricer.fraction) / pricer.frequency
        total += value
        weighted += years * value
        curvature += years * (years + 1 / pricer.frequency) * value
    end
    macaulay = weighted / total
    dv01 = (dirty(pricer, rate - 0.0001) - dirty(pricer, rate + 0.0001)) / 2
    return Risk(macaulay, macaulay / growth, curvature / (total * growth * growth), dv01)
end

end
