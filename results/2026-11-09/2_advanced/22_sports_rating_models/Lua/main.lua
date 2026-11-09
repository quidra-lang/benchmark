local source_directory = (arg[0]:match("^(.*[/\\])") or "./")
package.path = source_directory .. "?.lua;" .. package.path
local season = require("season")
local elo = require("elo")
local linear = require("linear_models")
local iterative = require("iterative_models")
local evaluation = require("evaluation")
local report = require("report")
local Fraction = report.Fraction

local rating_models = {"elo", "colley", "massey", "bt", "od", "winpct"}
local comparison_models = {"standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag"}
local link_models = {"colley", "massey", "od", "winpct"}
local prediction_models = {"base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble"}
local standings_header = "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck"
local ratings_header = "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank"
local projection_header = "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position"

local function zeros(count, value) local values = {} for index = 1, count do values[index] = value or 0 end return values end
local function indices(count) local values = {} for index = 1, count do values[index] = index end return values end
local function map(values, fn) local result = {} for index, value in ipairs(values) do result[index] = fn(value, index) end return result end
local function extend(target, values) for _, value in ipairs(values) do target[#target + 1] = value end end
local function mean(values) local total = 0.0 for _, value in ipairs(values) do total = total + value end return total / #values end
local function sum(values) local total = 0 for _, value in ipairs(values) do total = total + value end return total end
local function csv(fields) return table.concat(map(fields, function(value) return tostring(value) end), ",") end
local function join_parts(parts)
    local lines = {}
    for _, part in ipairs(parts) do if #lines > 0 then lines[#lines + 1] = "" end extend(lines, part) end
    return lines
end
local function result_letter(scored, conceded) return scored > conceded and "W" or scored == conceded and "D" or "L" end
local function record_text(appearances)
    local counts = {W = 0, D = 0, L = 0}
    for _, appearance in ipairs(appearances) do counts[appearance.letter] = counts[appearance.letter] + 1 end
    return counts.W .. "-" .. counts.D .. "-" .. counts.L
end
local function competition_ranks(values)
    return map(values, function(value)
        local rank = 1
        for _, other in ipairs(values) do if report.compare(other, value) > 0 then rank = rank + 1 end end
        return rank
    end)
end
local function appearances_of(team, matches)
    local appearances = {}
    for _, match in ipairs(matches) do
        if match.home == team or match.away == team then
            local home = match.home == team
            local scored, conceded = home and match.home_score or match.away_score, home and match.away_score or match.home_score
            appearances[#appearances + 1] = {match = match, home = home, opponent = home and match.away or match.home,
                scored = scored, conceded = conceded, letter = result_letter(scored, conceded)}
        end
    end
    return appearances
end
local function add_record(record, scored, conceded, settings)
    record.played, record.scored, record.conceded = record.played + 1, record.scored + scored, record.conceded + conceded
    if scored > conceded then record.won, record.points = record.won + 1, record.points + settings.win_points
    elseif scored == conceded then record.drawn, record.points = record.drawn + 1, record.points + settings.draw_points
    else record.lost = record.lost + 1 end
end
local function team_records(count, matches, settings)
    local records = {}
    for team = 1, count do records[team] = {played = 0, won = 0, drawn = 0, lost = 0, scored = 0, conceded = 0, points = 0} end
    for _, match in ipairs(matches) do
        add_record(records[match.home], match.home_score, match.away_score, settings)
        add_record(records[match.away], match.away_score, match.home_score, settings)
    end
    return records
end
local function percentage(record) return Fraction.new(2 * record.won + record.drawn, 2 * record.played) end

local function standings(teams, matches, settings)
    local count = #teams
    local result = {records = team_records(count, matches, settings), h2h_points = zeros(count), h2h_difference = zeros(count), order = indices(count), positions = {}}
    for _, match in ipairs(matches) do
        local i, j = match.home, match.away
        if result.records[i].points == result.records[j].points then
            local hp = match.margin > 0 and settings.win_points or match.margin == 0 and settings.draw_points or 0
            local ap = match.margin < 0 and settings.win_points or match.margin == 0 and settings.draw_points or 0
            result.h2h_points[i], result.h2h_points[j] = result.h2h_points[i] + hp, result.h2h_points[j] + ap
            result.h2h_difference[i], result.h2h_difference[j] = result.h2h_difference[i] + match.margin, result.h2h_difference[j] - match.margin
        end
    end
    table.sort(result.order, function(a, b)
        local first, second = result.records[a], result.records[b]
        local one = {first.points, result.h2h_points[a], result.h2h_difference[a], first.scored - first.conceded, first.scored}
        local two = {second.points, result.h2h_points[b], result.h2h_difference[b], second.scored - second.conceded, second.scored}
        for index = 1, #one do if one[index] ~= two[index] then return one[index] > two[index] end end
        return teams[a].code < teams[b].code
    end)
    for position, team in ipairs(result.order) do result.positions[team] = position end
    return result
end

local function longest_streak(appearances, unbeaten)
    local best, start, length = {length = 0, first = 0, last = 0}, 1, 0
    for index, appearance in ipairs(appearances) do
        if appearance.letter == "W" or unbeaten and appearance.letter == "D" then
            if length == 0 then start = index end
            length = length + 1
            if length > best.length then best = {length = length, first = appearances[start].match.round, last = appearance.match.round} end
        else length = 0 end
    end
    return best
end
local function current_streak(appearances)
    local last, count = appearances[#appearances].letter, 0
    for index = #appearances, 1, -1 do if appearances[index].letter ~= last then break end count = count + 1 end
    return last .. count
end

local Fit = {}
Fit.__index = Fit
function Fit.new(count, matches, settings)
    local self = setmetatable({}, Fit)
    self.elo = elo.run_elo(count, matches, settings.elo_k, settings.elo_home, settings.elo_initial)
    self.colley = linear.colley_ratings(count, matches)
    self.massey, self.home_advantage = linear.massey_ratings(count, matches)
    self.strengths, self.home_factor = iterative.bradley_terry(count, matches, settings.bt_iterations)
    self.offense, self.defense, self.od = iterative.offense_defense(count, matches, settings.od_iterations)
    self.win_percentages = map(team_records(count, matches, settings), percentage)
    return self
end
function Fit:feature(model, match)
    local home, away = match.home, match.away
    if model == "colley" then return self.colley[home] - self.colley[away] end
    if model == "massey" then return self.massey[home] - self.massey[away] end
    if model == "od" then return math.log(self.od[home]) - math.log(self.od[away]) end
    return self.win_percentages[home]:real() - self.win_percentages[away]:real()
end

local function validation_round(number, count, matches, settings)
    local validation = {number = number, training = season.matches_before(matches, number), links = {}, predictions = {}}
    validation.fit = Fit.new(count, validation.training, settings)
    local results = map(validation.training, function(match) return match.y end)
    validation.base = sum(map(validation.training, function(match) return match.y2 end)) / (2 * #validation.training)
    for _, model in ipairs(link_models) do
        local features = map(validation.training, function(match) return validation.fit:feature(model, match) end)
        local alpha, beta = evaluation.fit_link(features, results, settings.link_iterations)
        validation.links[model] = {alpha, beta}
    end
    for _, match in ipairs(matches) do
        if match.round == number then
            local fit = validation.fit
            local values = {base = validation.base, elo = elo.expected_score(fit.elo.ratings[match.home], fit.elo.ratings[match.away], settings.elo_home)}
            for _, model in ipairs(link_models) do local link = validation.links[model] values[model] = evaluation.sigma(link[1] + link[2] * fit:feature(model, match)) end
            local home = fit.home_factor * fit.strengths[match.home]
            values.bt = home / (home + fit.strengths[match.away])
            local ensemble = 0.0
            for _, model in ipairs(rating_models) do ensemble = ensemble + values[model] end
            values.ensemble = ensemble / #rating_models
            local probabilities = map(prediction_models, function(model) return values[model] end)
            local prediction = {match = match, probabilities = probabilities, margin_error = match.margin - (fit.massey[match.home] - fit.massey[match.away] + fit.home_advantage)}
            prediction.losses = map(probabilities, function(p) return evaluation.log_loss(p, match.y) end)
            prediction.briers = map(probabilities, function(p) return evaluation.brier_score(p, match.y) end)
            prediction.scores2 = map(probabilities, function(p) return evaluation.correctness2(p, match.y) end)
            validation.predictions[#validation.predictions + 1] = prediction
        end
    end
    return validation
end

local function model_scores(predictions)
    local scores = {losses = {}, briers = {}, skills = {}, accuracies = {}, loss_ranking = indices(#prediction_models), brier_ranking = indices(#prediction_models), accuracy_ranking = indices(#prediction_models)}
    for index = 1, #prediction_models do
        scores.losses[index] = mean(map(predictions, function(item) return item.losses[index] end))
        scores.briers[index] = mean(map(predictions, function(item) return item.briers[index] end))
        scores.accuracies[index] = Fraction.new(sum(map(predictions, function(item) return item.scores2[index] end)), 2 * #predictions)
    end
    for index, brier in ipairs(scores.briers) do scores.skills[index] = 1 - brier / scores.briers[1] end
    local function rank(values, descending, fractional)
        return function(a, b)
            local order
            if fractional then order = report.compare(values[a], values[b])
            else order = report.compare(report.decimal_value(values[a], 4), report.decimal_value(values[b], 4)) end
            if order == 0 then return a < b end
            return descending and order > 0 or not descending and order < 0
        end
    end
    table.sort(scores.loss_ranking, rank(scores.losses, false, false))
    table.sort(scores.brier_ranking, rank(scores.briers, false, false))
    table.sort(scores.accuracy_ranking, rank(scores.accuracies, true, true))
    return scores
end

local function projection(teams, matches, settings)
    local count, current_matches = #teams, season.matches_before(matches, settings.holdout_round)
    local result = {current = standings(teams, current_matches, settings), remaining = {}, total_points = zeros(count), titles = zeros(count), tops = zeros(count), bottoms = zeros(count), ranks = {}}
    result.ratings = elo.run_elo(count, current_matches, settings.elo_k, settings.elo_home, settings.elo_initial).ratings
    for _, match in ipairs(matches) do if match.round >= settings.holdout_round then result.remaining[#result.remaining + 1] = match end end
    local probabilities = map(result.remaining, function(match) return elo.expected_score(result.ratings[match.home], result.ratings[match.away], settings.elo_home) end)
    local function ordering(points)
        local order = indices(count)
        table.sort(order, function(a, b) return points[a] > points[b] or points[a] == points[b] and result.current.positions[a] < result.current.positions[b] end)
        return order
    end
    local state = settings.seed
    for _ = 1, settings.simulations do
        local points = map(result.current.records, function(record) return record.points end)
        for index, match in ipairs(result.remaining) do
            state = 48271 * state % 2147483647
            local winner = state / 2147483647 < probabilities[index] and match.home or match.away
            points[winner] = points[winner] + settings.win_points
        end
        for place, team in ipairs(ordering(points)) do
            result.total_points[team] = result.total_points[team] + points[team]
            if place == 1 then result.titles[team] = result.titles[team] + 1 end
            if place <= settings.top_positions then result.tops[team] = result.tops[team] + 1 end
            if place >= count - settings.bottom_positions + 1 then result.bottoms[team] = result.bottoms[team] + 1 end
        end
    end
    result.order = ordering(result.total_points)
    for rank, team in ipairs(result.order) do result.ranks[team] = rank end
    return result
end

local Analysis = {}
Analysis.__index = Analysis
function Analysis.new(teams, matches, settings)
    local self = setmetatable({teams = teams, matches = matches, settings = settings, team_count = #teams,
        final_round = matches[#matches].round, appearances = {}, round_tables = {}, win_streaks = {}, unbeaten_streaks = {}, rounds = {}, predictions = {}}, Analysis)
    for team = 1, #teams do self.appearances[team] = appearances_of(team, matches) end
    self.final = standings(teams, matches, settings)
    self.fit = Fit.new(#teams, matches, settings)
    for number = 1, self.final_round do self.round_tables[number] = standings(teams, season.matches_before(matches, number + 1), settings) end
    for team, items in ipairs(self.appearances) do self.win_streaks[team], self.unbeaten_streaks[team] = longest_streak(items, false), longest_streak(items, true) end
    local function opponent_average(team, values)
        local total = Fraction.new(0)
        for _, appearance in ipairs(self.appearances[team]) do total = total + values[appearance.opponent] end
        return total / #self.appearances[team]
    end
    self.sos, self.sos2, self.rpi, self.pythag, self.luck = {}, {}, {}, {}, {}
    for team = 1, #teams do self.sos[team] = opponent_average(team, self.fit.win_percentages) end
    for team = 1, #teams do self.sos2[team] = opponent_average(team, self.sos) end
    for team, record in ipairs(self.final.records) do
        self.rpi[team] = (self.fit.win_percentages[team] + 2 * self.sos[team] + self.sos2[team]) / 4
        self.pythag[team] = 1 / (1 + (record.conceded / record.scored) ^ settings.pythagorean_exponent)
        self.luck[team] = self.fit.win_percentages[team]:real() - self.pythag[team]
    end
    local function rounded(values, places) return map(values, function(value) return report.decimal_value(value, places) end) end
    self.comparison = {standings = map(self.final.positions, function(position) return -position end), elo = rounded(self.fit.elo.ratings, 2),
        colley = rounded(self.fit.colley, 4), massey = rounded(self.fit.massey, 4), bt = rounded(self.fit.strengths, 4), od = rounded(self.fit.od, 2),
        winpct = self.fit.win_percentages, rpi = self.rpi, pythag = rounded(self.pythag, 4)}
    self.ranks = {}
    for _, model in ipairs(rating_models) do self.ranks[model] = competition_ranks(self.comparison[model]) end
    for number = settings.holdout_round, self.final_round do
        local round = validation_round(number, #teams, matches, settings)
        self.rounds[#self.rounds + 1] = round
        extend(self.predictions, round.predictions)
    end
    self.scores = model_scores(self.predictions)
    self.projection = projection(teams, matches, settings)
    return self
end
function Analysis:code(team) return self.teams[team].code end

function Analysis:standings_lines()
    local lines = {standings_header}
    for position, team in ipairs(self.final.order) do
        local record, appearances = self.final.records[team], self.appearances[team]
        local home, away, close, form = {}, {}, {}, {}
        for index, item in ipairs(appearances) do
            local side = item.home and home or away side[#side + 1] = item
            if math.abs(item.scored - item.conceded) <= self.settings.close_margin then close[#close + 1] = item end
            if index > #appearances - self.settings.form_length then form[#form + 1] = item.letter end
        end
        lines[#lines + 1] = csv({position, self:code(team), self.teams[team].name, record.played, record.won, record.drawn, record.lost, record.scored, record.conceded,
            record.scored - record.conceded, record.points, record_text(home), record_text(away), table.concat(form), current_streak(appearances), record_text(close),
            self.win_streaks[team].length, self.unbeaten_streaks[team].length, report.fraction_text(self.fit.win_percentages[team]), report.fixed(self.sos[team]),
            report.fixed(self.sos2[team]), report.fixed(self.rpi[team]), report.fixed(self.pythag[team]), report.fixed(self.luck[team])})
    end
    return lines
end

function Analysis:ratings_lines()
    local totals = zeros(self.team_count)
    for _, model in ipairs(rating_models) do for team, rank in ipairs(self.ranks[model]) do totals[team] = totals[team] + rank end end
    local order = indices(self.team_count)
    table.sort(order, function(a, b) return totals[a] < totals[b] or totals[a] == totals[b] and self:code(a) < self:code(b) end)
    local fit, lines = self.fit, {ratings_header}
    for _, team in ipairs(order) do
        local best, worst = self.team_count, 1
        for _, model in ipairs(rating_models) do best, worst = math.min(best, self.ranks[model][team]), math.max(worst, self.ranks[model][team]) end
        lines[#lines + 1] = csv({self:code(team), report.fixed(fit.elo.ratings[team], 2), self.ranks.elo[team], report.fixed(fit.colley[team]), self.ranks.colley[team],
            report.fixed(fit.massey[team]), self.ranks.massey[team], report.fixed(fit.strengths[team]), self.ranks.bt[team], report.fixed(fit.offense[team], 2),
            report.fixed(fit.defense[team]), report.fixed(fit.od[team], 2), self.ranks.od[team], report.fixed(fit.win_percentages[team]), self.ranks.winpct[team], totals[team], best, worst})
    end
    return lines
end

function Analysis:history_lines()
    local lines, previous = {"round,team,elo,change,elo_rank,points,position"}, zeros(self.team_count, self.settings.elo_initial + 0.0)
    for number, table in ipairs(self.round_tables) do
        local ratings = self.fit.elo.round_ratings[number]
        local ranks = competition_ranks(map(ratings, function(value) return report.decimal_value(value, 2) end))
        for team = 1, self.team_count do lines[#lines + 1] = csv({number, self:code(team), report.fixed(ratings[team], 2), report.fixed(ratings[team] - previous[team], 2), ranks[team], table.records[team].points, table.positions[team]}) end
        previous = ratings
    end
    return lines
end

function Analysis:season_lines()
    local won, drawn, lost, y2 = 0, 0, 0, 0
    for _, match in ipairs(self.matches) do
        y2 = y2 + match.y2
        if match.y2 == 2 then won = won + 1 elseif match.y2 == 1 then drawn = drawn + 1 else lost = lost + 1 end
    end
    local summary = {"season teams " .. self.team_count .. " matches " .. #self.matches .. " rounds " .. self.final_round,
        "home won " .. won .. " drawn " .. drawn .. " lost " .. lost .. " rate " .. report.fraction_with_real(Fraction.new(y2, 2 * #self.matches)),
        "massey_home_advantage " .. report.fixed(self.fit.home_advantage), "bt_home_factor " .. report.fixed(self.fit.home_factor)}
    local upsets, candidates = {"upsets top " .. self.settings.upsets}, {}
    for index, match in ipairs(self.matches) do
        if match.margin ~= 0 then candidates[#candidates + 1] = {match = match, index = index,
            expected = match.margin > 0 and self.fit.elo.expected[index] or 1 - self.fit.elo.expected[index], gain = math.abs(self.fit.elo.changes[index])} end
    end
    table.sort(candidates, function(a, b)
        local first, second = report.decimal_value(a.expected, 4), report.decimal_value(b.expected, 4)
        return first < second or first == second and a.index < b.index
    end)
    for index = 1, math.min(self.settings.upsets, #candidates) do
        local item = candidates[index] local match = item.match local home = match.margin > 0
        local winner, loser = home and match.home or match.away, home and match.away or match.home
        local scored, conceded = home and match.home_score or match.away_score, home and match.away_score or match.home_score
        upsets[#upsets + 1] = "round " .. match.round .. " " .. self:code(winner) .. " beat " .. self:code(loser) .. " " .. scored .. "-" .. conceded .. " " .. (home and "home" or "away") .. " expected " .. report.fixed(item.expected) .. " gain " .. report.fixed(item.gain, 2)
    end
    local tiebreaks, groups = {"tiebreaks"}, {}
    for _, team in ipairs(self.final.order) do
        local last = groups[#groups]
        if last and self.final.records[last[1]].points == self.final.records[team].points then last[#last + 1] = team else groups[#groups + 1] = {team} end
    end
    for _, group in ipairs(groups) do
        if #group >= 2 then
            tiebreaks[#tiebreaks + 1] = "points " .. self.final.records[group[1]].points .. " order " .. table.concat(map(group, function(team) return self:code(team) end), " ")
                .. " h2h_points " .. table.concat(map(group, function(team) return tostring(self.final.h2h_points[team]) end), " ") .. " h2h_diff " .. table.concat(map(group, function(team) return tostring(self.final.h2h_difference[team]) end), " ")
        end
    end
    if #tiebreaks == 1 then tiebreaks[#tiebreaks + 1] = "none" end
    local leaders, previous, changes = {"leaders"}, nil, 0
    for round, table in ipairs(self.round_tables) do
        local leader = table.order[1]
        if leader ~= previous then leaders[#leaders + 1] = "round " .. round .. " " .. self:code(leader) .. " points " .. table.records[leader].points changes = changes + 1 end
        previous = leader
    end
    leaders[#leaders + 1] = "lead_changes " .. (changes - 1)
    local streaks = {}
    for _, item in ipairs({{"longest_win_streak", self.win_streaks}, {"longest_unbeaten_streak", self.unbeaten_streaks}}) do
        local maximum = 0
        for _, streak in ipairs(item[2]) do maximum = math.max(maximum, streak.length) end
        for team, streak in ipairs(item[2]) do if streak.length == maximum then streaks[#streaks + 1] = item[1] .. " " .. self:code(team) .. " length " .. streak.length .. " rounds " .. streak.first .. "-" .. streak.last end end
    end
    local top = {} for index = 1, self.settings.top_positions do top[index] = self.final.order[index] end
    local crosstable = {"crosstable top " .. self.settings.top_positions, "team " .. table.concat(map(top, function(team) return self:code(team) end), " ")}
    for _, first in ipairs(top) do
        local entries = {}
        for _, second in ipairs(top) do
            if first == second then entries[#entries + 1] = "-"
            else local meetings = {} for _, item in ipairs(self.appearances[first]) do if item.opponent == second then meetings[#meetings + 1] = item end end entries[#entries + 1] = record_text(meetings) end
        end
        crosstable[#crosstable + 1] = self:code(first) .. " " .. table.concat(entries, " ")
    end
    local trajectories = {"trajectories"}
    for team = 1, self.team_count do
        local peak, low, best, worst = 1, 1, 1, 1
        for round = 2, self.final_round do
            local key = report.decimal_value(self.fit.elo.round_ratings[round][team], 2)
            if key > report.decimal_value(self.fit.elo.round_ratings[peak][team], 2) then peak = round end
            if key < report.decimal_value(self.fit.elo.round_ratings[low][team], 2) then low = round end
            if self.round_tables[round].positions[team] < self.round_tables[best].positions[team] then best = round end
            if self.round_tables[round].positions[team] > self.round_tables[worst].positions[team] then worst = round end
        end
        trajectories[#trajectories + 1] = self:code(team) .. " elo_peak " .. report.fixed(self.fit.elo.round_ratings[peak][team], 2) .. " round " .. peak
            .. " elo_low " .. report.fixed(self.fit.elo.round_ratings[low][team], 2) .. " round " .. low .. " best_position " .. self.round_tables[best].positions[team] .. " round " .. best .. " worst_position " .. self.round_tables[worst].positions[team] .. " round " .. worst
    end
    local correlations = {}
    for _, item in ipairs({{"kendall", evaluation.kendall_tau}, {"spearman", evaluation.spearman_rho}}) do
        local lines = {item[1], "model " .. table.concat(comparison_models, " ")}
        for _, first in ipairs(comparison_models) do
            local values = map(comparison_models, function(second) return report.fraction_text(item[2](self.comparison[first], self.comparison[second])) end)
            lines[#lines + 1] = first .. " " .. table.concat(values, " ")
        end
        correlations[#correlations + 1] = lines
    end
    local most, least
    for i = 1, #comparison_models do
        for j = i + 1, #comparison_models do
            local a, b = comparison_models[i], comparison_models[j]
            local pair = {a, b, evaluation.kendall_tau(self.comparison[a], self.comparison[b])}
            if most == nil or report.compare(pair[3], most[3]) > 0 then most = pair end
            if least == nil or report.compare(pair[3], least[3]) < 0 then least = pair end
        end
    end
    local similarity = {"most_similar " .. most[1] .. " " .. most[2] .. " tau " .. report.fraction_with_real(most[3]), "least_similar " .. least[1] .. " " .. least[2] .. " tau " .. report.fraction_with_real(least[3])}
    return join_parts({summary, upsets, tiebreaks, leaders, streaks, crosstable, trajectories, correlations[1], correlations[2], similarity})
end

function Analysis:prediction_lines()
    local lines = {"round,home,away,home_score,away_score,result," .. table.concat(prediction_models, ",")}
    for _, prediction in ipairs(self.predictions) do
        local match = prediction.match
        local fields = {match.round, self:code(match.home), self:code(match.away), match.home_score, match.away_score, match.y2 == 2 and "H" or match.y2 == 0 and "A" or "D"}
        extend(fields, map(prediction.probabilities, function(value) return report.fixed(value) end))
        lines[#lines + 1] = csv(fields)
    end
    return lines
end

function Analysis:projection_tau()
    return evaluation.kendall_tau(map(self.projection.ranks, function(rank) return -rank end), map(self.final.positions, function(position) return -position end))
end

function Analysis:evaluation_lines()
    local links = {"links"}
    for _, validation in ipairs(self.rounds) do
        local parts = {"round " .. validation.number .. " train " .. #validation.training .. " base " .. report.fixed(validation.base) .. " bt_home " .. report.fixed(validation.fit.home_factor)}
        for _, model in ipairs(link_models) do local values = validation.links[model] parts[#parts + 1] = model .. " " .. report.fixed(values[1]) .. " " .. report.fixed(values[2]) end
        links[#links + 1] = table.concat(parts, " ")
    end
    local scores, score_lines = self.scores, {"scores", "model log_loss brier skill accuracy"}
    for index, model in ipairs(prediction_models) do score_lines[#score_lines + 1] = model .. " " .. report.fixed(scores.losses[index]) .. " " .. report.fixed(scores.briers[index]) .. " " .. report.fixed(scores.skills[index]) .. " " .. report.fraction_with_real(scores.accuracies[index]) end
    for _, item in ipairs({{"ranking_log_loss", scores.loss_ranking}, {"ranking_brier", scores.brier_ranking}, {"ranking_accuracy", scores.accuracy_ranking}}) do
        score_lines[#score_lines + 1] = item[1] .. " " .. table.concat(map(item[2], function(index) return prediction_models[index] end), " ")
    end
    local reference, count = scores.loss_ranking[1], #self.predictions
    local paired = {"paired_log_loss reference " .. prediction_models[reference]}
    for index, model in ipairs(prediction_models) do
        if index ~= reference then
            local deltas = map(self.predictions, function(item) return item.losses[index] - item.losses[reference] end)
            local average, squares = mean(deltas), 0.0
            for _, delta in ipairs(deltas) do squares = squares + (delta - average) * (delta - average) end
            local spread = math.sqrt(squares / (count - 1))
            local t_value = average / (spread / math.sqrt(count))
            paired[#paired + 1] = model .. " mean_diff " .. report.fixed(average) .. " sd " .. report.fixed(spread) .. " t " .. report.fixed(t_value, 2)
        end
    end
    local errors = map(self.predictions, function(item) return item.margin_error end)
    local absolute = mean(map(errors, function(value) return math.abs(value) end))
    local squared = math.sqrt(mean(map(errors, function(value) return value * value end)))
    local margin = {"massey_margin mae " .. report.fixed(absolute) .. " rmse " .. report.fixed(squared) .. " bias " .. report.fixed(mean(errors))}
    local rounds = {"round_log_loss", "round " .. table.concat(prediction_models, " ")}
    for _, validation in ipairs(self.rounds) do
        local losses = {}
        for index = 1, #prediction_models do losses[index] = report.fixed(mean(map(validation.predictions, function(item) return item.losses[index] end))) end
        rounds[#rounds + 1] = validation.number .. " " .. table.concat(losses, " ")
    end
    local bins, calibration = self.settings.calibration_bins, {"calibration bins " .. self.settings.calibration_bins}
    for index, model in ipairs(prediction_models) do
        local members = {}
        for bin = 1, bins do members[bin] = {} end
        for _, prediction in ipairs(self.predictions) do
            local bin = math.min(math.floor(bins * prediction.probabilities[index]) + 1, bins)
            local group = members[bin] group[#group + 1] = prediction
        end
        for bin, group in ipairs(members) do
            local predicted, observed = "-", "-"
            if #group > 0 then
                predicted = report.fixed(mean(map(group, function(item) return item.probabilities[index] end)))
                observed = report.fraction_text(Fraction.new(sum(map(group, function(item) return item.match.y2 end)), 2 * #group))
            end
            calibration[#calibration + 1] = model .. " bin " .. bin .. " count " .. #group .. " predicted " .. predicted .. " observed " .. observed
        end
    end
    local grid = {"elo_grid", "k " .. table.concat(map(self.settings.grid_home, function(home) return "h" .. home end), " ")}
    local best
    for _, k_factor in ipairs(self.settings.grid_k) do
        local row = {tostring(k_factor)}
        for _, home in ipairs(self.settings.grid_home) do
            local run = elo.run_elo(self.team_count, self.matches, k_factor, home, self.settings.elo_initial)
            local losses = {}
            for index, match in ipairs(self.matches) do if match.round >= self.settings.holdout_round then losses[#losses + 1] = evaluation.log_loss(run.expected[index], match.y) end end
            local loss = mean(losses)
            row[#row + 1] = report.fixed(loss)
            if best == nil or report.decimal_value(loss, 4) < report.decimal_value(best[3], 4) then best = {k_factor, home, loss} end
        end
        grid[#grid + 1] = table.concat(row, " ")
    end
    grid[#grid + 1] = "best k " .. best[1] .. " home " .. best[2] .. " log_loss " .. report.fixed(best[3])
    return join_parts({{"holdout rounds " .. self.settings.holdout_round .. "-" .. self.final_round .. " matches " .. #self.predictions}, links,
        score_lines, paired, margin, rounds, calibration, grid, {"projection simulations " .. self.settings.simulations .. " kendall " .. report.fraction_with_real(self:projection_tau())}})
end

function Analysis:projection_lines()
    local projected, simulations, lines = self.projection, self.settings.simulations, {projection_header}
    for rank, team in ipairs(projected.order) do
        local opponents = {}
        for _, match in ipairs(projected.remaining) do
            if match.home == team then opponents[#opponents + 1] = projected.ratings[match.away]
            elseif match.away == team then opponents[#opponents + 1] = projected.ratings[match.home] end
        end
        lines[#lines + 1] = csv({rank, self:code(team), projected.current.records[team].points, projected.current.positions[team], report.fixed(mean(opponents), 2),
            report.fixed(Fraction.new(projected.total_points[team], simulations)), report.fixed(Fraction.new(projected.titles[team], simulations)),
            report.fixed(Fraction.new(projected.tops[team], simulations)), report.fixed(Fraction.new(projected.bottoms[team], simulations)), self.final.records[team].points, self.final.positions[team]})
    end
    return lines
end

local function main()
    local teams, matches, settings = season.load_season("input")
    local analysis = Analysis.new(teams, matches, settings)
    local files = {{"standings.csv", analysis:standings_lines()}, {"ratings.csv", analysis:ratings_lines()}, {"history.csv", analysis:history_lines()},
        {"season.txt", analysis:season_lines()}, {"predictions.csv", analysis:prediction_lines()}, {"evaluation.txt", analysis:evaluation_lines()}, {"projection.csv", analysis:projection_lines()}}
    os.execute("mkdir -p output")
    for _, file in ipairs(files) do report.write_lines("output/" .. file[1], file[2]) end
end

main()
