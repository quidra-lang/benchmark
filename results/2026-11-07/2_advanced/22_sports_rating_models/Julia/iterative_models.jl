function bradley_terry(count::Int, matches::Vector{Match}, iterations::Int)
    wins = zeros(Int, count)
    home_wins = 0
    for game in matches
        wins[game.home] += result_twice(game)
        wins[game.away] += 2 - result_twice(game)
        home_wins += result_twice(game)
    end
    strengths = ones(count)
    theta = 1.0
    for _ in 1:iterations
        zeta = zeros(count)
        for game in matches
            q = theta * strengths[game.home] + strengths[game.away]
            zeta[game.home] += theta / q
            zeta[game.away] += 1 / q
        end
        for team in 1:count
            strengths[team] = (wins[team] / 2) / zeta[team]
        end
        total = 0.0
        for strength in strengths
            total += strength
        end
        for team in 1:count
            strengths[team] = strengths[team] * count / total
        end
        denominator = 0.0
        for game in matches
            home = strengths[game.home]
            denominator += home / (theta * home + strengths[game.away])
        end
        theta = (home_wins / 2) / denominator
    end
    (strengths, theta)
end
function offense_defense(count::Int, matches::Vector{Match}, iterations::Int)
    points = zeros(Int, count, count)
    for game in matches
        points[game.home, game.away] += game.away_score
        points[game.away, game.home] += game.home_score
    end
    offense = zeros(count)
    defense = ones(count)
    for _ in 1:iterations
        for j in 1:count
            total = 0.0
            for i in 1:count
                total += points[i, j] / defense[i]
            end
            offense[j] = total
        end
        for i in 1:count
            total = 0.0
            for j in 1:count
                total += points[i, j] / offense[j]
            end
            defense[i] = total
        end
    end
    (offense, defense, [offense[team] / defense[team] for team in 1:count])
end
