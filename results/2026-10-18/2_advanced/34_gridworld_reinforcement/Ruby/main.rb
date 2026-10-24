require "fileutils"
require_relative "environment"
require_relative "dynamic_programming"
require_relative "td_learning"
require_relative "monte_carlo"
require_relative "report"

METHODS = %w[mc sarsa q_learning expected_sarsa dyna_q].freeze
POLICY_NAMES = (%w[value_iteration policy_iteration] + METHODS).freeze
ENDINGS = %w[goal pit timeout].freeze
ABSORPTION_UNIT = 100_000_000

class Settings
  attr_reader :gamma, :step_reward, :slip_total, :floor_slip, :ice_slip, :theta,
              :gamma_sweep, :slip_sweep, :episodes, :step_limit, :block_size,
              :planning_steps, :seed, :rollouts, :rollout_seed, :phases

  def initialize(path)
    fields = File.foreach(path).to_h do |line|
      keyword, *numbers = line.split
      [keyword, numbers.map(&:to_i)]
    end
    @gamma = fields.fetch("GAMMA").first
    @step_reward = fields.fetch("STEP_REWARD").first
    @slip_total, @floor_slip, @ice_slip = fields.fetch("SLIP")
    @theta = fields.fetch("THETA").first
    @gamma_sweep = fields.fetch("GAMMA_SWEEP")
    @slip_sweep = fields.fetch("SLIP_SWEEP").each_slice(2).to_a
    @episodes = fields.fetch("EPISODES").first
    @step_limit = fields.fetch("STEP_LIMIT").first
    @block_size = fields.fetch("BLOCK_SIZE").first
    @alpha_schedule = fields.fetch("ALPHA").each_slice(2).to_a
    @epsilon_schedule = fields.fetch("EPSILON").each_slice(2).to_a
    @planning_steps = fields.fetch("PLANNING_STEPS").first
    @seed = fields.fetch("SEED").first
    @rollouts = fields.fetch("ROLLOUTS").first
    @rollout_seed = fields.fetch("ROLLOUT_SEED").first
    starts = (@alpha_schedule + @epsilon_schedule).map(&:first).uniq.sort
    @phases = starts.each_with_index.map do |first, index|
      [first, index + 1 < starts.length ? starts[index + 1] - 1 : @episodes]
    end
  end

  def schedule_value(schedule, episode)
    schedule.reverse_each.find { |start, _| start <= episode }[1]
  end

  def alpha(episode)
    schedule_value(@alpha_schedule, episode)
  end

  def epsilon(episode)
    schedule_value(@epsilon_schedule, episode)
  end
end

