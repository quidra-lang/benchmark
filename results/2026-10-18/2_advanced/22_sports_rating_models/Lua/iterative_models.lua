local M = {}

function M.bradley_terry(team_count, matches, iterations)
    local wins, strengths, home_wins, theta = {}, {}, 0.0, 1.0
    for team = 1, team_count do wins[team], strengths[team] = 0.0, 1.0 end
    for _, match in ipairs(matches) do
        wins[match.home], wins[match.away] = wins[match.home] + match.y, wins[match.away] + (1 - match.y)
        home_wins = home_wins + match.y
    end
    for _ = 1, iterations do
        local zeta = {}
        for team = 1, team_count do zeta[team] = 0.0 end
        for _, match in ipairs(matches) do
            local q = theta * strengths[match.home] + strengths[match.away]
            zeta[match.home], zeta[match.away] = zeta[match.home] + theta / q, zeta[match.away] + 1 / q
        end
        for team = 1, team_count do strengths[team] = wins[team] / zeta[team] end
        local sum = 0.0
        for _, value in ipairs(strengths) do sum = sum + value end
        for team = 1, team_count do strengths[team] = strengths[team] * team_count / sum end
        local denominator = 0.0
        for _, match in ipairs(matches) do
            local home = strengths[match.home]
            denominator = denominator + home / (theta * home + strengths[match.away])
        end
        theta = home_wins / denominator
    end
    return strengths, theta
end

function M.offense_defense(team_count, matches, iterations)
    local points, offense, defense, ratings = {}, {}, {}, {}
    for i = 1, team_count do points[i], offense[i], defense[i] = {}, 0.0, 1.0 for j = 1, team_count do points[i][j] = 0 end end
    for _, match in ipairs(matches) do
        points[match.home][match.away] = points[match.home][match.away] + match.away_score
        points[match.away][match.home] = points[match.away][match.home] + match.home_score
    end
    for _ = 1, iterations do
        for j = 1, team_count do
            local total = 0.0
            for i = 1, team_count do total = total + points[i][j] / defense[i] end
            offense[j] = total
        end
        for i = 1, team_count do
            local total = 0.0
            for j = 1, team_count do total = total + points[i][j] / offense[j] end
            defense[i] = total
        end
    end
    for team = 1, team_count do ratings[team] = offense[team] / defense[team] end
    return offense, defense, ratings
end

return M
