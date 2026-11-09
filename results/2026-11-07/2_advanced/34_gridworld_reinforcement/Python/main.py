import os

from dynamic_programming import (
    action_values, evaluate_policy, first_max, greedy_policy,
    in_place_value_iteration, policy_iteration, value_iteration,
)
from environment import (
    ACTION_LETTERS, FLOOR, GOAL, ICE, PIT, START, WALL,
    Environment, RandomGenerator, read_world,
)
from monte_carlo import ReturnAverages, discounted_return
from report import (
    average_text, cell_text, cells_text, fixed_text, join_parts, policy_grid,
    q_table_rows, symbol_grid, value_grid, write_lines,
)
from td_learning import DynaModel, choose, expected_value, td_target, td_update


INPUT_DIRECTORY = "input"
OUTPUT_DIRECTORY = "output"
METHODS = ("mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q")
POLICY_NAMES = ("value_iteration", "policy_iteration") + METHODS
ENDINGS = ("goal", "pit", "timeout")
MIRRORED_ACTIONS = (0, 3, 2, 1)
ABSORPTION_UNIT = 100000000


def pairs_of(values):
    return [(values[index], values[index + 1]) for index in range(0, len(values), 2)]


class Settings:
    def __init__(self, path):
        fields = {}
        with open(path) as file:
            for line in file:
                keyword, *numbers = line.split()
                fields[keyword] = [int(number) for number in numbers]
        self.gamma = fields["GAMMA"][0]
        self.step_reward = fields["STEP_REWARD"][0]
        self.slip_total, self.floor_slip, self.ice_slip = fields["SLIP"]
        self.theta = fields["THETA"][0]
        self.gamma_sweep = fields["GAMMA_SWEEP"]
        self.slip_sweep = pairs_of(fields["SLIP_SWEEP"])
        self.episodes = fields["EPISODES"][0]
        self.step_limit = fields["STEP_LIMIT"][0]
        self.block_size = fields["BLOCK_SIZE"][0]
        self.alpha_schedule = pairs_of(fields["ALPHA"])
        self.epsilon_schedule = pairs_of(fields["EPSILON"])
        self.planning_steps = fields["PLANNING_STEPS"][0]
        self.seed = fields["SEED"][0]
        self.rollouts = fields["ROLLOUTS"][0]
        self.rollout_seed = fields["ROLLOUT_SEED"][0]


def schedule_value(schedule, episode):
    value = schedule[0][1]
    for start, number in schedule:
        if start <= episode:
            value = number
    return value


def phase_ranges(settings):
    starts = sorted({start for start, _ in settings.alpha_schedule + settings.epsilon_schedule})
    ends = [start - 1 for start in starts[1:]] + [settings.episodes]
    return list(zip(starts, ends))


def count_agreements(first, second):
    return sum(left == right for left, right in zip(first, second))


def ending_counts(endings):
    return [endings.count(ending) for ending in ENDINGS]


def value_errors(q_values, optimal_values):
    return [abs(max(row) - optimal) for row, optimal in zip(q_values, optimal_values)]


class Episode:
    def __init__(self, start):
        self.total = 0
        self.steps = 0
        self.ending = "timeout"
        self.cells = [start]

    def record(self, cell, reward):
        self.total += reward
        self.steps += 1
        self.cells.append(cell)