module Analysis
  module_function

  def count_agreements(first, second)
    first.each_index.count { |state| first[state] == second[state] }
  end

  def ending_counts(endings)
    ENDINGS.map { |ending| endings.count(ending) }
  end

  def value_errors(q_values, optimal_values)
    q_values.each_with_index.map { |row, state| (row.max - optimal_values[state]).abs }
  end

  def nominal_path(environment, policy, origin, limit)
    world = environment.world
    cells = [origin]
    loop do
      state = world.state_index[cells.last]
      target = environment.moves[state][policy[state]]
      repeated = cells.include?(target)
      cells << target
      return [world.terminal_name(target), cells] if world.terminal?(target)
      return ["loop", cells] if repeated
      return ["limit", cells] if cells.length - 1 == limit
    end
  end

  def basin_symbols(environment, policy, limit)
    world = environment.world
    world.states.map do |cell|
      ending, cells = nominal_path(environment, policy, cell, limit)
      if ending == "goal" || ending == "pit"
        ("a".ord + world.terminal_index[cells.last]).chr
      else
        "*"
      end
    end
  end

  def risky_states(environment, policy)
    policy.each_with_index.count do |action, state|
      environment.transitions[state][action].any? do |cell, _|
        environment.world.kinds[cell] == "P"
      end
    end
  end

  def distances(environment)
    world = environment.world
    distance = Array.new(world.kinds.length)
    distance[world.start] = 0
    frontier = [world.start]
    until frontier.empty?
      following = []
      frontier.each do |cell|
        environment.transitions[world.state_index[cell]].each do |transitions|
          transitions.each do |target, _|
            next unless distance[target].nil?

            distance[target] = distance[cell] + 1
            following << target unless world.terminal?(target)
          end
        end
      end
      frontier = following.sort
    end
    distance
  end

  def symmetry(world, values, policy)
    pairs = equal = mirrored = 0
    mirror_actions = [0, 3, 2, 1]
    world.states.each_with_index do |cell, state|
      row, col = cell.divmod(world.cols)
      mirror_col = world.cols - 1 - col
      other = world.state_index[row * world.cols + mirror_col]
      next unless col < mirror_col && !other.nil?

      pairs += 1
      equal += 1 if values[state] == values[other]
      mirrored += 1 if policy[other] == mirror_actions[policy[state]]
    end
    [pairs, equal, mirrored]
  end

  def absorption(environment, policy, limit)
    world = environment.world
    goal = Array.new(policy.length, 0)
    pit = Array.new(policy.length, 0)
    expected = Array.new(policy.length, 0)
    limit.times do
      next_goal, next_pit, next_expected = [], [], []
      policy.each_with_index do |action, state|
        goal_total = pit_total = step_total = 0
        environment.transitions[state][action].each do |cell, numerator|
          target = world.state_index[cell]
          if !target.nil?
            goal_total += numerator * goal[target]
            pit_total += numerator * pit[target]
            step_total += numerator * expected[target]
          elsif world.kinds[cell] == "G"
            goal_total += numerator * ABSORPTION_UNIT
          else
            pit_total += numerator * ABSORPTION_UNIT
          end
        end
        next_goal << goal_total.div(environment.slip_total)
        next_pit << pit_total.div(environment.slip_total)
        next_expected << ABSORPTION_UNIT + step_total.div(environment.slip_total)
      end
      goal, pit, expected = next_goal, next_pit, next_expected
    end
    start = world.start_state
    [goal[start], pit[start], ABSORPTION_UNIT - goal[start] - pit[start], expected[start]]
  end

  def behaviour_value(environment, policy, epsilon, gamma, theta)
    values = Array.new(policy.length, 0)
    sweeps = 0
    loop do
      sweeps += 1
      delta = 0
      policy.each_with_index do |chosen, state|
        backups = DynamicProgramming.action_values(environment, values, gamma, state)
        total = backups.each_with_index.sum do |backup, action|
          weight = epsilon + (action == chosen ? 4 * (1000 - epsilon) : 0)
          weight * backup
        end
        value = total.div(4000)
        delta = [delta, (value - values[state]).abs].max
        values[state] = value
      end
      return [values[environment.world.start_state], sweeps] if delta <= theta
    end
  end

  def perform_rollouts(environment, policy, settings)
    world = environment.world
    generator = RandomGenerator.new(settings.rollout_seed)
    summary = RolloutSummary.new([], [], [], [], Array.new(world.terminals.length, 0))
    settings.rollouts.times do
      state = world.start_state
      rewards = []
      ending = "timeout"
      settings.step_limit.times do
        cell, reward = environment.step(generator, state, policy[state])
        rewards << reward
        state = world.state_index[cell]
        next unless state.nil?

        ending = world.terminal_name(cell)
        summary.terminal_counts[world.terminal_index[cell]] += 1
        break
      end
      summary.returns << rewards.sum
      summary.discounted << MonteCarlo.discounted_return(rewards, settings.gamma)
      summary.steps << rewards.length
      summary.endings << ending
    end
    summary
  end
end

Episode = Struct.new(:total, :steps, :ending, :cells, keyword_init: true)
RolloutSummary = Struct.new(:returns, :discounted, :steps, :endings, :terminal_counts)

