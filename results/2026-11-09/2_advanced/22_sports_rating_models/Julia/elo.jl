mutable struct EloRun
    ratings::Vector{Float64}
    expected::Vector{Float64}
    changes::Vector{Float64}
    round_ratings::Vector{Vector{Float64}}
end
expected_score(home::Float64, away::Float64, advantage::Int) = 1 / (1 + 10.0^((away - home - advantage) / 400))
function multiplier(game::Match, home::Float64, away::Float64, advantage::Int)
    goals = abs(margin(game))
    goals == 0 && return 1.0
    difference = margin(game) > 0 ? home + advantage - away : away - home - advantage
    log(goals + 1) * 2.2 / (0.001 * difference + 2.2)
end
function run_elo(count::Int, matches::Vector{Match}, k::Int, advantage::Int, initial::Int)
    run = EloRun(fill(Float64(initial), count), Float64[], Float64[], Vector{Float64}[])
    for (index, game) in enumerate(matches)
        home, away = run.ratings[game.home], run.ratings[game.away]
        expected = expected_score(home, away, advantage)
        change = k * multiplier(game, home, away, advantage) * (result_value(game) - expected)
        run.ratings[game.home] = home + change
        run.ratings[game.away] = away - change
        push!(run.expected, expected)
        push!(run.changes, change)
        if index == length(matches) || matches[index + 1].round != game.round
            push!(run.round_ratings, copy(run.ratings))
        end
    end
    run
end