class Learner:
    def __init__(self, method, environment, settings):
        state_count = len(environment.world.states)
        self.method = method
        self.environment = environment
        self.settings = settings
        self.generator = RandomGenerator(settings.seed)
        self.q_values = [[0] * 4 for _ in range(state_count)]
        self.visits = [[0] * 4 for _ in range(state_count)]
        self.model = DynaModel(state_count)
        self.averages = ReturnAverages(state_count)
        self.alpha = 0
        self.epsilon = 0
        self.episodes = []
        self.blocks = []

    def learn(self, optimal_values, optimal_policy):
        settings = self.settings
        for number in range(1, settings.episodes + 1):
            self.alpha = schedule_value(settings.alpha_schedule, number)
            self.epsilon = schedule_value(settings.epsilon_schedule, number)
            self.episodes.append(self.play())
            if number % settings.block_size == 0:
                self.blocks.append(self.block_record(optimal_values, optimal_policy))

    def select_action(self, state):
        return choose(self.generator, self.q_values[state], self.epsilon)

    def play(self):
        world = self.environment.world
        state = world.start_state
        episode = Episode(world.start)
        history = []
        action = self.select_action(state) if self.method == "sarsa" else 0
        while episode.steps < self.settings.step_limit:
            if self.method != "sarsa":
                action = self.select_action(state)
            cell, reward = self.environment.step(self.generator, state, action)
            self.visits[state][action] += 1
            episode.record(cell, reward)
            next_state = world.state_index[cell]
            if self.method == "mc":
                history.append((state, action, reward))
            elif self.method == "sarsa":
                action = self.sarsa_update(state, action, reward, next_state)
            else:
                self.off_policy_update(state, action, reward, next_state)
            if next_state is None:
                episode.ending = world.terminal_name(cell)
                break
            state = next_state
        if self.method == "mc":
            self.averages.update(self.q_values, history, self.settings.gamma)
        return episode

    def sarsa_update(self, state, action, reward, next_state):
        terminal = next_state is None
        next_action = action
        next_value = 0
        if not terminal:
            next_action = self.select_action(next_state)
            next_value = self.q_values[next_state][next_action]
        target = td_target(reward, terminal, next_value, self.settings.gamma)
        td_update(self.q_values[state], action, target, self.alpha)
        return next_action

    def off_policy_update(self, state, action, reward, next_state):
        terminal = next_state is None
        next_value = 0
        if not terminal and self.method == "expected_sarsa":
            next_value = expected_value(self.q_values[next_state], self.epsilon)
        elif not terminal:
            next_value = max(self.q_values[next_state])
        target = td_target(reward, terminal, next_value, self.settings.gamma)
        td_update(self.q_values[state], action, target, self.alpha)
        if self.method == "dyna_q":
            self.model.record(state, action, reward, next_state)
            self.model.plan(
                self.generator, self.q_values, self.settings.gamma,
                self.alpha, self.settings.planning_steps,
            )

    def block_record(self, optimal_values, optimal_policy):
        agree = count_agreements(self.policy(), optimal_policy)
        error = sum(value_errors(self.q_values, optimal_values)) // len(optimal_values)
        coverage = sum(total > 0 for total in self.state_visits())
        return agree, error, coverage

    def policy(self):
        return [first_max(row) for row in self.q_values]

    def state_visits(self):
        return [sum(row) for row in self.visits]

    def block_episodes(self, number):
        size = self.settings.block_size
        return self.episodes[(number - 1) * size:number * size]

    def block_returns(self):
        return [
            sum(episode.total for episode in self.block_episodes(number))
            for number in range(1, len(self.blocks) + 1)
        ]


def nominal_path(environment, policy, origin, limit):
    world = environment.world
    cells = [origin]
    while True:
        state = world.state_index[cells[-1]]
        target = environment.moves[state][policy[state]]
        repeated = target in cells
        cells.append(target)
        if world.is_terminal(target):
            return world.terminal_name(target), cells
        if repeated:
            return "loop", cells
        if len(cells) - 1 == limit:
            return "limit", cells


def basin_symbols(environment, policy, limit):
    world = environment.world
    symbols = []
    for cell in world.states:
        ending, cells = nominal_path(environment, policy, cell, limit)
        if ending in ("goal", "pit"):
            symbols.append(chr(ord("a") + world.terminal_index[cells[-1]]))
        else:
            symbols.append("*")
    return symbols


def action_counts(policy):
    return [policy.count(action) for action in range(4)]


def risky_states(environment, policy):
    world = environment.world
    return sum(
        any(world.kinds[cell] == PIT for cell, _ in environment.transitions[state][action])
        for state, action in enumerate(policy)
    )


def distances(environment):
    world = environment.world
    distance = [None] * len(world.kinds)
    distance[world.start] = 0
    frontier = [world.start]
    level = 0
    while frontier:
        level += 1
        following = []
        for cell in frontier:
            for transitions in environment.transitions[world.state_index[cell]]:
                for target, _ in transitions:
                    if distance[target] is None:
                        distance[target] = level
                        if not world.is_terminal(target):
                            following.append(target)
        frontier = following
    return distance