class Learner
  include Analysis
  include DynamicProgramming
  include TDLearning

  attr_reader :name, :q_values, :visits, :episodes, :blocks

  def initialize(method, environment, settings)
    @name, @environment, @settings = method, environment, settings
    @generator = RandomGenerator.new(settings.seed)
    state_count = environment.world.states.length
    @q_values = Array.new(state_count) { Array.new(4, 0) }
    @visits = Array.new(state_count) { Array.new(4, 0) }
    @model = DynaModel.new(state_count) if method == "dyna_q"
    @averages = ReturnAverages.new(state_count) if method == "mc"
    @episodes, @blocks = [], []
  end

  def learn(optimal_values, optimal_policy)
    1.upto(@settings.episodes) do |number|
      @alpha = @settings.alpha(number)
      @epsilon = @settings.epsilon(number)
      @episodes << play(number == @settings.episodes)
      next unless (number % @settings.block_size).zero?

      agree = count_agreements(policy, optimal_policy)
      error = value_errors(@q_values, optimal_values).sum.div(optimal_values.length)
      coverage = state_visits.count(&:positive?)
      @blocks << [agree, error, coverage]
    end
  end

  def select_action(state)
    choose(@generator, @q_values[state], @epsilon)
  end

  def play(keep_cells)
    world = @environment.world
    state = world.start_state
    episode = Episode.new(total: 0, steps: 0, ending: "timeout", cells: keep_cells ? [world.start] : nil)
    history = []
    action = select_action(state) if @name == "sarsa"
    @settings.step_limit.times do
      action = select_action(state) unless @name == "sarsa"
      cell, reward = @environment.step(@generator, state, action)
      @visits[state][action] += 1
      episode.total += reward
      episode.steps += 1
      episode.cells << cell if episode.cells
      next_state = world.state_index[cell]
      case @name
      when "mc"
        history << [state, action, reward]
      when "sarsa"
        action = sarsa_update(state, action, reward, next_state)
      else
        off_policy_update(state, action, reward, next_state)
      end
      if next_state.nil?
        episode.ending = world.terminal_name(cell)
        break
      end
      state = next_state
    end
    @averages.update(@q_values, history, @settings.gamma) if @name == "mc"
    episode
  end

  def sarsa_update(state, action, reward, next_state)
    terminal = next_state.nil?
    next_action = action
    future = 0
    unless terminal
      next_action = select_action(next_state)
      future = @q_values[next_state][next_action]
    end
    target = td_target(reward, terminal, future, @settings.gamma)
    td_update(@q_values[state], action, target, @alpha)
    next_action
  end

  def off_policy_update(state, action, reward, next_state)
    terminal = next_state.nil?
    epsilon = @name == "expected_sarsa" ? @epsilon : nil
    future = terminal ? 0 : next_value(@q_values[next_state], epsilon)
    target = td_target(reward, terminal, future, @settings.gamma)
    td_update(@q_values[state], action, target, @alpha)
    return unless @name == "dyna_q"

    @model.record(state, action, reward, next_state)
    @model.plan(@generator, @q_values, @settings.gamma, @alpha, @settings.planning_steps)
  end

  def policy
    @q_values.map { |row| first_max(row) }
  end

  def state_visits
    @visits.map(&:sum)
  end

  def block_episodes(number)
    @episodes[(number - 1) * @settings.block_size, @settings.block_size]
  end

  def block_returns
    @episodes.each_slice(@settings.block_size).map { |episodes| episodes.sum(&:total) }
  end
end

