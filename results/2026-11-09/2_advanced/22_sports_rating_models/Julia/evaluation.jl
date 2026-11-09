sigma(value::Float64) = 1 / (1 + exp(-value))
function fit_link(features::Vector{Float64}, results::Vector{Float64}, iterations::Int)
    alpha = 0.0
    beta = 0.0
    for _ in 1:iterations
        g0 = g1 = h00 = h01 = h11 = 0.0
        for (z, y) in zip(features, results)
            p = sigma(alpha + beta * z)
            w = p * (1 - p)
            g0 += y - p
            g1 += (y - p) * z
            h00 += w
            h01 += w * z
            h11 += w * z * z
        end
        determinant = h00 * h11 - h01 * h01
        alpha += (h11 * g0 - h01 * g1) / determinant
        beta += (h00 * g1 - h01 * g0) / determinant
    end
    (alpha, beta)
end
function log_loss(probability::Float64, result::Int)
    result == 2 && return -log(probability)
    result == 0 && return -log(1 - probability)
    -(log(probability) / 2 + log(1 - probability) / 2)
end
function brier_score(probability::Float64, result::Int)
    difference = probability - result / 2
    difference * difference
end
function correctness_twice(probability::Float64, result::Int)
    result == 1 && return 1
    probability > 0.5 && result == 2 || probability < 0.5 && result == 0 ? 2 : 0
end
function doubled_average_ranks(values::Vector{Rational{Int}})
    [2 * count(other -> other > value, values) + count(==(value), values) + 1 for value in values]
end
function kendall_tau(first::Vector{Rational{Int}}, second::Vector{Rational{Int}})
    signed = 0
    for team in eachindex(first), other in (team + 1):length(first)
        a = first[team] > first[other] ? 1 : (first[team] < first[other] ? -1 : 0)
        b = second[team] > second[other] ? 1 : (second[team] < second[other] ? -1 : 0)
        signed += a * b
    end
    signed // (length(first) * (length(first) - 1) ÷ 2)
end
function spearman_rho(first::Vector{Rational{Int}}, second::Vector{Rational{Int}})
    first_ranks = doubled_average_ranks(first)
    second_ranks = doubled_average_ranks(second)
    squares = 0
    for (a, b) in zip(first_ranks, second_ranks)
        squares += (a - b) * (a - b)
    end
    count = length(first)
    (1 // 1) - (6 * squares) // (4 * count * (count * count - 1))
end
