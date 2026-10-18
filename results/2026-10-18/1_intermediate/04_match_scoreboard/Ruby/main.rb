class Invalid < StandardError
end

module Darts
  DATA = {}
  (1..20).each do |n|
    DATA["S#{n}"] = { value: n, double: false }
    DATA["D#{n}"] = { value: 2 * n, double: true }
    DATA["T#{n}"] = { value: 3 * n, double: false }
  end
  DATA["25"] = { value: 25, double: false }
  DATA["BULL"] = { value: 50, double: true }
  DATA["MISS"] = { value: 0, double: false }
  A = %w[S T D].flat_map { |prefix| 20.downto(1).map { |n| "#{prefix}#{n}" } } + %w[25 BULL]
  B = 20.downto(1).map { |n| "D#{n}" } + ["BULL"]
  CACHE = {}

  def self.checkout(score, maximum = 3)
    key = [score, maximum]
    return CACHE[key] if CACHE.key?(key)
    (1..maximum).each do |count|
      A.repeated_permutation(count - 1) do |prefix|
        wanted = score - prefix.sum { |dart| DATA[dart][:value] }
        last = B.find { |dart| DATA[dart][:value] == wanted }
        if last
          CACHE[key] = prefix + [last]
          return CACHE[key]
        end
      end
    end
    CACHE[key] = nil
  end
end