class PolicyEvaluation
  include Analysis
  include DynamicProgramming

  attr_reader :values, :sweeps, :agree, :optimal_actions, :max_gap, :max_gap_state,
              :improved_changes, :improved_start, :improved_agree, :absorption, :rollouts

  def initialize(experiment, policy)
    environment, settings = experiment.environment, experiment.settings
    zeros = Array.new(policy.length, 0)
    @values, @sweeps = evaluate_policy(environment, policy, zeros, settings.gamma, settings.theta)
    @agree = count_agreements(policy, experiment.optimal_policy)
    @optimal_actions = policy.each_index.count do |state|
      experiment.optimal_actions[state].include?(policy[state])
    end
    gaps = @values.each_index.map { |state| experiment.optimal_values[state] - @values[state] }
    @max_gap = gaps.max
    @max_gap_state = gaps.index(@max_gap)
    improved = greedy_policy(environment, @values, settings.gamma)
    @improved_changes = policy.length - count_agreements(improved, policy)
    improved_values, = evaluate_policy(environment, improved, zeros, settings.gamma, settings.theta)
    @improved_start = improved_values[environment.world.start_state]
    @improved_agree = count_agreements(improved, experiment.optimal_policy)
    @absorption = Analysis.absorption(environment, policy, settings.step_limit)
    @rollouts = perform_rollouts(environment, policy, settings)
  end
end