def symmetry(world, values, policy):
    pairs = 0
    equal = 0
    mirrored = 0
    for state, cell in enumerate(world.states):
        row, col = divmod(cell, world.cols)
        mirror_col = world.cols - 1 - col
        other = world.state_index[row * world.cols + mirror_col]
        if col < mirror_col and other is not None:
            pairs += 1
            if values[state] == values[other]:
                equal += 1
            if policy[other] == MIRRORED_ACTIONS[policy[state]]:
                mirrored += 1
    return pairs, equal, mirrored


def absorption(environment, policy, limit):
    world = environment.world
    goal = [0] * len(policy)
    pit = [0] * len(policy)
    expected = [0] * len(policy)
    for _ in range(limit):
        next_goal = []
        next_pit = []
        next_expected = []
        for state, action in enumerate(policy):
            goal_total = 0
            pit_total = 0
            step_total = 0
            for cell, numerator in environment.transitions[state][action]:
                target = world.state_index[cell]
                if target is not None:
                    goal_total += numerator * goal[target]
                    pit_total += numerator * pit[target]
                    step_total += numerator * expected[target]
                elif world.kinds[cell] == GOAL:
                    goal_total += numerator * ABSORPTION_UNIT
                else:
                    pit_total += numerator * ABSORPTION_UNIT
            next_goal.append(goal_total // environment.slip_total)
            next_pit.append(pit_total // environment.slip_total)
            next_expected.append(ABSORPTION_UNIT + step_total // environment.slip_total)
        goal, pit, expected = next_goal, next_pit, next_expected
    start = world.start_state
    return goal[start], pit[start], expected[start]


def behaviour_value(environment, policy, epsilon, gamma, theta):
    values = [0] * len(policy)
    sweeps = 0
    while True:
        sweeps += 1
        delta = 0
        for state, chosen in enumerate(policy):
            total = 0
            for action, backup in enumerate(action_values(environment, values, gamma, state)):
                weight = epsilon + 4 * (1000 - epsilon) if action == chosen else epsilon
                total += weight * backup
            value = total // 4000
            delta = max(delta, abs(value - values[state]))
            values[state] = value
        if delta <= theta:
            return values[environment.world.start_state], sweeps


class RolloutSummary:
    def __init__(self, terminal_count):
        self.returns = []
        self.discounted = []
        self.steps = []
        self.endings = []
        self.terminal_counts = [0] * terminal_count

    def add(self, rewards, ending, gamma):
        self.returns.append(sum(rewards))
        self.discounted.append(discounted_return(rewards, gamma))
        self.steps.append(len(rewards))
        self.endings.append(ending)


def perform_rollouts(environment, policy, settings):
    world = environment.world
    generator = RandomGenerator(settings.rollout_seed)
    summary = RolloutSummary(len(world.terminals))
    for _ in range(settings.rollouts):
        state = world.start_state
        rewards = []
        ending = "timeout"
        while len(rewards) < settings.step_limit:
            cell, reward = environment.step(generator, state, policy[state])
            rewards.append(reward)
            state = world.state_index[cell]
            if state is None:
                ending = world.terminal_name(cell)
                summary.terminal_counts[world.terminal_index[cell]] += 1
                break
        summary.add(rewards, ending, settings.gamma)
    return summary


class PolicyEvaluation:
    def __init__(self, experiment, policy):
        environment = experiment.environment
        settings = experiment.settings
        gamma = settings.gamma
        theta = settings.theta
        zeros = [0] * len(policy)
        self.values, self.sweeps = evaluate_policy(environment, policy, zeros, gamma, theta)
        self.agree = count_agreements(policy, experiment.optimal_policy)
        self.optimal_actions = sum(
            action in actions for action, actions in zip(policy, experiment.optimal_actions)
        )
        gaps = [optimal - value for optimal, value in zip(experiment.optimal_values, self.values)]
        self.max_gap = max(gaps)
        self.max_gap_state = gaps.index(self.max_gap)
        improved = greedy_policy(environment, self.values, gamma)
        self.improved_changes = len(policy) - count_agreements(improved, policy)
        improved_values, _ = evaluate_policy(environment, improved, zeros, gamma, theta)
        self.improved_start = improved_values[environment.world.start_state]
        self.improved_agree = count_agreements(improved, experiment.optimal_policy)
        self.absorption = absorption(environment, policy, settings.step_limit)
        self.rollouts = perform_rollouts(environment, policy, settings)


class Experiment:
    def __init__(self, world, settings):
        self.world = world
        self.settings = settings
        self.environment = self.environment_with(settings.floor_slip, settings.ice_slip)
        environment = self.environment
        gamma = settings.gamma
        theta = settings.theta
        self.optimal_values, self.changes = value_iteration(environment, gamma, theta)
        self.optimal_q = [
            action_values(environment, self.optimal_values, gamma, state)
            for state in range(len(world.states))
        ]
        self.optimal_policy = [first_max(row) for row in self.optimal_q]
        self.optimal_actions = [
            [action for action in range(4) if row[action] == max(row)] for row in self.optimal_q
        ]
        _, self.in_place_sweeps = in_place_value_iteration(environment, gamma, theta)
        self.iteration_policy, self.iteration_values, self.rounds = policy_iteration(
            environment, gamma, theta
        )
        self.learners = []
        for method in METHODS:
            learner = Learner(method, environment, settings)
            learner.learn(self.optimal_values, self.optimal_policy)
            self.learners.append(learner)
        self.policies = [self.optimal_policy, self.iteration_policy]
        self.policies.extend(learner.policy() for learner in self.learners)
        self.evaluations = [PolicyEvaluation(self, policy) for policy in self.policies]

    def environment_with(self, floor_slip, ice_slip):
        settings = self.settings
        return Environment(
            self.world, settings.step_reward, settings.slip_total, floor_slip, ice_slip
        )

    def state_text(self, state):
        return cell_text(self.world, self.world.states[state])

    def world_part(self):
        world = self.world
        kinds = world.kinds
        distance = distances(self.environment)
        reachable = sum(distance[cell] is not None for cell in world.states)
        lines = [
            f"world rows {world.rows} cols {world.cols} states {len(world.states)} "
            f"walls {kinds.count(WALL)} floor {kinds.count(FLOOR) + kinds.count(START)} "
            f"ice {kinds.count(ICE)} goals {kinds.count(GOAL)} pits {kinds.count(PIT)}",
            f"start {cell_text(world, world.start)} reachable {reachable}",
        ]
        for index, cell in enumerate(world.terminals):
            steps = "-" if distance[cell] is None else str(distance[cell])
            lines.append(
                f"terminal {cell_text(world, cell)} {world.terminal_name(cell)} "
                f"reward {world.terminal_rewards[index]} distance {steps}"
            )
        return lines

    def value_iteration_part(self):
        settings = self.settings
        lines = [
            f"value_iteration gamma {settings.gamma} theta {fixed_text(settings.theta)} "
            f"iterations {len(self.changes)}"
        ]
        for number, change in enumerate(self.changes, 1):
            lines.append(f"iteration {number} max_change {fixed_text(change)}")
        return lines

    def ties_part(self):
        tied = [state for state, actions in enumerate(self.optimal_actions) if len(actions) > 1]
        lines = [f"ties {len(tied)}"]
        for state in tied:
            letters = "".join(ACTION_LETTERS[action] for action in self.optimal_actions[state])
            lines.append(f"tie {self.state_text(state)} {letters}")
        pairs, equal, mirrored = symmetry(self.world, self.optimal_values, self.optimal_policy)
        lines.append(f"symmetry pairs {pairs} equal_values {equal} mirrored_actions {mirrored}")
        return lines

    def policy_iteration_part(self):
        lines = [f"policy_iteration rounds {len(self.rounds)}"]
        for number, (sweeps, changes, start_value) in enumerate(self.rounds, 1):
            lines.append(
                f"round {number} sweeps {sweeps} changed {changes} "
                f"value_start {fixed_text(start_value)}"
            )
        return lines

    def comparison_part(self):
        state_count = len(self.world.states)
        differences = [
            abs(value - optimal)
            for value, optimal in zip(self.iteration_values, self.optimal_values)
        ]
        largest = max(differences)
        agreements = count_agreements(self.iteration_policy, self.optimal_policy)
        policy_differences = state_count - agreements
        total_sweeps = sum(sweeps for sweeps, _, _ in self.rounds)
        iteration_backups = len(self.changes) * state_count * 4
        in_place_backups = self.in_place_sweeps * state_count * 4
        policy_backups = total_sweeps * state_count + len(self.rounds) * state_count * 4
        return [
            f"comparison policy_differences {policy_differences} "
            f"max_value_difference {fixed_text(largest)} "
            f"at {self.state_text(differences.index(largest))}",
            f"backups value_iteration {iteration_backups} "
            f"in_place_iterations {self.in_place_sweeps} in_place {in_place_backups} "
            f"policy_iteration {policy_backups}",
        ]

    def sensitivity_text(self, environment, gamma):
        world = self.world
        values, changes = value_iteration(environment, gamma, self.settings.theta)
        policy = greedy_policy(environment, values, gamma)
        ending, cells = nominal_path(environment, policy, world.start, self.settings.step_limit)
        differences = len(policy) - count_agreements(policy, self.optimal_policy)
        return (
            f"iterations {len(changes)} value_start {fixed_text(values[world.start_state])} "
            f"path {ending} steps {len(cells) - 1} last {cell_text(world, cells[-1])} "
            f"differences {differences}"
        )

    def gamma_sweep_part(self):
        lines = ["gamma_sweep"]
        for gamma in self.settings.gamma_sweep:
            lines.append(f"gamma {gamma} " + self.sensitivity_text(self.environment, gamma))
        return lines

    def slip_sweep_part(self):
        lines = ["slip_sweep"]
        for floor_slip, ice_slip in self.settings.slip_sweep:
            environment = self.environment_with(floor_slip, ice_slip)
            details = self.sensitivity_text(environment, self.settings.gamma)
            lines.append(f"slip {floor_slip} {ice_slip} {details}")
        return lines

    def values_report(self):
        world = self.world
        action_set_sizes = [str(len(actions)) for actions in self.optimal_actions]
        return join_parts([
            self.world_part(),
            self.value_iteration_part(),
            ["optimal_values"] + value_grid(world, self.optimal_values),
            ["optimal_action_counts"] + symbol_grid(world, action_set_sizes),
            self.ties_part(),
            self.policy_iteration_part(),
            ["policy_iteration_values"] + value_grid(world, self.iteration_values),
            self.comparison_part(),
            self.gamma_sweep_part(),
            self.slip_sweep_part(),
        ])

    def policy_part(self, name, policy, learner):
        world = self.world
        limit = self.settings.step_limit
        ending, cells = nominal_path(self.environment, policy, world.start, limit)
        north, east, south, west = action_counts(policy)
        lines = [name] + policy_grid(world, policy)
        lines.append(f"path {ending} steps {len(cells) - 1} {cells_text(world, cells)}")
        lines.append(
            f"actions N {north} E {east} S {south} W {west} "
            f"risk {risky_states(self.environment, policy)}"
        )
        lines.append("basins")
        lines.extend(symbol_grid(world, basin_symbols(self.environment, policy, limit)))
        if learner is not None:
            digits = [
                str(len(str(total))) if total > 0 else "0" for total in learner.state_visits()
            ]
            lines.append("visits")
            lines.extend(symbol_grid(world, digits))
        return lines

    def policies_report(self):
        parts = [
            self.policy_part("value_iteration", self.optimal_policy, None),
            self.policy_part("policy_iteration", self.iteration_policy, None),
        ]
        for learner in self.learners:
            parts.append(self.policy_part(learner.method, learner.policy(), learner))
        return join_parts(parts)

    def q_table(self):
        lines = ["method,row,col,action,value,visits"]
        lines.extend(q_table_rows(self.world, "value_iteration", self.optimal_q, None))
        for learner in self.learners:
            lines.extend(
                q_table_rows(self.world, learner.method, learner.q_values, learner.visits)
            )
        return lines

    def learning_curves(self):
        size = self.settings.block_size
        lines = [
            "method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage"
        ]
        for learner in self.learners:
            for number, (agree, error, coverage) in enumerate(learner.blocks, 1):
                episodes = learner.block_episodes(number)
                goals, pits, timeouts = ending_counts([episode.ending for episode in episodes])
                fields = [
                    learner.method, str(number),
                    average_text(sum(episode.total for episode in episodes), size),
                    average_text(sum(episode.steps for episode in episodes), size),
                    str(goals), str(pits), str(timeouts),
                    str(agree), fixed_text(error), str(coverage),
                ]
                lines.append(",".join(fields))
        return lines

    def summary_part(self):
        settings = self.settings
        return [
            f"summary states {len(self.world.states)} "
            f"start {cell_text(self.world, self.world.start)} "
            f"rollouts {settings.rollouts} step_limit {settings.step_limit}"
        ]

    def policy_values_part(self):
        start = self.world.start_state
        lines = ["policies", "policy agree optimal_actions value_start sweeps max_gap at"]
        for name, evaluation in zip(POLICY_NAMES, self.evaluations):
            lines.append(
                f"{name} {evaluation.agree} {evaluation.optimal_actions} "
                f"{fixed_text(evaluation.values[start])} {evaluation.sweeps} "
                f"{fixed_text(evaluation.max_gap)} {self.state_text(evaluation.max_gap_state)}"
            )
        return lines

    def improvement_part(self):
        lines = ["improvement", "policy changed value_start agree"]
        for name, evaluation in zip(POLICY_NAMES, self.evaluations):
            lines.append(
                f"{name} {evaluation.improved_changes} "
                f"{fixed_text(evaluation.improved_start)} {evaluation.improved_agree}"
            )
        return lines

    def absorption_part(self):
        lines = ["absorption", "policy p_goal p_pit p_timeout expected_steps"]
        for name, evaluation in zip(POLICY_NAMES, self.evaluations):
            goal, pit, expected = evaluation.absorption
            timeout = ABSORPTION_UNIT - goal - pit
            fields = [fixed_text(value // 10000) for value in (goal, pit, timeout, expected)]
            lines.append(" ".join([name] + fields))
        return lines

    def behaviour_part(self):
        settings = self.settings
        epsilon = schedule_value(settings.epsilon_schedule, settings.episodes)
        lines = ["behaviour", "method epsilon value_start sweeps"]
        for learner in self.learners:
            value, sweeps = behaviour_value(
                self.environment, learner.policy(), epsilon, settings.gamma, settings.theta
            )
            lines.append(f"{learner.method} {epsilon} {fixed_text(value)} {sweeps}")
        return lines

    def q_errors_part(self):
        state_count = len(self.world.states)
        lines = ["q_errors", "method mean_abs max_abs at unvisited tied"]
        for learner in self.learners:
            errors = value_errors(learner.q_values, self.optimal_values)
            largest = max(errors)
            unvisited = sum(total == 0 for total in learner.state_visits())
            tied = sum(row.count(max(row)) > 1 for row in learner.q_values)
            lines.append(
                f"{learner.method} {fixed_text(sum(errors) // state_count)} "
                f"{fixed_text(largest)} {self.state_text(errors.index(largest))} "
                f"{unvisited} {tied}"
            )
        return lines

    def q_action_errors_part(self):
        lines = ["q_action_errors", "method N E S W"]
        for learner in self.learners:
            fields = [learner.method]
            for action in range(4):
                total = 0
                count = 0
                for state, row in enumerate(learner.q_values):
                    if learner.visits[state][action] > 0:
                        total += abs(row[action] - self.optimal_q[state][action])
                        count += 1
                fields.append(fixed_text(total // count) if count > 0 else "-")
            lines.append(" ".join(fields))
        return lines

    def rollouts_part(self):
        count = self.settings.rollouts
        lines = [
            "rollouts",
            "policy mean_return mean_discounted mean_steps goals pits timeouts min median max",
        ]
        for name, evaluation in zip(POLICY_NAMES, self.evaluations):
            summary = evaluation.rollouts
            returns = sorted(summary.returns)
            goals, pits, timeouts = ending_counts(summary.endings)
            lines.append(
                f"{name} {average_text(sum(summary.returns), count)} "
                f"{fixed_text(sum(summary.discounted) // count)} "
                f"{average_text(sum(summary.steps), count)} {goals} {pits} {timeouts} "
                f"{returns[0]} {returns[(count + 1) // 2 - 1]} {returns[-1]}"
            )
        return lines

    def terminals_part(self):
        lines = ["terminals", "policy " + cells_text(self.world, self.world.terminals)]
        for name, evaluation in zip(POLICY_NAMES, self.evaluations):
            counts = [str(count) for count in evaluation.rollouts.terminal_counts]
            lines.append(" ".join([name] + counts))
        return lines

    def agreement_part(self):
        lines = ["agreement", "policy " + " ".join(POLICY_NAMES)]
        for name, policy in zip(POLICY_NAMES, self.policies):
            counts = [str(count_agreements(policy, other)) for other in self.policies]
            lines.append(" ".join([name] + counts))
        return lines

    def training_part(self):
        settings = self.settings
        size = settings.block_size
        optimal_total = sum(self.evaluations[0].rollouts.returns)
        lines = [
            "training",
            "method steps goals pits timeouts best_block best_mean last_mean reach",
        ]
        for learner in self.learners:
            goals, pits, timeouts = ending_counts([episode.ending for episode in learner.episodes])
            steps = sum(episode.steps for episode in learner.episodes)
            totals = learner.block_returns()
            best = totals.index(max(totals))
            reach = "-"
            for number, total in enumerate(totals, 1):
                if 10 * settings.rollouts * total >= 9 * size * optimal_total:
                    reach = str(number)
                    break
            lines.append(
                f"{learner.method} {steps} {goals} {pits} {timeouts} {best + 1} "
                f"{average_text(totals[best], size)} {average_text(totals[-1], size)} {reach}"
            )
        return lines

    def visited_part(self):
        lines = ["visited"]
        for learner in self.learners:
            totals = learner.state_visits()
            order = sorted(range(len(totals)), key=lambda state: (-totals[state], state))
            entries = [f"{self.state_text(state)}:{totals[state]}" for state in order[:3]]
            lines.append(" ".join([learner.method] + entries))
        return lines

    def last_episodes_part(self):
        lines = ["last_episodes"]
        for learner in self.learners:
            episode = learner.episodes[-1]
            lines.append(
                f"{learner.method} return {episode.total} steps {episode.steps} "
                f"end {episode.ending} {cells_text(self.world, episode.cells)}"
            )
        return lines

    def phases_part(self):
        settings = self.settings
        lines = ["phases"]
        for learner in self.learners:
            for first, last in phase_ranges(settings):
                episodes = learner.episodes[first - 1:last]
                count = len(episodes)
                alpha = schedule_value(settings.alpha_schedule, first)
                epsilon = schedule_value(settings.epsilon_schedule, first)
                total = sum(episode.total for episode in episodes)
                steps = sum(episode.steps for episode in episodes)
                goals = sum(episode.ending == "goal" for episode in episodes)
                lines.append(
                    f"{learner.method} {first}-{last} alpha {alpha} epsilon {epsilon} "
                    f"mean_return {average_text(total, count)} "
                    f"mean_steps {average_text(steps, count)} goals {goals}"
                )
        return lines

    def evaluation_report(self):
        return join_parts([
            self.summary_part(),
            self.policy_values_part(),
            self.improvement_part(),
            self.absorption_part(),
            self.behaviour_part(),
            self.q_errors_part(),
            self.q_action_errors_part(),
            self.rollouts_part(),
            self.terminals_part(),
            self.agreement_part(),
            self.training_part(),
            self.visited_part(),
            self.last_episodes_part(),
            self.phases_part(),
        ])


def main():
    world = read_world(os.path.join(INPUT_DIRECTORY, "world.txt"))
    settings = Settings(os.path.join(INPUT_DIRECTORY, "params.txt"))
    experiment = Experiment(world, settings)
    os.makedirs(OUTPUT_DIRECTORY, exist_ok=True)
    outputs = (
        ("values.txt", experiment.values_report()),
        ("policies.txt", experiment.policies_report()),
        ("q_tables.csv", experiment.q_table()),
        ("learning_curves.csv", experiment.learning_curves()),
        ("evaluation.txt", experiment.evaluation_report()),
    )
    for name, lines in outputs:
        write_lines(os.path.join(OUTPUT_DIRECTORY, name), lines)


if __name__ == "__main__":
    main()