class Game
  CHOICES = {
    "TENNIS" => {
      "SETS" => %w[3 5], "DEUCE" => %w[AD NOAD],
      "FINAL" => %w[TB7 TB10 ADV SUPER], "FIRST" => %w[A B]
    },
    "TABLETENNIS" => { "GAMES" => %w[5 7], "FIRST" => %w[A B] },
    "BADMINTON" => { "FIRST" => %w[A B] },
    "VOLLEYBALL" => { "FIRST" => %w[A B] },
    "DARTS" => { "START" => %w[301 501 701], "SETS" => %w[1 2 3 4 5],
                 "LEGS" => %w[1 2 3 4 5], "FIRST" => %w[A B] },
    "BOWLING" => {}
  }.freeze
  DEFAULTS = {
    "TENNIS" => { "SETS" => "3", "DEUCE" => "AD", "FINAL" => "TB7", "FIRST" => "A" },
    "TABLETENNIS" => { "GAMES" => "5", "FIRST" => "A" },
    "BADMINTON" => { "FIRST" => "A" }, "VOLLEYBALL" => { "FIRST" => "A" },
    "DARTS" => { "START" => "501", "SETS" => "1", "LEGS" => "1", "FIRST" => "A" },
    "BOWLING" => {}
  }.freeze
  attr_reader :id, :sport, :names, :state

  def initialize(args)
    @id, @sport = args[0, 2]
    @names = @sport == "BOWLING" ? [args[2]] : args[2, 2]
    @lineups = @sport == "VOLLEYBALL" ? args[4, 2].map { |lineup| lineup.split(",").map(&:to_i) } : [[], []]
    option_start = @sport == "BOWLING" ? 3 : @sport == "VOLLEYBALL" ? 6 : 4
    @options = DEFAULTS[@sport].dup
    seen = {}
    args.drop(option_start).each do |option|
      parts = option.split("=", -1)
      if parts.length != 2 || !CHOICES[@sport].key?(parts[0]) ||
         !CHOICES[@sport][parts[0]].include?(parts[1]) || seen[parts[0]]
        raise Invalid, "invalid option"
      end
      seen[parts[0]] = true
      @options[parts[0]] = parts[1]
    end
    @first = @options["FIRST"] == "B" ? 1 : 0
    start = @options.fetch("START", "501").to_i
    @state = {
      done: false, winner: -1, sets: [0, 0], legs: [0, 0], points: [0, 0], games: [0, 0],
      finished: [], game_server: @first, server: @first,
      lineups: @lineups.map(&:dup), subs: [0, 0], timeouts: [0, 0],
      rally: Array.new(2) do
        { points: 0, served: 0, serve_won: 0, run: 0, current: 0,
          holds: 0, service_games: 0, breaks: 0, opportunities: 0, conversions: 0 }
      end,
      frames: Array.new(10) { [] }, marks: Array.new(10) { [] }, frame: 0, standing: 10,
      remaining: [start, start], player: @first, leg_number: 0,
      turn: [], turn_start: start, turn_score: 0,
      darts: Array.new(2) do
        { darts: 0, points: 0, busts: 0, high: 0, tons: 0, maximums: 0, attempts: 0, hits: 0 }
      end
    }
    @initial = copy(@state)
    @history = []
  end

  def copy(state)
    Marshal.load(Marshal.dump(state))
  end

  def pair(values, reverse = false)
    (reverse ? values.reverse : values).join("-")
  end

  def rally_sport?
    %w[TENNIS TABLETENNIS BADMINTON VOLLEYBALL].include?(@sport)
  end

  def final_set?(s)
    target = @options["SETS"].to_i.div(2)
    s[:sets][0] == target && s[:sets][1] == target
  end

  def tennis_kind(s)
    return :super if final_set?(s) && @options["FINAL"] == "SUPER"
    if s[:games] == [6, 6] && !(final_set?(s) && @options["FINAL"] == "ADV")
      return :tie
    end
    :normal
  end

  def server(s)
    if @sport == "TENNIS"
      return s[:game_server] if tennis_kind(s) == :normal
      k = s[:points].sum + 1
      s[:game_server] ^ (k.div(2) % 2)
    elsif @sport == "TABLETENNIS"
      first = @first ^ (s[:finished].length % 2)
      t = s[:points].sum
      first ^ (t < 20 ? t.div(2) % 2 : t % 2)
    else
      s[:server]
    end
  end

  def normal_game_wins?(points, winner)
    points[winner] >= 4 && (@options["DEUCE"] == "NOAD" || points[winner] - points[1 - winner] >= 2)
  end

  def finish_rally_unit(s, winner, record, target)
    s[:finished] << record
    s[:sets][winner] += 1
    if s[:sets][winner] == target
      s[:done] = true
      s[:winner] = winner
    else
      s[:points] = [0, 0]
      s[:games] = [0, 0]
      if @sport == "VOLLEYBALL"
        s[:lineups] = @lineups.map(&:dup)
        s[:subs] = [0, 0]
        s[:timeouts] = [0, 0]
        s[:server] = @first ^ (s[:finished].length % 2)
      end
    end
  end

  def point(s, winner)
    serving = server(s)
    s[:rally][winner][:points] += 1
    s[:rally][serving][:served] += 1
    s[:rally][serving][:serve_won] += 1 if winner == serving
    s[:rally][winner][:current] += 1
    s[:rally][winner][:run] = [s[:rally][winner][:run], s[:rally][winner][:current]].max
    s[:rally][1 - winner][:current] = 0
    if @sport == "TENNIS"
      kind = tennis_kind(s)
      if kind == :normal
        receiver = 1 - serving
        hypothetical = s[:points].dup
        hypothetical[receiver] += 1
        if normal_game_wins?(hypothetical, receiver)
          s[:rally][receiver][:opportunities] += 1
          s[:rally][receiver][:conversions] += 1 if winner == receiver
        end
      end
      s[:points][winner] += 1
      target_sets = @options["SETS"].to_i.div(2) + 1
      if kind == :normal && normal_game_wins?(s[:points], winner)
        s[:rally][serving][:service_games] += 1
        if winner == serving
          s[:rally][serving][:holds] += 1
        else
          s[:rally][winner][:breaks] += 1
        end
        s[:games][winner] += 1
        s[:points] = [0, 0]
        s[:game_server] ^= 1
        if s[:games][winner] >= 6 && s[:games][winner] - s[:games][1 - winner] >= 2
          finish_rally_unit(s, winner, { values: s[:games].dup, tie: -1, super: false }, target_sets)
        end
      elsif kind != :normal
        target = kind == :super || (final_set?(s) && @options["FINAL"] == "TB10") ? 10 : 7
        if s[:points][winner] >= target && s[:points][winner] - s[:points][1 - winner] >= 2
          record = if kind == :super
                     { values: s[:points].dup, tie: -1, super: true }
                   else
                     { values: s[:games].each_with_index.map { |value, i| value + (i == winner ? 1 : 0) },
                       tie: s[:points][1 - winner], super: false }
                   end
          s[:game_server] ^= 1
          finish_rally_unit(s, winner, record, target_sets)
        end
      end
    else
      s[:points][winner] += 1
      if @sport == "BADMINTON"
        s[:server] = winner
      elsif @sport == "VOLLEYBALL" && winner != s[:server]
        s[:server] = winner
        s[:lineups][winner].rotate!
      end
      target = if @sport == "TABLETENNIS"
                 11
               elsif @sport == "BADMINTON"
                 21
               else
                 s[:finished].length == 4 ? 15 : 25
               end
      won = (s[:points][winner] >= target && s[:points][winner] - s[:points][1 - winner] >= 2) ||
            (@sport == "BADMINTON" && s[:points][winner] == 30)
      if won
        needed = @sport == "TABLETENNIS" ? @options["GAMES"].to_i.div(2) + 1 : @sport == "BADMINTON" ? 2 : 3
        finish_rally_unit(s, winner, { values: s[:points].dup, tie: -1, super: false }, needed)
      end
    end
  end

  def standing(s)
    s[:frame] == 9 && s[:standing].zero? ? 10 : s[:standing]
  end

  def roll(s, pins)
    pins_standing = standing(s)
    raise Invalid, "too many pins" if pins > pins_standing
    frame = s[:frames][s[:frame]]
    fresh_rack = frame.empty? || (s[:frame] == 9 && s[:standing].zero?)
    mark = if fresh_rack && pins == 10
             "X"
           elsif pins == pins_standing
             "/"
           elsif pins.zero?
             "-"
           else
             pins.to_s
           end
    frame << pins
    s[:marks][s[:frame]] << mark
    s[:standing] = pins_standing - pins
    if s[:frame] < 9
      if (pins == 10 && frame.length == 1) || frame.length == 2
        s[:frame] += 1
        s[:standing] = 10
      end
    elsif frame.length == 3 || (frame.length == 2 && frame[0] != 10 && frame[0] + frame[1] < 10)
      s[:done] = true
    end
  end

  def frame_scores(s)
    s[:frames].each_with_index.map do |frame, i|
      if i == 9
        s[:done] ? frame.sum : nil
      else
        later = s[:frames].drop(i + 1).flatten
        if frame[0] == 10
          later.length >= 2 ? 10 + later[0] + later[1] : nil
        elsif frame.length < 2
          nil
        elsif frame.sum == 10
          later.empty? ? nil : 10 + later[0]
        else
          frame.sum
        end
      end
    end
  end

  def maximum(s)
    hypothetical = copy(s)
    roll(hypothetical, standing(hypothetical)) until hypothetical[:done]
    frame_scores(hypothetical).compact.sum
  end

  def completed_turn(s, player)
    stats = s[:darts][player]
    stats[:high] = [stats[:high], s[:turn_score]].max
    stats[:tons] += 1 if s[:turn_score] >= 100
    stats[:maximums] += 1 if s[:turn_score] == 180
  end

  def next_turn(s)
    s[:player] = 1 - s[:player]
    s[:turn] = []
    s[:turn_score] = 0
    s[:turn_start] = s[:remaining][s[:player]]
  end

  def throw_dart(s, notation)
    dart = Darts::DATA[notation]
    raise Invalid, "invalid dart" unless dart
    player = s[:player]
    stats = s[:darts][player]
    before = s[:remaining][player]
    stats[:darts] += 1
    stats[:attempts] += 1 if before == 50 || (before <= 40 && before.even?)
    s[:turn] << notation
    s[:turn_score] += dart[:value]
    stats[:points] += dart[:value]
    remaining = before - dart[:value]
    if remaining.negative? || remaining == 1 || (remaining.zero? && !dart[:double])
      stats[:busts] += 1
      stats[:points] -= s[:turn_score]
      s[:remaining][player] = s[:turn_start]
      next_turn(s)
    else
      s[:remaining][player] = remaining
      if remaining.zero?
        stats[:hits] += 1
        completed_turn(s, player)
        s[:legs][player] += 1
        if s[:legs][player] == @options["LEGS"].to_i
          s[:sets][player] += 1
          s[:finished] << { values: s[:legs].dup, tie: -1, super: false }
          if s[:sets][player] == @options["SETS"].to_i
            s[:done] = true
            s[:winner] = player
            return
          end
          s[:legs] = [0, 0]
        end
        s[:leg_number] += 1
        start = @options["START"].to_i
        s[:remaining] = [start, start]
        s[:player] = @first ^ (s[:leg_number] % 2)
        s[:turn] = []
        s[:turn_score] = 0
        s[:turn_start] = start
      elsif s[:turn].length == 3
        completed_turn(s, player)
        next_turn(s)
      end
    end
  end

  def apply(name, args)
    case name
    when "POINT"
      point(@state, args[0] == "A" ? 0 : 1)
    when "ROLL"
      roll(@state, args[0].to_i)
    when "THROW"
      throw_dart(@state, args[0])
    else
      side = args[0] == "A" ? 0 : 1
      if name == "SUB"
        lineup = @state[:lineups][side]
        position = lineup.index(args[1].to_i)
        raise Invalid, "player not on court" unless position
        raise Invalid, "player already on court" if lineup.include?(args[2].to_i)
        raise Invalid, "no substitutions left" if @state[:subs][side] >= 6
        lineup[position] = args[2].to_i
        @state[:subs][side] += 1
      else
        raise Invalid, "no timeouts left" if @state[:timeouts][side] >= 2
        @state[:timeouts][side] += 1
      end
    end
  end

  def event(name, args)
    allowed = case name
              when "POINT" then rally_sport?
              when "ROLL" then @sport == "BOWLING"
              when "THROW" then @sport == "DARTS"
              else @sport == "VOLLEYBALL"
              end
    raise Invalid, "wrong event" unless allowed
    events = if name == "POINT"
               args[0].chars.map { |value| [value] }
             elsif %w[ROLL THROW].include?(name)
               args.map { |value| [value] }
             else
               [args]
             end
    events.each do |values|
      raise Invalid, "match over" if @state[:done]
      apply(name, values)
      @history << { name: name, args: values }
    end
  end

  def undo
    raise Invalid, "nothing to undo" if @history.empty?
    @history.pop
    @state = copy(@initial)
    @history.each { |event| apply(event[:name], event[:args]) }
  end

  def score_record(record, reverse = false)
    value = pair(record[:values], reverse)
    record[:super] ? "[#{value}]" : value + (record[:tie] >= 0 ? "(#{record[:tie]})" : "")
  end

  def situation(side)
    s = @state
    hypothetical = copy(s)
    serving = server(s)
    normal = @sport == "TENNIS" && tennis_kind(s) == :normal
    point(hypothetical, side)
    return "match point" if hypothetical[:done]
    if hypothetical[:finished].length > s[:finished].length
      return %w[TENNIS VOLLEYBALL].include?(@sport) ? "set point" : "game point"
    end
    return side == serving ? "game point" : "break point" if normal && hypothetical[:game_server] != s[:game_server]
    nil
  end

  def score
    s = @state
    if @sport == "BOWLING"
      scores = frame_scores(s)
      total = 0
      items = []
      s[:frames].each_with_index do |frame, i|
        break if frame.empty?
        value = s[:marks][i].join
        unless scores[i].nil?
          total += scores[i]
          value += "(#{total})"
        end
        items << value
      end
      return "#{@id}: #{@names[0]}" + (items.empty? ? "" : " " + items.join(" "))
    end
    serving = @sport == "DARTS" ? s[:player] : server(s)
    displays = @names.each_with_index.map { |name, i| name + (!s[:done] && i == serving ? "*" : "") }
    items = s[:finished].map { |record| score_record(record) }
    if @sport == "DARTS"
      items = ["sets", pair(s[:sets]), "legs", pair(s[:legs]), "score", pair(s[:remaining])]
      unless s[:done]
        items.concat(["turn", *s[:turn]]) unless s[:turn].empty?
        finish = Darts.checkout(s[:remaining][s[:player]], 3 - s[:turn].length)
        items.concat(["checkout", *finish]) if finish
      end
    elsif !s[:done]
      if @sport == "TENNIS"
        kind = tennis_kind(s)
        if kind == :super
          items << "[#{pair(s[:points])}]"
        else
          items << pair(s[:games])
          if kind == :tie
            items << pair(s[:points])
          elsif @options["DEUCE"] == "AD" && s[:points].all? { |value| value >= 3 }
            display = s[:points][0] == s[:points][1] ? "40-40" : s[:points][0] > s[:points][1] ? "AD-40" : "40-AD"
            items << display
          else
            items << s[:points].map { |value| %w[0 15 30 40][value] }.join("-")
          end
        end
      else
        items << pair(s[:points])
        items.concat(["server", s[:lineups][s[:server]][0].to_s]) if @sport == "VOLLEYBALL"
      end
      2.times do |side|
        status = situation(side)
        items << "(#{status} #{@names[side]})" if status
      end
    end
    "#{@id}: #{displays[0]} vs #{displays[1]} " + items.join(" ")
  end

  def stats
    s = @state
    if @sport == "BOWLING"
      marks = s[:marks].flatten
      open_frames = s[:frames].count { |frame| frame.length >= 2 && frame[0] != 10 && frame[0] + frame[1] < 10 }
      return ["#{@id} #{@names[0]}: strikes #{marks.count('X')} spares #{marks.count('/')} open #{open_frames} max #{maximum(s)}"]
    end
    @names.each_with_index.map do |name, i|
      result = "#{@id} #{name}: "
      if @sport == "DARTS"
        stats = s[:darts][i]
        average = stats[:darts].positive? ? (stats[:points] * 300).div(stats[:darts]) : 0
        result += "darts #{stats[:darts]} average #{format('%d.%02d', average.div(100), average % 100)}"
        result += " busts #{stats[:busts]} high #{stats[:high]} tons #{stats[:tons]} 180s #{stats[:maximums]}"
        result += " doubles #{stats[:hits]}/#{stats[:attempts]}"
      else
        stats = s[:rally][i]
        result += "points #{stats[:points]} serve #{stats[:serve_won]}/#{stats[:served]} run #{stats[:run]}"
        if @sport == "TENNIS"
          result += " holds #{stats[:holds]}/#{stats[:service_games]} breaks #{stats[:breaks]}"
          result += " break points #{stats[:conversions]}/#{stats[:opportunities]}"
        elsif @sport == "VOLLEYBALL"
          result += " subs #{s[:subs][i]} timeouts #{s[:timeouts][i]} lineup " + s[:lineups][i].join(",")
        end
      end
      result
    end
  end

  def result
    s = @state
    raise Invalid, "match not finished" unless s[:done]
    return "#{@id}: #{@names[0]} #{frame_scores(s).compact.sum}" if @sport == "BOWLING"
    "#{@id}: #{@names[s[:winner]]} def. #{@names[1 - s[:winner]]} " +
      s[:finished].map { |record| score_record(record, s[:winner] == 1) }.join(" ")
  end