class Experiment
  include Analysis
  include DynamicProgramming
  include Report

  attr_reader :world, :settings, :environment, :optimal_values, :optimal_policy, :optimal_actions

  def initialize(world, settings)
    @world, @settings = world, settings
    @environment = environment_with(settings.floor_slip, settings.ice_slip)
    @optimal_values, @changes = value_iteration(@environment, settings.gamma, settings.theta)
    @optimal_q = world.states.each_index.map do |state|
      action_values(@environment, @optimal_values, settings.gamma, state)
    end
    @optimal_policy = @optimal_q.map { |row| first_max(row) }
    @optimal_actions = @optimal_q.map { |row| (0...4).select { |action| row[action] == row.max } }
    _, @in_place_sweeps = in_place_value_iteration(@environment, settings.gamma, settings.theta)
    @iteration_policy, @iteration_values, @rounds = policy_iteration(@environment, settings.gamma, settings.theta)
    @learners = METHODS.map do |method|
      learner = Learner.new(method, @environment, settings)
      learner.learn(@optimal_values, @optimal_policy)
      learner
    end
    @policies = [@optimal_policy, @iteration_policy] + @learners.map(&:policy)
    @evaluations = @policies.map { |policy| PolicyEvaluation.new(self, policy) }
  end

  def environment_with(floor_slip, ice_slip)
    Environment.new(@world, @settings.step_reward, @settings.slip_total, floor_slip, ice_slip)
  end

  def state_text(state)
    cell_text(@world, @world.states[state])
  end

  def world_part
    kinds = @world.kinds
    distance = distances(@environment)
    reachable = @world.states.count { |cell| !distance[cell].nil? }
    lines = [
      "world rows #{@world.rows} cols #{@world.cols} states #{@world.states.length} " \
      "walls #{kinds.count('#')} floor #{kinds.count('.S')} ice #{kinds.count('~')} " \
      "goals #{kinds.count('G')} pits #{kinds.count('P')}",
      "start #{cell_text(@world, @world.start)} reachable #{reachable}"
    ]
    @world.terminals.each_with_index do |cell, index|
      steps = distance[cell].nil? ? "-" : distance[cell]
      lines << "terminal #{cell_text(@world, cell)} #{@world.terminal_name(cell)} " \
               "reward #{@world.terminal_rewards[index]} distance #{steps}"
    end
    lines
  end

  def value_iteration_part
    lines = ["value_iteration gamma #{@settings.gamma} theta #{fixed_text(@settings.theta)} iterations #{@changes.length}"]
    @changes.each_with_index { |change, index| lines << "iteration #{index + 1} max_change #{fixed_text(change)}" }
    lines
  end

  def ties_part
    tied = @optimal_actions.each_index.select { |state| @optimal_actions[state].length > 1 }
    lines = ["ties #{tied.length}"]
    tied.each do |state|
      letters = @optimal_actions[state].map { |action| ACTION_LETTERS[action] }.join
      lines << "tie #{state_text(state)} #{letters}"
    end
    pairs, equal, mirrored = symmetry(@world, @optimal_values, @optimal_policy)
    lines << "symmetry pairs #{pairs} equal_values #{equal} mirrored_actions #{mirrored}"
    lines
  end

  def policy_iteration_part
    lines = ["policy_iteration rounds #{@rounds.length}"]
    @rounds.each_with_index do |(sweeps, changes, start_value), index|
      lines << "round #{index + 1} sweeps #{sweeps} changed #{changes} value_start #{fixed_text(start_value)}"
    end
    lines
  end

  def comparison_part
    count = @world.states.length
    differences = @iteration_values.each_index.map { |state| (@iteration_values[state] - @optimal_values[state]).abs }
    largest = differences.max
    policy_differences = count - count_agreements(@iteration_policy, @optimal_policy)
    policy_backups = @rounds.sum(&:first) * count + @rounds.length * count * 4
    [
      "comparison policy_differences #{policy_differences} max_value_difference #{fixed_text(largest)} " \
      "at #{state_text(differences.index(largest))}",
      "backups value_iteration #{@changes.length * count * 4} in_place_iterations #{@in_place_sweeps} " \
      "in_place #{@in_place_sweeps * count * 4} policy_iteration #{policy_backups}"
    ]
  end

  def sensitivity_text(environment, gamma)
    values, changes = value_iteration(environment, gamma, @settings.theta)
    policy = greedy_policy(environment, values, gamma)
    ending, cells = nominal_path(environment, policy, @world.start, @settings.step_limit)
    differences = policy.length - count_agreements(policy, @optimal_policy)
    "iterations #{changes.length} value_start #{fixed_text(values[@world.start_state])} " \
    "path #{ending} steps #{cells.length - 1} last #{cell_text(@world, cells.last)} differences #{differences}"
  end

  def values_report
    gamma_lines = @settings.gamma_sweep.map do |gamma|
      "gamma #{gamma} #{sensitivity_text(@environment, gamma)}"
    end
    slip_lines = @settings.slip_sweep.map do |floor_slip, ice_slip|
      environment = environment_with(floor_slip, ice_slip)
      "slip #{floor_slip} #{ice_slip} #{sensitivity_text(environment, @settings.gamma)}"
    end
    join_parts([
      world_part,
      value_iteration_part,
      ["optimal_values"] + value_grid(@world, @optimal_values),
      ["optimal_action_counts"] + grid_lines(@world, @optimal_actions.map { |actions| actions.length.to_s }),
      ties_part,
      policy_iteration_part,
      ["policy_iteration_values"] + value_grid(@world, @iteration_values),
      comparison_part,
      ["gamma_sweep"] + gamma_lines,
      ["slip_sweep"] + slip_lines
    ])
  end

  def policy_part(name, policy, learner = nil)
    limit = @settings.step_limit
    ending, cells = nominal_path(@environment, policy, @world.start, limit)
    counts = Array.new(4) { |action| policy.count(action) }
    lines = [name] + policy_grid(@world, policy)
    lines << "path #{ending} steps #{cells.length - 1} #{cells_text(@world, cells)}"
    lines << "actions N #{counts[0]} E #{counts[1]} S #{counts[2]} W #{counts[3]} risk #{risky_states(@environment, policy)}"
    lines << "basins"
    lines.concat(grid_lines(@world, basin_symbols(@environment, policy, limit)))
    if learner
      digits = learner.state_visits.map { |total| total.positive? ? total.to_s.length.to_s : "0" }
      lines << "visits"
      lines.concat(grid_lines(@world, digits))
    end
    lines
  end

  def policies_report
    parts = [policy_part("value_iteration", @optimal_policy), policy_part("policy_iteration", @iteration_policy)]
    @learners.each { |learner| parts << policy_part(learner.name, learner.policy, learner) }
    join_parts(parts)
  end

  def q_table
    lines = ["method,row,col,action,value,visits"] + q_table_rows(@world, "value_iteration", @optimal_q, nil)
    @learners.each { |learner| lines.concat(q_table_rows(@world, learner.name, learner.q_values, learner.visits)) }
    lines
  end

  def learning_curves
    size = @settings.block_size
    lines = ["method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage"]
    @learners.each do |learner|
      learner.blocks.each_with_index do |(agree, error, coverage), index|
        episodes = learner.block_episodes(index + 1)
        fields = [learner.name, index + 1, average_text(episodes.sum(&:total), size),
                  average_text(episodes.sum(&:steps), size)]
        fields.concat(ending_counts(episodes.map(&:ending)))
        fields.concat([agree, fixed_text(error), coverage])
        lines << fields.join(",")
      end
    end
    lines
  end

  def summary_part
    ["summary states #{@world.states.length} start #{cell_text(@world, @world.start)} " \
     "rollouts #{@settings.rollouts} step_limit #{@settings.step_limit}"]
  end

  def policy_values_part
    lines = ["policies", "policy agree optimal_actions value_start sweeps max_gap at"]
    POLICY_NAMES.zip(@evaluations).each do |name, evaluation|
      lines << [name, evaluation.agree, evaluation.optimal_actions,
                fixed_text(evaluation.values[@world.start_state]), evaluation.sweeps,
                fixed_text(evaluation.max_gap), state_text(evaluation.max_gap_state)].join(" ")
    end
    lines
  end

  def improvement_part
    lines = ["improvement", "policy changed value_start agree"]
    POLICY_NAMES.zip(@evaluations).each do |name, evaluation|
      lines << [name, evaluation.improved_changes, fixed_text(evaluation.improved_start),
                evaluation.improved_agree].join(" ")
    end
    lines
  end

  def absorption_part
    lines = ["absorption", "policy p_goal p_pit p_timeout expected_steps"]
    POLICY_NAMES.zip(@evaluations).each do |name, evaluation|
      fields = evaluation.absorption.map { |value| fixed_text(value.div(10_000)) }
      lines << ([name] + fields).join(" ")
    end
    lines
  end

  def behaviour_part
    epsilon = @settings.epsilon(@settings.episodes)
    lines = ["behaviour", "method epsilon value_start sweeps"]
    @learners.each do |learner|
      value, sweeps = behaviour_value(@environment, learner.policy, epsilon, @settings.gamma, @settings.theta)
      lines << "#{learner.name} #{epsilon} #{fixed_text(value)} #{sweeps}"
    end
    lines
  end

  def q_errors_part
    lines = ["q_errors", "method mean_abs max_abs at unvisited tied"]
    @learners.each do |learner|
      errors = value_errors(learner.q_values, @optimal_values)
      largest = errors.max
      unvisited = learner.state_visits.count(&:zero?)
      tied = learner.q_values.count { |row| row.count(row.max) > 1 }
      lines << [learner.name, fixed_text(errors.sum.div(errors.length)), fixed_text(largest),
                state_text(errors.index(largest)), unvisited, tied].join(" ")
    end
    lines
  end

  def q_action_errors_part
    lines = ["q_action_errors", "method N E S W"]
    @learners.each do |learner|
      fields = [learner.name]
      4.times do |action|
        errors = learner.q_values.each_with_index.filter_map do |row, state|
          (row[action] - @optimal_q[state][action]).abs if learner.visits[state][action].positive?
        end
        fields << (errors.empty? ? "-" : fixed_text(errors.sum.div(errors.length)))
      end
      lines << fields.join(" ")
    end
    lines
  end

  def rollouts_part
    count = @settings.rollouts
    lines = ["rollouts", "policy mean_return mean_discounted mean_steps goals pits timeouts min median max"]
    POLICY_NAMES.zip(@evaluations).each do |name, evaluation|
      summary = evaluation.rollouts
      returns = summary.returns.sort
      fields = [name, average_text(summary.returns.sum, count), fixed_text(summary.discounted.sum.div(count)),
                average_text(summary.steps.sum, count)]
      fields.concat(ending_counts(summary.endings))
      fields.concat([returns.first, returns[(count + 1).div(2) - 1], returns.last])
      lines << fields.join(" ")
    end
    lines
  end

  def terminals_part
    lines = ["terminals", "policy #{cells_text(@world, @world.terminals)}"]
    POLICY_NAMES.zip(@evaluations).each do |name, evaluation|
      lines << ([name] + evaluation.rollouts.terminal_counts).join(" ")
    end
    lines
  end

  def agreement_part
    lines = ["agreement", "policy #{POLICY_NAMES.join(' ')}"]
    POLICY_NAMES.zip(@policies).each do |name, policy|
      lines << ([name] + @policies.map { |other| count_agreements(policy, other) }).join(" ")
    end
    lines
  end

  def training_part
    size = @settings.block_size
    optimal_total = @evaluations.first.rollouts.returns.sum
    lines = ["training", "method steps goals pits timeouts best_block best_mean last_mean reach"]
    @learners.each do |learner|
      totals = learner.block_returns
      best = totals.index(totals.max)
      reach = totals.index { |total| 10 * @settings.rollouts * total >= 9 * size * optimal_total }
      fields = [learner.name, learner.episodes.sum(&:steps)]
      fields.concat(ending_counts(learner.episodes.map(&:ending)))
      fields.concat([best + 1, average_text(totals[best], size), average_text(totals.last, size),
                     reach.nil? ? "-" : reach + 1])
      lines << fields.join(" ")
    end
    lines
  end

  def visited_part
    lines = ["visited"]
    @learners.each do |learner|
      totals = learner.state_visits
      order = totals.each_index.sort_by { |state| [-totals[state], state] }.first(3)
      entries = order.map { |state| "#{state_text(state)}:#{totals[state]}" }
      lines << ([learner.name] + entries).join(" ")
    end
    lines
  end

  def last_episodes_part
    lines = ["last_episodes"]
    @learners.each do |learner|
      episode = learner.episodes.last
      lines << "#{learner.name} return #{episode.total} steps #{episode.steps} end #{episode.ending} " \
               "#{cells_text(@world, episode.cells)}"
    end
    lines
  end

  def phases_part
    lines = ["phases"]
    @learners.each do |learner|
      @settings.phases.each do |first, last|
        episodes = learner.episodes[first - 1, last - first + 1]
        lines << "#{learner.name} #{first}-#{last} alpha #{@settings.alpha(first)} epsilon #{@settings.epsilon(first)} " \
                 "mean_return #{average_text(episodes.sum(&:total), episodes.length)} " \
                 "mean_steps #{average_text(episodes.sum(&:steps), episodes.length)} " \
                 "goals #{episodes.count { |episode| episode.ending == 'goal' }}"
      end
    end
    lines
  end

  def evaluation_report
    join_parts([summary_part, policy_values_part, improvement_part, absorption_part,
                behaviour_part, q_errors_part, q_action_errors_part, rollouts_part,
                terminals_part, agreement_part, training_part, visited_part,
                last_episodes_part, phases_part])
  end

  def write_reports(directory)
    FileUtils.mkdir_p(directory)
    {
      "values.txt" => values_report,
      "policies.txt" => policies_report,
      "q_tables.csv" => q_table,
      "learning_curves.csv" => learning_curves,
      "evaluation.txt" => evaluation_report
    }.each { |name, lines| write_lines(File.join(directory, name), lines) }
  end
end

if $PROGRAM_NAME == __FILE__
  world = World.read("input/world.txt")
  settings = Settings.new("input/params.txt")
  Experiment.new(world, settings).write_reports("output")
end
