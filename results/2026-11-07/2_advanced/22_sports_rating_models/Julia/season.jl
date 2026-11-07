struct Team
    code::String
    name::String
end
struct Match
    round::Int
    home::Int
    away::Int
    home_score::Int
    away_score::Int
    file_order::Int
end
margin(game::Match) = game.home_score - game.away_score
result_twice(game::Match) = game.home_score > game.away_score ? 2 : (game.home_score == game.away_score ? 1 : 0)
match_result(game::Match) = result_twice(game) // 2
result_value(game::Match) = result_twice(game) / 2
struct Settings
    win_points::Int
    draw_points::Int
    form_length::Int
    close_margin::Int
    exponent::Float64
    elo_k::Int
    elo_home::Int
    elo_initial::Int
    grid_k::Vector{Int}
    grid_home::Vector{Int}
    bt_iterations::Int
    od_iterations::Int
    link_iterations::Int
    holdout_round::Int
    upsets::Int
    calibration_bins::Int
    simulations::Int
    seed::Int
    top_positions::Int
    bottom_positions::Int
end
matches_before(matches::Vector{Match}, round::Int) = filter(game -> game.round < round, matches)
function load_season()
    teams = Team[]
    for line in readlines("input/teams.csv")[2:end]
        code, name = split(line, ',')
        push!(teams, Team(code, name))
    end
    indices = Dict(team.code => index for (index, team) in enumerate(teams))
    matches = Match[]
    for (index, line) in enumerate(readlines("input/matches.csv")[2:end])
        words = split(line, ',')
        push!(matches, Match(parse(Int, words[1]), indices[words[2]], indices[words[3]], parse(Int, words[4]), parse(Int, words[5]), index))
    end
    sort!(matches; by=game -> (game.round, game.file_order))
    values = Dict{String,Vector{String}}()
    for line in readlines("input/params.txt")
        words = String.(split(line, ' '))
        values[words[1]] = words[2:end]
    end
    integer(key) = parse(Int, values[key][1])
    settings = Settings(integer("WIN_POINTS"), integer("DRAW_POINTS"), integer("FORM_LENGTH"), integer("CLOSE_MARGIN"), parse(Float64, values["PYTHAGOREAN_EXPONENT"][1]),
        integer("ELO_K"), integer("ELO_HOME"), integer("ELO_INITIAL"), parse.(Int, values["ELO_GRID_K"]), parse.(Int, values["ELO_GRID_HOME"]),
        integer("BT_ITERATIONS"), integer("OD_ITERATIONS"), integer("LINK_ITERATIONS"), integer("HOLDOUT_ROUND"), integer("UPSETS"), integer("CALIBRATION_BINS"),
        integer("SIMULATIONS"), integer("SIM_SEED"), integer("TOP_POSITIONS"), integer("BOTTOM_POSITIONS"))
    (teams, matches, settings)
end