end

class Scoreboard
  def initialize
    @matches = {}
  end

  def command(line)
    name, *args = line.split(" ")
    if name == "MATCH"
      raise Invalid, "duplicate match" if @matches.key?(args[0])
      match = Game.new(args)
      @matches[match.id] = match
      return []
    end
    if name == "CHECKOUT"
      answer = Darts.checkout(args[0].to_i)
      return ["checkout #{args[0]}: " + (answer ? answer.join(" ") : "none")]
    end
    if name == "STANDINGS"
      totals = {}
      @matches.each_value do |match|
        next if !match.state[:done] || match.sport == "BOWLING"
        match.names.each_with_index do |person, i|
          totals[person] ||= [0, 0]
          totals[person][i == match.state[:winner] ? 0 : 1] += 1
        end
      end
      ordered = totals.sort_by { |person, values| [-values[0], values[1], person] }
      display = ordered.map { |person, values| "#{person} #{values.join('-')}" }
      return ["standings: " + (display.empty? ? "none" : display.join(", "))]
    end
    match = @matches[args[0]]
    raise Invalid, "unknown match" unless match
    case name
    when "UNDO"
      match.undo
      []
    when "SCORE"
      [match.score]
    when "STATS"
      match.stats
    when "RESULT"
      [match.result]
    else
      match.event(name, args.drop(1))
      []
    end
  end
end

lines = STDIN.read.split("\n")
scoreboard = Scoreboard.new
output = []
lines[0].to_i.times do |i|
  begin
    output.concat(scoreboard.command(lines[i + 1]))
  rescue Invalid => error
    output << "ERROR " + error.message
  end
end
STDOUT.write(output.join("\n") + "\n") unless output.empty?
