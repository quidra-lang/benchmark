include("report.jl")
include("season.jl")
include("elo.jl")
include("linear_models.jl")
include("iterative_models.jl")
include("evaluation.jl")

const RATING_MODELS = ["elo", "colley", "massey", "bt", "od", "winpct"]
const COMPARISON_MODELS = ["standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag"]
const LINK_MODELS = ["colley", "massey", "od", "winpct"]
const PREDICTION_MODELS = ["base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble"]
const STANDINGS_HEADER = "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck"
const RATINGS_HEADER = "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank"
const HISTORY_HEADER = "round,team,elo,change,elo_rank,points,position"
const PROJECTION_HEADER = "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position"
function sequential_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
mean_values(values::Vector{Float64}) = sequential_sum(values) / length(values)
competition_ranks(values::Vector{Rational{Int}}) = [1 + count(other -> other > value, values) for value in values]
rounded_values(values::Vector{Float64}, places::Int) = [decimal_value(value, places) // 1 for value in values]
csv_line(fields) = join(string.(fields), ',')
function join_parts(parts::Vector{Vector{String}})
    lines = String[]
    for part in parts
        isempty(lines) || push!(lines, "")
        append!(lines, part)
    end
    lines
end
struct Appearance
    game::Match
    home::Bool
    opponent::Int
    scored::Int
    conceded::Int
    letter::Char
end
function Appearance(game::Match, team::Int)
    home = game.home == team
    scored, conceded = home ? (game.home_score, game.away_score) : (game.away_score, game.home_score)
    opponent = home ? game.away : game.home
    letter = scored > conceded ? 'W' : (scored == conceded ? 'D' : 'L')
    Appearance(game, home, opponent, scored, conceded, letter)
end
appearances_of(team::Int, matches::Vector{Match}) = [Appearance(game, team) for game in matches if game.home == team || game.away == team]
function record_text(appearances::Vector{Appearance})
    won = count(item -> item.letter == 'W', appearances)
    drawn = count(item -> item.letter == 'D', appearances)
    lost = count(item -> item.letter == 'L', appearances)
    "$won-$drawn-$lost"
end
mutable struct Record
    played::Int
    won::Int
    drawn::Int
    lost::Int
    scored::Int
    conceded::Int
    points::Int
end
Record() = Record(0, 0, 0, 0, 0, 0, 0)
function add_result!(record::Record, scored::Int, conceded::Int, settings::Settings)
    record.played += 1
    record.scored += scored
    record.conceded += conceded
    if scored > conceded
        record.won += 1
        record.points += settings.win_points
    elseif scored == conceded
        record.drawn += 1
        record.points += settings.draw_points
    else
        record.lost += 1
    end
end
difference(record::Record) = record.scored - record.conceded
win_percentage(record::Record) = (2 * record.won + record.drawn) // (2 * record.played)
function team_records(count::Int, matches::Vector{Match}, settings::Settings)
    records = [Record() for _ in 1:count]
    for game in matches
        add_result!(records[game.home], game.home_score, game.away_score, settings)
        add_result!(records[game.away], game.away_score, game.home_score, settings)
    end
    records
end
struct Standings
    records::Vector{Record}
    h2h_points::Vector{Int}
    h2h_difference::Vector{Int}
    order::Vector{Int}
    positions::Vector{Int}
end
function Standings(teams::Vector{Team}, matches::Vector{Match}, settings::Settings)
    count = length(teams)
    records = team_records(count, matches, settings)
    groups = Dict{Int,Set{Int}}()
    for team in 1:count
        push!(get!(groups, records[team].points, Set{Int}()), team)
    end
    h2h_points = zeros(Int, count)
    h2h_difference = zeros(Int, count)
    for members in values(groups)
        inner = team_records(count, filter(game -> game.home in members && game.away in members, matches), settings)
        for team in members
            h2h_points[team] = inner[team].points
            h2h_difference[team] = difference(inner[team])
        end
    end
    order = sort!(collect(1:count); by=team -> (-records[team].points, -h2h_points[team], -h2h_difference[team], -difference(records[team]), -records[team].scored, teams[team].code))
    positions = zeros(Int, count)
    for (position, team) in enumerate(order)
        positions[team] = position
    end
    Standings(records, h2h_points, h2h_difference, order, positions)
end
function tied_groups(table::Standings)
    groups = Vector{Int}[]
    for team in table.order
        if !isempty(groups) && table.records[groups[end][1]].points == table.records[team].points
            push!(groups[end], team)
        else
            push!(groups, [team])
        end
    end
    filter(group -> length(group) >= 2, groups)
end
struct Streak
    length::Int
    first::Int
    last::Int
end
function longest_streak(appearances::Vector{Appearance}, unbeaten::Bool)
    best = Streak(0, 0, 0)
    start = 0
    length = 0
    for (index, item) in enumerate(appearances)
        if item.letter != 'W' && !(unbeaten && item.letter == 'D')
            length = 0
            continue
        end
        length == 0 && (start = index)
        length += 1
        length > best.length && (best = Streak(length, appearances[start].game.round, item.game.round))
    end
    best
end
function current_streak(appearances::Vector{Appearance})
    last = appearances[end].letter
    count = 0
    for item in Iterators.reverse(appearances)
        item.letter == last || break
        count += 1
    end
    "$last$count"
end
struct ModelFit
    elo::EloRun
    colley::Vector{Float64}
    massey::Vector{Float64}
    home_advantage::Float64
    strengths::Vector{Float64}
    home_factor::Float64
    offense::Vector{Float64}
    defense::Vector{Float64}
    od::Vector{Float64}
    win_percentages::Vector{Rational{Int}}
end
function ModelFit(count::Int, matches::Vector{Match}, settings::Settings)
    elo = run_elo(count, matches, settings.elo_k, settings.elo_home, settings.elo_initial)
    colley = colley_ratings(count, matches)
    massey, home_advantage = massey_ratings(count, matches)
    strengths, home_factor = bradley_terry(count, matches, settings.bt_iterations)
    offense, defense, od = offense_defense(count, matches, settings.od_iterations)
    percentages = win_percentage.(team_records(count, matches, settings))
    ModelFit(elo, colley, massey, home_advantage, strengths, home_factor, offense, defense, od, percentages)
end
function feature(fit::ModelFit, model::Int, game::Match)
    model == 1 && return fit.colley[game.home] - fit.colley[game.away]
    model == 2 && return fit.massey[game.home] - fit.massey[game.away]
    model == 3 && return log(fit.od[game.home]) - log(fit.od[game.away])
    Float64(fit.win_percentages[game.home]) - Float64(fit.win_percentages[game.away])
end
function bt_probability(fit::ModelFit, game::Match)
    home = fit.home_factor * fit.strengths[game.home]
    home / (home + fit.strengths[game.away])
end
predicted_margin(fit::ModelFit, game::Match) = fit.massey[game.home] - fit.massey[game.away] + fit.home_advantage
struct Prediction
    game::Match
    probabilities::Vector{Float64}
    losses::Vector{Float64}
    briers::Vector{Float64}
    scores::Vector{Int}
    margin_error::Float64
end
function Prediction(game::Match, probabilities::Vector{Float64}, margin_error::Float64)
    losses = [log_loss(p, result_twice(game)) for p in probabilities]
    briers = [brier_score(p, result_twice(game)) for p in probabilities]
    scores = [correctness_twice(p, result_twice(game)) for p in probabilities]
    Prediction(game, probabilities, losses, briers, scores, margin_error)
end
struct ValidationRound
    number::Int
    training_count::Int
    fit::ModelFit
    base::Float64
    links::Vector{Tuple{Float64,Float64}}
    predictions::Vector{Prediction}
end
function ValidationRound(number::Int, count::Int, matches::Vector{Match}, settings::Settings)
    training = matches_before(matches, number)
    fit = ModelFit(count, training, settings)
    base = Float64(sum(result_twice(game) for game in training) // (2 * length(training)))
    results = result_value.(training)
    links = [fit_link([feature(fit, model, game) for game in training], results, settings.link_iterations) for model in 1:4]
    predictions = Prediction[]
    for game in matches
        game.round == number || continue
        probabilities = zeros(8)
        probabilities[1] = base
        probabilities[2] = expected_score(fit.elo.ratings[game.home], fit.elo.ratings[game.away], settings.elo_home)
        for (model, target) in enumerate([3, 4, 6, 7])
            probabilities[target] = sigma(links[model][1] + links[model][2] * feature(fit, model, game))
        end
        probabilities[5] = bt_probability(fit, game)
        probabilities[8] = sequential_sum(probabilities[index] for index in [2, 3, 4, 5, 6, 7]) / 6
        error = margin(game) - predicted_margin(fit, game)
        push!(predictions, Prediction(game, probabilities, error))
    end
    ValidationRound(number, length(training), fit, base, links, predictions)
end
struct ModelScores
    losses::Vector{Float64}
    briers::Vector{Float64}
    skills::Vector{Float64}
    accuracies::Vector{Rational{Int}}
    loss_ranking::Vector{Int}
    brier_ranking::Vector{Int}
    accuracy_ranking::Vector{Int}
end
function ModelScores(predictions::Vector{Prediction})
    count = length(predictions)
    losses = [sequential_sum(item.losses[model] for item in predictions) / count for model in 1:8]
    briers = [sequential_sum(item.briers[model] for item in predictions) / count for model in 1:8]
    skills = [1 - brier / briers[1] for brier in briers]
    accuracies = [sum(item.scores[model] for item in predictions) // (2 * count) for model in 1:8]
    loss_ranking = sort!(collect(1:8); by=model -> (decimal_value(losses[model], 4), model))
    brier_ranking = sort!(collect(1:8); by=model -> (decimal_value(briers[model], 4), model))
    accuracy_ranking = sort!(collect(1:8); by=model -> (-accuracies[model], model))
    ModelScores(losses, briers, skills, accuracies, loss_ranking, brier_ranking, accuracy_ranking)
end
struct Projection
    current::Standings
    ratings::Vector{Float64}
    remaining::Vector{Match}
    total_points::Vector{Int}
    titles::Vector{Int}
    tops::Vector{Int}
    bottoms::Vector{Int}
    order::Vector{Int}
    ranks::Vector{Int}
end
function Projection(teams::Vector{Team}, matches::Vector{Match}, settings::Settings)
    count = length(teams)
    current_matches = matches_before(matches, settings.holdout_round)
    current = Standings(teams, current_matches, settings)
    ratings = run_elo(count, current_matches, settings.elo_k, settings.elo_home, settings.elo_initial).ratings
    remaining = filter(game -> game.round >= settings.holdout_round, matches)
    probabilities = [expected_score(ratings[game.home], ratings[game.away], settings.elo_home) for game in remaining]
    total_points = zeros(Int, count)
    titles = zeros(Int, count)
    tops = zeros(Int, count)
    bottoms = zeros(Int, count)
    state = settings.seed
    for _ in 1:settings.simulations
        points = [record.points for record in current.records]
        for (game, probability) in zip(remaining, probabilities)
            state = 48271 * state % 2147483647
            winner = state / 2147483647 < probability ? game.home : game.away
            points[winner] += settings.win_points
        end
        order = sort!(collect(1:count); by=team -> (-points[team], current.positions[team]))
        for (place, team) in enumerate(order)
            total_points[team] += points[team]
            place == 1 && (titles[team] += 1)
            place <= settings.top_positions && (tops[team] += 1)
            place >= count - settings.bottom_positions + 1 && (bottoms[team] += 1)
        end
    end
    order = sort!(collect(1:count); by=team -> (-total_points[team], current.positions[team]))
    ranks = zeros(Int, count)
    for (rank, team) in enumerate(order)
        ranks[team] = rank
    end
    Projection(current, ratings, remaining, total_points, titles, tops, bottoms, order, ranks)
end
function opponent_strength(projection::Projection, team::Int)
    values = Float64[]
    for game in projection.remaining
        if game.home == team
            push!(values, projection.ratings[game.away])
        elseif game.away == team
            push!(values, projection.ratings[game.home])
        end
    end
    mean_values(values)
end
struct LeagueAnalysis
    teams::Vector{Team}
    matches::Vector{Match}
    settings::Settings
    appearances::Vector{Vector{Appearance}}
    final_table::Standings
    fit::ModelFit
    round_tables::Vector{Standings}
    win_streaks::Vector{Streak}
    unbeaten_streaks::Vector{Streak}
    sos::Vector{Rational{Int}}
    sos2::Vector{Rational{Int}}
    rpi::Vector{Rational{Int}}
    pythag::Vector{Float64}
    luck::Vector{Float64}
    comparison::Vector{Vector{Rational{Int}}}
    ranks::Vector{Vector{Int}}
    rounds::Vector{ValidationRound}
    scores::ModelScores
    projection::Projection
end
all_predictions(rounds::Vector{ValidationRound}) = [prediction for round in rounds for prediction in round.predictions]
function LeagueAnalysis(teams::Vector{Team}, matches::Vector{Match}, settings::Settings)
    count = length(teams)
    final_round = matches[end].round
    appearances = [appearances_of(team, matches) for team in 1:count]
    final_table = Standings(teams, matches, settings)
    fit = ModelFit(count, matches, settings)
    round_tables = [Standings(teams, matches_before(matches, round + 1), settings) for round in 1:final_round]
    win_streaks = [longest_streak(items, false) for items in appearances]
    unbeaten_streaks = [longest_streak(items, true) for items in appearances]
    function opponent_average(values::Vector{Rational{Int}})
        averages = Rational{Int}[]
        for items in appearances
            total = 0 // 1
            for item in items
                total += values[item.opponent]
            end
            push!(averages, total / length(items))
        end
        averages
    end
    sos = opponent_average(fit.win_percentages)
    sos2 = opponent_average(sos)
    rpi = [(fit.win_percentages[team] + 2 * sos[team] + sos2[team]) / 4 for team in 1:count]
    pythag = [1 / (1 + (record.conceded / record.scored)^settings.exponent) for record in final_table.records]
    luck = [Float64(fit.win_percentages[team]) - pythag[team] for team in 1:count]
    comparison = Vector{Rational{Int}}[[-position // 1 for position in final_table.positions], rounded_values(fit.elo.ratings, 2), rounded_values(fit.colley, 4), rounded_values(fit.massey, 4),
        rounded_values(fit.strengths, 4), rounded_values(fit.od, 2), fit.win_percentages, rpi, rounded_values(pythag, 4)]
    ranks = [competition_ranks(comparison[model]) for model in 2:(length(RATING_MODELS) + 1)]
    rounds = [ValidationRound(number, count, matches, settings) for number in settings.holdout_round:final_round]
    scores = ModelScores(all_predictions(rounds))
    projection = Projection(teams, matches, settings)
    LeagueAnalysis(teams, matches, settings, appearances, final_table, fit, round_tables, win_streaks, unbeaten_streaks, sos, sos2, rpi, pythag, luck, comparison, ranks, rounds, scores, projection)
end
team_code(analysis::LeagueAnalysis, team::Int) = analysis.teams[team].code
final_round(analysis::LeagueAnalysis) = length(analysis.round_tables)
function standings_lines(analysis::LeagueAnalysis)
    lines = [STANDINGS_HEADER]
    for (position, team) in enumerate(analysis.final_table.order)
        record = analysis.final_table.records[team]
        items = analysis.appearances[team]
        home = record_text(filter(item -> item.home, items))
        away = record_text(filter(item -> !item.home, items))
        close = record_text(filter(item -> abs(item.scored - item.conceded) <= analysis.settings.close_margin, items))
        form = join(item.letter for item in items[max(1, length(items) - analysis.settings.form_length + 1):end])
        push!(lines, csv_line([position, team_code(analysis, team), analysis.teams[team].name, record.played, record.won, record.drawn, record.lost, record.scored, record.conceded,
            difference(record), record.points, home, away, form, current_streak(items), close, analysis.win_streaks[team].length, analysis.unbeaten_streaks[team].length,
            fraction_text(analysis.fit.win_percentages[team]), fixed(analysis.sos[team]), fixed(analysis.sos2[team]), fixed(analysis.rpi[team]), fixed(analysis.pythag[team]), fixed(analysis.luck[team])]))
    end
    lines
end
function ratings_lines(analysis::LeagueAnalysis)
    fit = analysis.fit
    totals = [sum(ranks[team] for ranks in analysis.ranks) for team in eachindex(analysis.teams)]
    order = sort!(collect(eachindex(analysis.teams)); by=team -> (totals[team], team_code(analysis, team)))
    lines = [RATINGS_HEADER]
    for team in order
        ranks = [values[team] for values in analysis.ranks]
        push!(lines, csv_line([team_code(analysis, team), fixed(fit.elo.ratings[team], 2), ranks[1], fixed(fit.colley[team]), ranks[2], fixed(fit.massey[team]), ranks[3],
            fixed(fit.strengths[team]), ranks[4], fixed(fit.offense[team], 2), fixed(fit.defense[team]), fixed(fit.od[team], 2), ranks[5], fixed(fit.win_percentages[team]), ranks[6], totals[team], minimum(ranks), maximum(ranks)]))
    end
    lines
end
function history_lines(analysis::LeagueAnalysis)
    lines = [HISTORY_HEADER]
    previous = fill(Float64(analysis.settings.elo_initial), length(analysis.teams))
    for (round, table) in enumerate(analysis.round_tables)
        ratings = analysis.fit.elo.round_ratings[round]
        ranks = competition_ranks(rounded_values(ratings, 2))
        for team in eachindex(analysis.teams)
            push!(lines, csv_line([round, team_code(analysis, team), fixed(ratings[team], 2), fixed(ratings[team] - previous[team], 2), ranks[team], table.records[team].points, table.positions[team]]))
        end
        previous = ratings
    end
    lines
end
function summary_lines(analysis::LeagueAnalysis)
    won = count(game -> result_twice(game) == 2, analysis.matches)
    drawn = count(game -> result_twice(game) == 1, analysis.matches)
    lost = length(analysis.matches) - won - drawn
    rate = (2 * won + drawn) // (2 * length(analysis.matches))
    ["season teams $(length(analysis.teams)) matches $(length(analysis.matches)) rounds $(final_round(analysis))", "home won $won drawn $drawn lost $lost rate $(fraction_with_real(rate))",
        "massey_home_advantage $(fixed(analysis.fit.home_advantage))", "bt_home_factor $(fixed(analysis.fit.home_factor))"]
end
function upset_lines(analysis::LeagueAnalysis)
    candidates = Tuple{Int,Float64}[]
    for (index, game) in enumerate(analysis.matches)
        margin(game) == 0 && continue
        expected = margin(game) > 0 ? analysis.fit.elo.expected[index] : 1 - analysis.fit.elo.expected[index]
        push!(candidates, (index, expected))
    end
    sort!(candidates; by=entry -> (decimal_value(entry[2], 4), entry[1]))
    lines = ["upsets top $(analysis.settings.upsets)"]
    for (index, expected) in candidates[1:min(length(candidates), analysis.settings.upsets)]
        game = analysis.matches[index]
        home = margin(game) > 0
        winner, loser = home ? (game.home, game.away) : (game.away, game.home)
        scored, conceded = home ? (game.home_score, game.away_score) : (game.away_score, game.home_score)
        side = home ? "home" : "away"
        push!(lines, "round $(game.round) $(team_code(analysis, winner)) beat $(team_code(analysis, loser)) $scored-$conceded $side expected $(fixed(expected)) gain $(fixed(abs(analysis.fit.elo.changes[index]), 2))")
    end
    lines
end
function tiebreak_lines(analysis::LeagueAnalysis)
    lines = ["tiebreaks"]
    for group in tied_groups(analysis.final_table)
        points = analysis.final_table.records[group[1]].points
        order = join((team_code(analysis, team) for team in group), ' ')
        h2h_points = join((analysis.final_table.h2h_points[team] for team in group), ' ')
        h2h_difference = join((analysis.final_table.h2h_difference[team] for team in group), ' ')
        push!(lines, "points $points order $order h2h_points $h2h_points h2h_diff $h2h_difference")
    end
    length(lines) == 1 && push!(lines, "none")
    lines
end
function leader_lines(analysis::LeagueAnalysis)
    lines = ["leaders"]
    previous = nothing
    recorded = 0
    for (round, table) in enumerate(analysis.round_tables)
        leader = table.order[1]
        if leader != previous
            push!(lines, "round $round $(team_code(analysis, leader)) points $(table.records[leader].points)")
            recorded += 1
        end
        previous = leader
    end
    push!(lines, "lead_changes $(recorded - 1)")
    lines
end
function streak_lines(analysis::LeagueAnalysis)
    lines = String[]
    for (label, streaks) in [("longest_win_streak", analysis.win_streaks), ("longest_unbeaten_streak", analysis.unbeaten_streaks)]
        longest = maximum(streak.length for streak in streaks)
        for (team, streak) in enumerate(streaks)
            if streak.length == longest
                push!(lines, "$label $(team_code(analysis, team)) length $(streak.length) rounds $(streak.first)-$(streak.last)")
            end
        end
    end
    lines
end
function crosstable_lines(analysis::LeagueAnalysis)
    top = analysis.final_table.order[1:analysis.settings.top_positions]
    lines = ["crosstable top $(analysis.settings.top_positions)", "team " * join((team_code(analysis, team) for team in top), ' ')]
    for first in top
        entries = [first == second ? "-" : record_text(filter(item -> item.opponent == second, analysis.appearances[first])) for second in top]
        push!(lines, team_code(analysis, first) * " " * join(entries, ' '))
    end
    lines
end
function trajectory_lines(analysis::LeagueAnalysis)
    lines = ["trajectories"]
    for team in eachindex(analysis.teams)
        ratings = [snapshot[team] for snapshot in analysis.fit.elo.round_ratings]
        rounded = [decimal_value(rating, 2) for rating in ratings]
        positions = [table.positions[team] for table in analysis.round_tables]
        peak = low = best = worst = 1
        for index in 2:final_round(analysis)
            rounded[index] > rounded[peak] && (peak = index)
            rounded[index] < rounded[low] && (low = index)
            positions[index] < positions[best] && (best = index)
            positions[index] > positions[worst] && (worst = index)
        end
        push!(lines, "$(team_code(analysis, team)) elo_peak $(fixed(ratings[peak], 2)) round $peak elo_low $(fixed(ratings[low], 2)) round $low best_position $(positions[best]) round $best worst_position $(positions[worst]) round $worst")
    end
    lines
end
function correlation_lines(analysis::LeagueAnalysis, title::String, measure)
    lines = [title, "model " * join(COMPARISON_MODELS, ' ')]
    for (first, label) in enumerate(COMPARISON_MODELS)
        values = [fraction_text(measure(analysis.comparison[first], second)) for second in analysis.comparison]
        push!(lines, label * " " * join(values, ' '))
    end
    lines
end
function similarity_lines(analysis::LeagueAnalysis)
    pairs = Tuple{Int,Int,Rational{Int}}[]
    for first in eachindex(COMPARISON_MODELS), second in (first + 1):length(COMPARISON_MODELS)
        push!(pairs, (first, second, kendall_tau(analysis.comparison[first], analysis.comparison[second])))
    end
    most = least = pairs[1]
    for pair in pairs[2:end]
        pair[3] > most[3] && (most = pair)
        pair[3] < least[3] && (least = pair)
    end
    ["$label $(COMPARISON_MODELS[pair[1]]) $(COMPARISON_MODELS[pair[2]]) tau $(fraction_with_real(pair[3]))" for (label, pair) in [("most_similar", most), ("least_similar", least)]]
end
function season_lines(analysis::LeagueAnalysis)
    join_parts([summary_lines(analysis), upset_lines(analysis), tiebreak_lines(analysis), leader_lines(analysis), streak_lines(analysis), crosstable_lines(analysis), trajectory_lines(analysis),
        correlation_lines(analysis, "kendall", kendall_tau), correlation_lines(analysis, "spearman", spearman_rho), similarity_lines(analysis)])
end
function prediction_lines(analysis::LeagueAnalysis)
    lines = ["round,home,away,home_score,away_score,result," * join(PREDICTION_MODELS, ',')]
    for prediction in all_predictions(analysis.rounds)
        game = prediction.game
        result = result_twice(game) == 2 ? "H" : (result_twice(game) == 0 ? "A" : "D")
        fields = [string(game.round), team_code(analysis, game.home), team_code(analysis, game.away), string(game.home_score), string(game.away_score), result]
        append!(fields, fixed.(prediction.probabilities))
        push!(lines, join(fields, ','))
    end
    lines
end
function link_lines(analysis::LeagueAnalysis)
    lines = ["links"]
    for validation in analysis.rounds
        parts = ["round $(validation.number) train $(validation.training_count) base $(fixed(validation.base)) bt_home $(fixed(validation.fit.home_factor))"]
        for (model, name) in enumerate(LINK_MODELS)
            push!(parts, "$name $(fixed(validation.links[model][1])) $(fixed(validation.links[model][2]))")
        end
        push!(lines, join(parts, ' '))
    end
    lines
end
function score_lines(analysis::LeagueAnalysis)
    scores = analysis.scores
    lines = ["scores", "model log_loss brier skill accuracy"]
    for (model, name) in enumerate(PREDICTION_MODELS)
        push!(lines, "$name $(fixed(scores.losses[model])) $(fixed(scores.briers[model])) $(fixed(scores.skills[model])) $(fraction_with_real(scores.accuracies[model]))")
    end
    for (label, ranking) in [("ranking_log_loss", scores.loss_ranking), ("ranking_brier", scores.brier_ranking), ("ranking_accuracy", scores.accuracy_ranking)]
        push!(lines, label * " " * join(PREDICTION_MODELS[ranking], ' '))
    end
    lines
end
function paired_lines(analysis::LeagueAnalysis)
    reference = analysis.scores.loss_ranking[1]
    predictions = all_predictions(analysis.rounds)
    count = length(predictions)
    lines = ["paired_log_loss reference $(PREDICTION_MODELS[reference])"]
    for (model, name) in enumerate(PREDICTION_MODELS)
        model == reference && continue
        deltas = [item.losses[model] - item.losses[reference] for item in predictions]
        average = mean_values(deltas)
        squares = sequential_sum((delta - average) * (delta - average) for delta in deltas)
        spread = sqrt(squares / (count - 1))
        statistic = average / (spread / sqrt(count))
        push!(lines, "$name mean_diff $(fixed(average)) sd $(fixed(spread)) t $(fixed(statistic, 2))")
    end
    lines
end
function margin_lines(analysis::LeagueAnalysis)
    errors = [prediction.margin_error for prediction in all_predictions(analysis.rounds)]
    absolute = mean_values(abs.(errors))
    squared = sqrt(mean_values([error * error for error in errors]))
    bias = mean_values(errors)
    ["massey_margin mae $(fixed(absolute)) rmse $(fixed(squared)) bias $(fixed(bias))"]
end
function round_loss_lines(analysis::LeagueAnalysis)
    lines = ["round_log_loss", "round " * join(PREDICTION_MODELS, ' ')]
    for validation in analysis.rounds
        losses = [fixed(sequential_sum(item.losses[model] for item in validation.predictions) / length(validation.predictions)) for model in 1:8]
        push!(lines, "$(validation.number) " * join(losses, ' '))
    end
    lines
end
function calibration_lines(analysis::LeagueAnalysis)
    bins = analysis.settings.calibration_bins
    lines = ["calibration bins $bins"]
    for (model, name) in enumerate(PREDICTION_MODELS)
        groups = [Prediction[] for _ in 1:bins]
        for prediction in all_predictions(analysis.rounds)
            bin = min(floor(Int, bins * prediction.probabilities[model]) + 1, bins)
            push!(groups[bin], prediction)
        end
        for (number, group) in enumerate(groups)
            if isempty(group)
                push!(lines, "$name bin $number count 0 predicted - observed -")
                continue
            end
            predicted = sequential_sum(item.probabilities[model] for item in group) / length(group)
            observed = sum(result_twice(item.game) for item in group) // (2 * length(group))
            push!(lines, "$name bin $number count $(length(group)) predicted $(fixed(predicted)) observed $(fraction_text(observed))")
        end
    end
    lines
end
function grid_lines(analysis::LeagueAnalysis)
    settings = analysis.settings
    lines = ["elo_grid", "k " * join(("h$home" for home in settings.grid_home), ' ')]
    best = nothing
    for k in settings.grid_k
        row = [string(k)]
        for home in settings.grid_home
            run = run_elo(length(analysis.teams), analysis.matches, k, home, settings.elo_initial)
            losses = [log_loss(run.expected[index], result_twice(game)) for (index, game) in enumerate(analysis.matches) if game.round >= settings.holdout_round]
            loss = mean_values(losses)
            push!(row, fixed(loss))
            if isnothing(best) || decimal_value(loss, 4) < decimal_value(best[3], 4)
                best = (k, home, loss)
            end
        end
        push!(lines, join(row, ' '))
    end
    push!(lines, "best k $(best[1]) home $(best[2]) log_loss $(fixed(best[3]))")
    lines
end
function projection_tau(analysis::LeagueAnalysis)
    projected = [-rank // 1 for rank in analysis.projection.ranks]
    final = [-position // 1 for position in analysis.final_table.positions]
    kendall_tau(projected, final)
end
function evaluation_lines(analysis::LeagueAnalysis)
    join_parts([["holdout rounds $(analysis.settings.holdout_round)-$(final_round(analysis)) matches $(length(all_predictions(analysis.rounds)))"], link_lines(analysis), score_lines(analysis), paired_lines(analysis),
        margin_lines(analysis), round_loss_lines(analysis), calibration_lines(analysis), grid_lines(analysis), ["projection simulations $(analysis.settings.simulations) kendall $(fraction_with_real(projection_tau(analysis)))"]])
end
function projection_lines(analysis::LeagueAnalysis)
    projection = analysis.projection
    simulations = analysis.settings.simulations
    lines = [PROJECTION_HEADER]
    for (rank, team) in enumerate(projection.order)
        push!(lines, csv_line([rank, team_code(analysis, team), projection.current.records[team].points, projection.current.positions[team], fixed(opponent_strength(projection, team), 2),
            fixed(projection.total_points[team] // simulations), fixed(projection.titles[team] // simulations), fixed(projection.tops[team] // simulations), fixed(projection.bottoms[team] // simulations),
            analysis.final_table.records[team].points, analysis.final_table.positions[team]]))
    end
    lines
end
function output_files(analysis::LeagueAnalysis)
    [("standings.csv", standings_lines(analysis)), ("ratings.csv", ratings_lines(analysis)), ("history.csv", history_lines(analysis)), ("season.txt", season_lines(analysis)),
        ("predictions.csv", prediction_lines(analysis)), ("evaluation.txt", evaluation_lines(analysis)), ("projection.csv", projection_lines(analysis))]
end
function main()
    teams, matches, settings = load_season()
    analysis = LeagueAnalysis(teams, matches, settings)
    mkpath("output")
    for (name, lines) in output_files(analysis)
        write_lines(joinpath("output", name), lines)
    end
end

main()
