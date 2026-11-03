local M = {}

function M.expected_score(home, away, advantage) return 1 / (1 + 10 ^ ((away - home - advantage) / 400)) end

function M.run_elo(team_count, matches, k_factor, advantage, initial)
    local run = {ratings = {}, expected = {}, changes = {}, round_ratings = {}}
    for team = 1, team_count do run.ratings[team] = initial + 0.0 end
    for position, match in ipairs(matches) do
        local home, away = run.ratings[match.home], run.ratings[match.away]
        local expected = M.expected_score(home, away, advantage)
        local goals, weight = math.abs(match.margin), 1.0
        if goals > 0 then
            local difference = match.margin > 0 and home + advantage - away or away - home - advantage
            weight = math.log(goals + 1) * 2.2 / (0.001 * difference + 2.2)
        end
        local change = k_factor * weight * (match.y - expected)
        run.ratings[match.home], run.ratings[match.away] = home + change, away - change
        run.expected[#run.expected + 1], run.changes[#run.changes + 1] = expected, change
        if position == #matches or matches[position + 1].round ~= match.round then
            local snapshot = {}
            for team, rating in ipairs(run.ratings) do snapshot[team] = rating end
            run.round_ratings[#run.round_ratings + 1] = snapshot
        end
    end
    return run
end

return M
