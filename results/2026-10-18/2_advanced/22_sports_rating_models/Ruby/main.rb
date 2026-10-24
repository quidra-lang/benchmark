# frozen_string_literal: true

require_relative 'season'
require_relative 'elo'
require_relative 'linear_models'
require_relative 'iterative_models'
require_relative 'evaluation'
require_relative 'report'

class SportsRatings
  RATING_MODELS = %i[elo colley massey bt od winpct].freeze
  COMPARISON_MODELS = %i[standings elo colley massey bt od winpct rpi pythag].freeze
  PREDICTION_MODELS = %i[base elo colley massey bt od winpct ensemble].freeze
  LINK_MODELS = %i[colley massey od winpct].freeze
  PRECISIONS = { elo: 2, colley: 4, massey: 4, bt: 4, od: 2 }.freeze
  RESULT_LETTERS = { 1 => 'W', 0 => 'D', -1 => 'L' }.freeze
  Record = Struct.new(:played, :won, :drawn, :lost, :scored, :conceded, :diff, :points)
  Standing = Data.define(:records, :head_to_head, :order, :positions, :groups)
  Progress = Data.define(:round, :elo, :changes, :ranks, :standing)
  Prediction = Data.define(:match, :probabilities, :margin_error)
  ValidationRound = Data.define(:round, :training, :models, :links, :base, :predictions)

  def initialize
    @teams, @matches, @params = Season.read
    @count = @teams.length
    @indices = (0...@count).to_a
    @round_count = @matches.last.round
    @by_round = @matches.group_by(&:round)
    @team_games = Array.new(@count) { [] }
    @matches.each do |match|
      @team_games[match.home] << match
      @team_games[match.away] << match
    end
  end

  def team_records(matches)
    records = Array.new(@count) { Record.new(0, 0, 0, 0, 0, 0, 0, 0) }
    matches.each do |match|
      [[match.home, match.home_score, match.away_score],
       [match.away, match.away_score, match.home_score]].each do |team, scored, conceded|
        record = records[team]
        record.played += 1
        record.scored += scored
        record.conceded += conceded
        case scored <=> conceded
        when 1 then record.won += 1
        when 0 then record.drawn += 1
        else record.lost += 1
        end
      end
    end
    records.each do |record|
      record.diff = record.scored - record.conceded
      record.points = @params[:win_points] * record.won + @params[:draw_points] * record.drawn
    end
    records
  end

  def positions(order)
    result = Array.new(@count)
    order.each_with_index { |team, index| result[team] = index + 1 }
    result
  end

  def standings(matches)
    records = team_records(matches)
    tied_matches = matches.select { |match| records[match.home].points == records[match.away].points }
    head = team_records(tied_matches)
    order = @indices.sort_by do |team|
      record = records[team]
      [-record.points, -head[team].points, -head[team].diff, -record.diff, -record.scored, @teams[team].id]
    end
    groups = order.group_by { |team| records[team].points }
    Standing.new(records, head, order, positions(order), groups)
  end

  def opponent(match, team)
    match.home == team ? match.away : match.home
  end

  def side_result(match, team)
    result = match.home_score <=> match.away_score
    match.home == team ? result : -result
  end

  def wdl(matches, team)
    counts = [0, 0, 0]
    matches.each { |match| counts[1 - side_result(match, team)] += 1 }
    counts.join('-')
  end

  def longest(team, accepted)
    best = [0, 0, 0]
    length = 0
    first = 0
    @team_games[team].each do |match|
      if accepted.include?(side_result(match, team))
        length += 1
        first = match.round if length == 1
        best = [length, first, match.round] if length > best[0]
      else
        length = 0
      end
    end
    best
  end

  def calculate_details
    @details = @indices.map do |team|
      games = @team_games[team]
      letters = games.map { |match| RESULT_LETTERS.fetch(side_result(match, team)) }
      streak = letters.reverse.take_while { |letter| letter == letters.last }.length
      home = games.select { |match| match.home == team }
      away = games.select { |match| match.away == team }
      close = games.select { |match| (match.home_score - match.away_score).abs <= @params[:close_margin] }
      { home: wdl(home, team), away: wdl(away, team), close: wdl(close, team),
        form: letters.last(@params[:form_length]).join, streak: "#{letters.last}#{streak}",
        longest_win: longest(team, [1]), longest_unbeaten: longest(team, [0, 1]) }
    end
  end

  def fit_models(matches)
    records = team_records(matches)
    elo = Elo.fit(@count, matches, @params[:elo_k], @params[:elo_home], @params[:elo_initial])
    colley = LinearModels.colley(@count, matches)
    massey, advantage = LinearModels.massey(@count, matches)
    bt, theta = IterativeModels.bradley_terry(@count, matches, @params[:bt_iterations])
    offense, defense, od = IterativeModels.offense_defense(@count, matches, @params[:od_iterations])
    winpct = records.map { |record| Rational(2 * record.won + record.drawn, 2 * record.played) }
    { elo: elo.ratings, elo_fit: elo, colley: colley, massey: massey, mu: advantage,
      bt: bt, theta: theta, offense: offense, defense: defense, od: od, winpct: winpct }
  end

  def opponent_means(values)
    @indices.map do |team|
      total = Rational(0)
      @team_games[team].each { |match| total += values[opponent(match, team)] }
      total / @team_games[team].length
    end
  end

  def calculate_indicators
    @sos = opponent_means(@models[:winpct])
    @sos2 = opponent_means(@sos)
    @rpi = @indices.map { |team| (@models[:winpct][team] + 2 * @sos[team] + @sos2[team]) / 4 }
    @pythag = @final.records.map do |record|
      1.0 / (1.0 + (record.conceded.to_f / record.scored)**@params[:pythagorean_exponent])
    end
    @luck = @indices.map { |team| @models[:winpct][team].to_f - @pythag[team] }
  end

  def ranks(values)
    values.map { |value| values.count { |other| other > value } + 1 }
  end

  def calculate_comparisons
    @comparisons = { standings: @final.positions.map { |position| -position },
                     winpct: @models[:winpct], rpi: @rpi,
                     pythag: @pythag.map { |value| Report.decimal_value(value, 4) } }
    PRECISIONS.each do |model, digits|
      @comparisons[model] = @models[model].map { |value| Report.decimal_value(value, digits) }
    end
    @ranks = RATING_MODELS.to_h { |model| [model, ranks(@comparisons[model])] }
    @rank_totals = @indices.map { |team| RATING_MODELS.sum { |model| @ranks[model][team] } }
    @consensus_order = @indices.sort_by { |team| [@rank_totals[team], @teams[team].id] }
  end

  def calculate_history
    previous = Array.new(@count, @params[:elo_initial].to_f)
    @history = (1..@round_count).map do |round|
      ratings = @models[:elo_fit].rounds.fetch(round)
      changes = @indices.map { |team| ratings[team] - previous[team] }
      rounded = ratings.map { |value| Report.decimal_value(value, 2) }
      standing = standings(Season.before(@matches, round + 1))
      previous = ratings
      Progress.new(round, ratings, changes, ranks(rounded), standing)
    end
  end

  def calculate_correlations
    @kendall = COMPARISON_MODELS.to_h do |first|
      [first, COMPARISON_MODELS.map { |second| Evaluation.kendall(@comparisons[first], @comparisons[second]) }]
    end
    @spearman = COMPARISON_MODELS.to_h do |first|
      [first, COMPARISON_MODELS.map { |second| Evaluation.spearman(@comparisons[first], @comparisons[second]) }]
    end
    pairs = []
    COMPARISON_MODELS.each_with_index do |first, index|
      (index + 1...COMPARISON_MODELS.length).each do |other|
        pairs << [first, COMPARISON_MODELS[other], @kendall[first][other]]
      end
    end
    @most_similar = pairs.each_with_index.min_by { |pair, index| [-pair[2], index] }.first
    @least_similar = pairs.each_with_index.min_by { |pair, index| [pair[2], index] }.first
  end

  def feature(model, match, values)
    home = values[model][match.home]
    away = values[model][match.away]
    return Math.log(home) - Math.log(away) if model == :od
    return home.to_f - away.to_f if model == :winpct

    home - away
  end

  def ordered_sum(values)
    total = 0.0
    values.each { |value| total += value }
    total
  end

  def mean(values)
    ordered_sum(values) / values.length
  end

  def validate_rounds
    @predictions = []
    @validation_rounds = (@params[:holdout_round]..@round_count).map do |round|
      training = Season.before(@matches, round)
      models = fit_models(training)
      results = training.map(&:result)
      links = LINK_MODELS.to_h do |model|
        features = training.map { |match| feature(model, match, models) }
        [model, Evaluation.fit_link(features, results, @params[:link_iterations])]
      end
      base = mean(results.map(&:to_f))
      predictions = @by_round.fetch(round).map do |match|
        probabilities = { base: base,
                          elo: Elo.expected(models[:elo][match.home], models[:elo][match.away], @params[:elo_home]) }
        LINK_MODELS.each do |model|
          alpha, beta = links[model]
          probabilities[model] = Evaluation.sigma(alpha + beta * feature(model, match, models))
        end
        home_strength = models[:theta] * models[:bt][match.home]
        probabilities[:bt] = home_strength / (home_strength + models[:bt][match.away])
        total = 0.0
        RATING_MODELS.each { |model| total += probabilities[model] }
        probabilities[:ensemble] = total / 6
        margin = models[:massey][match.home] - models[:massey][match.away] + models[:mu]
        Prediction.new(match, probabilities, (match.home_score - match.away_score) - margin)
      end
      @predictions.concat(predictions)
      ValidationRound.new(round, training.length, models, links, base, predictions)
    end
  end

  def evaluate_predictions
    @scores = PREDICTION_MODELS.to_h do |model|
      losses = []
      briers = []
      correct = Rational(0)
      @predictions.each do |prediction|
        probability = prediction.probabilities[model]
        result = prediction.match.result
        losses << Evaluation.log_loss(probability, result)
        briers << Evaluation.brier(probability, result)
        correct += Evaluation.correctness(probability, result)
      end
      [model, { losses: losses, log_loss: mean(losses), brier: mean(briers),
                accuracy: correct / @predictions.length }]
    end
    @scores.each_value { |score| score[:skill] = 1.0 - score[:brier] / @scores[:base][:brier] }
    @rankings = {}
    %i[log_loss brier].each do |metric|
      @rankings[metric] = PREDICTION_MODELS.each_with_index.sort_by do |model, index|
        [Report.decimal_value(@scores[model][metric], 4), index]
      end.map(&:first)
    end
    @rankings[:accuracy] = PREDICTION_MODELS.each_with_index.sort_by do |model, index|
      [-@scores[model][:accuracy], index]
    end.map(&:first)
    @reference = @rankings[:log_loss].first
    @paired = {}
    PREDICTION_MODELS.each do |model|
      next if model == @reference

      differences = @scores[model][:losses].each_with_index.map do |loss, index|
        loss - @scores[@reference][:losses][index]
      end
      average = mean(differences)
      squares = differences.map { |difference| (difference - average) * (difference - average) }
      deviation = Math.sqrt(ordered_sum(squares) / (@predictions.length - 1))
      statistic = average / (deviation / Math.sqrt(@predictions.length))
      @paired[model] = [average, deviation, statistic]
    end
    errors = @predictions.map(&:margin_error)
    @margin_errors = [mean(errors.map(&:abs)), Math.sqrt(mean(errors.map { |error| error * error })), mean(errors)]
    calculate_calibration
  end

  def calculate_calibration
    count = @params[:calibration_bins]
    @calibration = PREDICTION_MODELS.to_h do |model|
      bins = Array.new(count) { [] }
      @predictions.each do |prediction|
        index = [(count * prediction.probabilities[model]).floor, count - 1].min
        bins[index] << prediction
      end
      values = bins.map do |bin|
        if bin.empty?
          [0, nil, nil]
        else
          observed = Rational(0)
          bin.each { |prediction| observed += prediction.match.result }
          [bin.length, mean(bin.map { |prediction| prediction.probabilities[model] }), observed / bin.length]
        end
      end
      [model, values]
    end
  end

  def search_elo_grid
    candidates = []
    @grid = @params[:elo_grid_k].map do |coefficient|
      losses = @params[:elo_grid_home].map do |advantage|
        fitted = Elo.fit(@count, @matches, coefficient, advantage, @params[:elo_initial])
        loss_values = []
        @matches.each_with_index do |match, index|
          next if match.round < @params[:holdout_round]

          loss_values << Evaluation.log_loss(fitted.expected[index], match.result)
        end
        loss = mean(loss_values)
        candidates << [coefficient, advantage, loss]
        loss
      end
      [coefficient, losses]
    end
    @best_grid = candidates.min_by { |coefficient, advantage, loss| [Report.decimal_value(loss, 4), coefficient, advantage] }
  end

  def simulate
    current = standings(Season.before(@matches, @params[:holdout_round]))
    ratings = @validation_rounds.first.models[:elo]
    remaining = @predictions.map(&:match)
    probabilities = remaining.map { |match| Elo.expected(ratings[match.home], ratings[match.away], @params[:elo_home]) }
    totals = Array.new(@count, 0)
    titles = Array.new(@count, 0)
    top = Array.new(@count, 0)
    bottom = Array.new(@count, 0)
    seed = @params[:sim_seed]
    @params[:simulations].times do
      points = current.records.map(&:points)
      remaining.each_with_index do |match, index|
        seed = (48_271 * seed) % 2_147_483_647
        winner = seed.to_f / 2_147_483_647 < probabilities[index] ? match.home : match.away
        points[winner] += @params[:win_points]
      end
      order = @indices.sort_by { |team| [-points[team], current.positions[team]] }
      @indices.each { |team| totals[team] += points[team] }
      order.each_with_index do |team, index|
        place = index + 1
        titles[team] += 1 if place == 1
        top[team] += 1 if place <= @params[:top_positions]
        bottom[team] += 1 if place >= @count - @params[:bottom_positions] + 1
      end
    end
    order = @indices.sort_by { |team| [-totals[team], current.positions[team]] }
    projected = positions(order)
    strength = @indices.map do |team|
      games = @team_games[team].select { |match| match.round >= @params[:holdout_round] }
      mean(games.map { |match| ratings[opponent(match, team)] })
    end
    @projection = { current: current, totals: totals, titles: titles, top: top, bottom: bottom,
                    order: order, positions: projected, strength: strength }
    @agreement = Evaluation.kendall(projected.map { |position| -position }, @comparisons[:standings])
  end

  def team_ids(teams)
    teams.map { |team| @teams[team].id }.join(' ')
  end

  def real_values(values, digits = 4)
    values.map { |value| Report.real(value, digits) }.join(' ')
  end

  def separate(parts)
    parts.each_with_index.flat_map { |part, index| index.zero? ? part : [''] + part }
  end

  def standings_lines
    lines = ['pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck']
    @final.order.each do |team|
      detail = @details[team]
      values = [@final.positions[team], @teams[team].id, @teams[team].name] + @final.records[team].to_a
      values.concat([detail[:home], detail[:away], detail[:form], detail[:streak], detail[:close],
                     detail[:longest_win][0], detail[:longest_unbeaten][0], Report.fraction(@models[:winpct][team])])
      values.concat([@sos[team], @sos2[team], @rpi[team], @pythag[team], @luck[team]].map { |value| Report.real(value) })
      lines << values.join(',')
    end
    lines
  end

  def ratings_lines
    lines = ['team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank']
    @consensus_order.each do |team|
      values = [@teams[team].id]
      %i[elo colley massey bt].each do |model|
        values.concat([Report.real(@models[model][team], PRECISIONS[model]), @ranks[model][team]])
      end
      ranks = RATING_MODELS.map { |model| @ranks[model][team] }
      values.concat([Report.real(@models[:offense][team], 2), Report.real(@models[:defense][team]),
                     Report.real(@models[:od][team], 2), @ranks[:od][team], Report.real(@models[:winpct][team]),
                     @ranks[:winpct][team], @rank_totals[team], ranks.min, ranks.max])
      lines << values.join(',')
    end
    lines
  end

  def history_lines
    lines = ['round,team,elo,change,elo_rank,points,position']
    @history.each do |entry|
      @indices.each do |team|
        lines << [entry.round, @teams[team].id, Report.real(entry.elo[team], 2),
                  Report.real(entry.changes[team], 2), entry.ranks[team],
                  entry.standing.records[team].points, entry.standing.positions[team]].join(',')
      end
    end
    lines
  end

  def upset_lines
    candidates = []
    @matches.each_with_index do |match, index|
      next if match.result == Rational(1, 2)

      probability = @models[:elo_fit].expected[index]
      probability = 1.0 - probability if match.result.zero?
      candidates << [match, index, probability]
    end
    candidates.sort_by! { |_, index, probability| [Report.decimal_value(probability, 4), index] }
    lines = ["upsets top #{@params[:upsets]}"]
    candidates.first(@params[:upsets]).each do |match, index, probability|
      home = match.result == 1
      winner = home ? match.home : match.away
      loser = home ? match.away : match.home
      scored = home ? match.home_score : match.away_score
      conceded = home ? match.away_score : match.home_score
      gain = Report.real(@models[:elo_fit].changes[index].abs, 2)
      lines << "round #{match.round} #{@teams[winner].id} beat #{@teams[loser].id} #{scored}-#{conceded} #{home ? 'home' : 'away'} expected #{Report.real(probability)} gain #{gain}"
    end
    lines
  end

  def tiebreak_lines
    lines = ['tiebreaks']
    @final.groups.each do |points, group|
      next if group.length < 2

      head_points = group.map { |team| @final.head_to_head[team].points }.join(' ')
      head_diff = group.map { |team| @final.head_to_head[team].diff }.join(' ')
      lines << "points #{points} order #{team_ids(group)} h2h_points #{head_points} h2h_diff #{head_diff}"
    end
    lines << 'none' if lines.length == 1
    lines
  end

  def leader_lines
    records = []
    previous = nil
    @history.each do |entry|
      leader = entry.standing.order.first
      if leader != previous
        records << "round #{entry.round} #{@teams[leader].id} points #{entry.standing.records[leader].points}"
      end
      previous = leader
    end
    ['leaders'] + records + ["lead_changes #{records.length - 1}"]
  end

  def streak_lines
    lines = []
    %i[longest_win longest_unbeaten].each do |kind|
      maximum = @details.map { |detail| detail[kind][0] }.max
      @indices.each do |team|
        length, first, last = @details[team][kind]
        next unless length == maximum

        lines << "#{kind}_streak #{@teams[team].id} length #{length} rounds #{first}-#{last}"
      end
    end
    lines
  end

  def crosstable_lines
    teams = @final.order.first(@params[:top_positions])
    lines = ["crosstable top #{@params[:top_positions]}", "team #{team_ids(teams)}"]
    teams.each do |team|
      entries = teams.map do |other|
        team == other ? '-' : wdl(@team_games[team].select { |match| opponent(match, team) == other }, team)
      end
      lines << "#{@teams[team].id} #{entries.join(' ')}"
    end
    lines
  end

  def trajectory_lines
    lines = ['trajectories']
    @indices.each do |team|
      peak = @history.min_by { |entry| [-Report.decimal_value(entry.elo[team], 2), entry.round] }
      low = @history.min_by { |entry| [Report.decimal_value(entry.elo[team], 2), entry.round] }
      best = @history.min_by { |entry| [entry.standing.positions[team], entry.round] }
      worst = @history.min_by { |entry| [-entry.standing.positions[team], entry.round] }
      lines << "#{@teams[team].id} elo_peak #{Report.real(peak.elo[team], 2)} round #{peak.round} elo_low #{Report.real(low.elo[team], 2)} round #{low.round} best_position #{best.standing.positions[team]} round #{best.round} worst_position #{worst.standing.positions[team]} round #{worst.round}"
    end
    lines
  end

  def correlation_lines(name, matrix)
    rows = COMPARISON_MODELS.map do |model|
      "#{model} #{matrix[model].map { |value| Report.fraction(value) }.join(' ')}"
    end
    [name, "model #{COMPARISON_MODELS.join(' ')}"] + rows
  end

  def season_lines
    won = @matches.count { |match| match.result == 1 }
    drawn = @matches.count { |match| match.result == Rational(1, 2) }
    rate = Rational(2 * won + drawn, 2 * @matches.length)
    summary = ["season teams #{@count} matches #{@matches.length} rounds #{@round_count}",
               "home won #{won} drawn #{drawn} lost #{@matches.length - won - drawn} rate #{Report.fraction(rate)} #{Report.real(rate)}",
               "massey_home_advantage #{Report.real(@models[:mu])}",
               "bt_home_factor #{Report.real(@models[:theta])}"]
    similarities = [[:most_similar, @most_similar], [:least_similar, @least_similar]].map do |name, pair|
      "#{name} #{pair[0]} #{pair[1]} tau #{Report.fraction(pair[2])} #{Report.real(pair[2])}"
    end
    separate([summary, upset_lines, tiebreak_lines, leader_lines, streak_lines, crosstable_lines,
              trajectory_lines, correlation_lines('kendall', @kendall),
              correlation_lines('spearman', @spearman), similarities])
  end

  def prediction_lines
    lines = ['round,home,away,home_score,away_score,result,base,elo,colley,massey,bt,od,winpct,ensemble']
    @predictions.each do |prediction|
      match = prediction.match
      result = match.result == 1 ? 'H' : (match.result.zero? ? 'A' : 'D')
      values = [match.round, @teams[match.home].id, @teams[match.away].id, match.home_score, match.away_score, result]
      values.concat(PREDICTION_MODELS.map { |model| Report.real(prediction.probabilities[model]) })
      lines << values.join(',')
    end
    lines
  end

  def evaluation_lines
    links = ['links']
    @validation_rounds.each do |entry|
      line = "round #{entry.round} train #{entry.training} base #{Report.real(entry.base)} bt_home #{Report.real(entry.models[:theta])}"
      LINK_MODELS.each { |model| line += " #{model} #{real_values(entry.links[model])}" }
      links << line
    end
    scores = ['scores', 'model log_loss brier skill accuracy']
    PREDICTION_MODELS.each do |model|
      score = @scores[model]
      scores << "#{model} #{real_values([score[:log_loss], score[:brier], score[:skill]])} #{Report.fraction(score[:accuracy])} #{Report.real(score[:accuracy])}"
    end
    %i[log_loss brier accuracy].each { |metric| scores << "ranking_#{metric} #{@rankings[metric].join(' ')}" }
    paired = ["paired_log_loss reference #{@reference}"]
    @paired.each do |model, values|
      paired << "#{model} mean_diff #{Report.real(values[0])} sd #{Report.real(values[1])} t #{Report.real(values[2], 2)}"
    end
    margin = ["massey_margin mae #{Report.real(@margin_errors[0])} rmse #{Report.real(@margin_errors[1])} bias #{Report.real(@margin_errors[2])}"]
    rounds = ['round_log_loss', "round #{PREDICTION_MODELS.join(' ')}"]
    @validation_rounds.each do |entry|
      losses = PREDICTION_MODELS.map do |model|
        mean(entry.predictions.map { |prediction| Evaluation.log_loss(prediction.probabilities[model], prediction.match.result) })
      end
      rounds << "#{entry.round} #{real_values(losses)}"
    end
    calibration = ["calibration bins #{@params[:calibration_bins]}"]
    PREDICTION_MODELS.each do |model|
      @calibration[model].each_with_index do |(count, predicted, observed), index|
        prediction_text = predicted.nil? ? '-' : Report.real(predicted)
        observed_text = observed.nil? ? '-' : Report.fraction(observed)
        calibration << "#{model} bin #{index + 1} count #{count} predicted #{prediction_text} observed #{observed_text}"
      end
    end
    grid = ['elo_grid', 'k ' + @params[:elo_grid_home].map { |home| "h#{home}" }.join(' ')]
    @grid.each { |coefficient, losses| grid << "#{coefficient} #{real_values(losses)}" }
    coefficient, advantage, loss = @best_grid
    grid << "best k #{coefficient} home #{advantage} log_loss #{Report.real(loss)}"
    agreement = ["projection simulations #{@params[:simulations]} kendall #{Report.fraction(@agreement)} #{Report.real(@agreement)}"]
    separate([["holdout rounds #{@params[:holdout_round]}-#{@round_count} matches #{@predictions.length}"],
              links, scores, paired, margin, rounds, calibration, grid, agreement])
  end

  def projection_lines
    lines = ['projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position']
    @projection[:order].each do |team|
      current = @projection[:current]
      values = [@projection[:positions][team], @teams[team].id, current.records[team].points,
                current.positions[team], Report.real(@projection[:strength][team], 2)]
      %i[totals titles top bottom].each do |kind|
        values << Report.real(Rational(@projection[kind][team], @params[:simulations]))
      end
      values.concat([@final.records[team].points, @final.positions[team]])
      lines << values.join(',')
    end
    lines
  end

  def run
    @final = standings(@matches)
    @models = fit_models(@matches)
    calculate_details
    calculate_indicators
    calculate_comparisons
    calculate_history
    calculate_correlations
    validate_rounds
    evaluate_predictions
    search_elo_grid
    simulate
    Report.write('standings.csv', standings_lines)
    Report.write('ratings.csv', ratings_lines)
    Report.write('history.csv', history_lines)
    Report.write('season.txt', season_lines)
    Report.write('predictions.csv', prediction_lines)
    Report.write('evaluation.txt', evaluation_lines)
    Report.write('projection.csv', projection_lines)
  end
end

SportsRatings.new.run if $PROGRAM_NAME == __FILE__
