import Foundation

enum Method: String, CaseIterable {
    case mc
    case sarsa
    case qLearning = "q_learning"
    case expectedSarsa = "expected_sarsa"
    case dynaQ = "dyna_q"
}

enum Ending: String, CaseIterable {
    case goal
    case pit
    case timeout
}

let policyNames = ["value_iteration", "policy_iteration"] + Method.allCases.map { $0.rawValue }
let absorptionUnit = 100_000_000

struct ScheduleEntry {
    let start: Int
    let value: Int
}

struct Settings {
    let gamma: Int
    let stepReward: Int
    let slipTotal: Int
    let floorSlip: Int
    let iceSlip: Int
    let theta: Int
    let gammaSweep: [Int]
    let slipSweep: [(Int, Int)]
    let episodes: Int
    let stepLimit: Int
    let blockSize: Int
    let alpha: [ScheduleEntry]
    let epsilon: [ScheduleEntry]
    let planningSteps: Int
    let seed: Int
    let rollouts: Int
    let rolloutSeed: Int

    init(_ path: String) throws {
        let text = try String(contentsOfFile: path, encoding: .ascii)
        let fields = Dictionary(uniqueKeysWithValues: text.split(separator: "\n").map { line in
            let parts = line.split(separator: " ")
            return (String(parts[0]), parts.dropFirst().map { Int($0)! })
        })
        func integer(_ name: String) -> Int { fields[name]![0] }
        func schedule(_ name: String) -> [ScheduleEntry] {
            let values = fields[name]!
            return stride(from: 0, to: values.count, by: 2).map {
                ScheduleEntry(start: values[$0], value: values[$0 + 1])
            }
        }
        gamma = integer("GAMMA")
        stepReward = integer("STEP_REWARD")
        slipTotal = fields["SLIP"]![0]
        floorSlip = fields["SLIP"]![1]
        iceSlip = fields["SLIP"]![2]
        theta = integer("THETA")
        gammaSweep = fields["GAMMA_SWEEP"]!
        let slips = fields["SLIP_SWEEP"]!
        slipSweep = stride(from: 0, to: slips.count, by: 2).map { (slips[$0], slips[$0 + 1]) }
        episodes = integer("EPISODES")
        stepLimit = integer("STEP_LIMIT")
        blockSize = integer("BLOCK_SIZE")
        alpha = schedule("ALPHA")
        epsilon = schedule("EPSILON")
        planningSteps = integer("PLANNING_STEPS")
        seed = integer("SEED")
        rollouts = integer("ROLLOUTS")
        rolloutSeed = integer("ROLLOUT_SEED")
    }
}

func scheduleValue(_ schedule: [ScheduleEntry], _ episode: Int) -> Int {
    schedule.last { $0.start <= episode }!.value
}

func agreements(_ first: [Int], _ second: [Int]) -> Int {
    first.indices.filter { first[$0] == second[$0] }.count
}

func endingCounts<S: Sequence>(_ endings: S) -> [Int] where S.Element == Ending {
    let values = Array(endings)
    return Ending.allCases.map { ending in values.filter { $0 == ending }.count }
}

struct Episode {
    var total = 0
    var steps = 0
    var ending = Ending.timeout
    var cells: [Int]
}

struct BlockRecord {
    let agree: Int
    let error: Int
    let coverage: Int
}

final class Learner {
    let method: Method
    let environment: Environment
    let settings: Settings
    let generator: RandomGenerator
    let model: DynaModel?
    let averages: ReturnAverages?
    var q: [[Int]]
    var visits: [[Int]]
    var episodes: [Episode] = []
    var blocks: [BlockRecord] = []
    var policy: [Int] { q.map(firstMaximum) }
    var stateVisits: [Int] { visits.map { $0.reduce(0, +) } }

    init(_ method: Method, _ environment: Environment, _ settings: Settings) {
        self.method = method
        self.environment = environment
        self.settings = settings
        generator = RandomGenerator(settings.seed)
        let count = environment.world.states.count
        let zeros = [[Int]](repeating: [Int](repeating: 0, count: 4), count: count)
        q = zeros
        visits = zeros
        model = method == .dynaQ ? DynaModel(count) : nil
        averages = method == .mc ? ReturnAverages(count) : nil
    }

    func learn(_ optimalValues: [Int], _ optimalPolicy: [Int]) {
        for number in 1...settings.episodes {
            let alpha = scheduleValue(settings.alpha, number)
            let epsilon = scheduleValue(settings.epsilon, number)
            episodes.append(play(alpha, epsilon))
            if number % settings.blockSize == 0 {
                let errors = q.indices.map { abs(q[$0].max()! - optimalValues[$0]) }
                blocks.append(BlockRecord(
                    agree: agreements(policy, optimalPolicy), error: floorDivide(errors.reduce(0, +), errors.count),
                    coverage: stateVisits.filter { $0 > 0 }.count
                ))
            }
        }
    }

    func play(_ alpha: Int, _ epsilon: Int) -> Episode {
        let world = environment.world
        var state = world.startState
        var episode = Episode(cells: [world.start])
        var history: [EpisodeStep] = []
        var action = method == .sarsa ? choose(generator, q[state], epsilon) : 0
        while episode.steps < settings.stepLimit {
            if method != .sarsa { action = choose(generator, q[state], epsilon) }
            let (cell, reward) = environment.step(generator, state, action)
            visits[state][action] += 1
            episode.total += reward
            episode.steps += 1
            episode.cells.append(cell)
            let next = world.stateIndex[cell]
            if method == .mc {
                history.append(EpisodeStep(state: state, action: action, reward: reward))
            } else if method == .sarsa {
                let nextAction = next.map { choose(generator, q[$0], epsilon) } ?? action
                let nextValue = next.map { q[$0][nextAction] } ?? 0
                let target = tdTarget(reward, next == nil, nextValue, settings.gamma)
                tdUpdate(&q, state, action, target, alpha)
                action = nextAction
            } else {
                let nextValue = next.map { method == .expectedSarsa ? expectedValue(q[$0], epsilon) : q[$0].max()! } ?? 0
                let target = tdTarget(reward, next == nil, nextValue, settings.gamma)
                tdUpdate(&q, state, action, target, alpha)
                if let model {
                    model.record(state, action, reward, next)
                    model.plan(generator, &q, settings.gamma, alpha, settings.planningSteps)
                }
            }
            if let next {
                state = next
            } else {
                episode.ending = world.kinds[cell] == "G" ? .goal : .pit
                break
            }
        }
        if let averages { averages.update(&q, history, settings.gamma) }
        return episode
    }

    func blockEpisodes(_ number: Int) -> ArraySlice<Episode> {
        episodes[(number * settings.blockSize)..<((number + 1) * settings.blockSize)]
    }

    var blockReturns: [Int] {
        blocks.indices.map { blockEpisodes($0).reduce(0) { $0 + $1.total } }
    }
}

struct NominalPath {
    let ending: String
    let cells: [Int]
    var steps: Int { cells.count - 1 }
}

func nominalPath(_ environment: Environment, _ policy: [Int], _ origin: Int, _ limit: Int) -> NominalPath {
    let world = environment.world
    var cells = [origin]
    while true {
        let state = world.stateIndex[cells.last!]!
        let target = environment.moves[state][policy[state]]
        let repeated = cells.contains(target)
        cells.append(target)
        if world.isTerminal(target) { return NominalPath(ending: world.terminalName(target), cells: cells) }
        if repeated { return NominalPath(ending: "loop", cells: cells) }
        if cells.count - 1 == limit { return NominalPath(ending: "limit", cells: cells) }
    }
}

func distances(_ environment: Environment) -> [Int?] {
    let world = environment.world
    var result = [Int?](repeating: nil, count: world.kinds.count)
    result[world.start] = 0
    var queue = [world.start]
    var front = 0
    while front < queue.count {
        let cell = queue[front]
        front += 1
        for transitions in environment.transitions[world.stateIndex[cell]!] {
            for transition in transitions where result[transition.cell] == nil {
                result[transition.cell] = result[cell]! + 1
                if !world.isTerminal(transition.cell) { queue.append(transition.cell) }
            }
        }
    }
    return result
}

struct Absorption {
    let goal: Int
    let pit: Int
    let expected: Int
}

func computeAbsorption(_ environment: Environment, _ policy: [Int], _ limit: Int) -> Absorption {
    let world = environment.world
    var goal = [Int](repeating: 0, count: policy.count)
    var pit = goal
    var expected = goal
    for _ in 0..<limit {
        var nextGoal: [Int] = []
        var nextPit: [Int] = []
        var nextExpected: [Int] = []
        for (state, action) in policy.enumerated() {
            var goalTotal = 0
            var pitTotal = 0
            var stepTotal = 0
            for transition in environment.transitions[state][action] {
                let cell = transition.cell
                let numerator = transition.numerator
                if let target = world.stateIndex[cell] {
                    goalTotal += numerator * goal[target]
                    pitTotal += numerator * pit[target]
                    stepTotal += numerator * expected[target]
                } else if world.kinds[cell] == "G" {
                    goalTotal += numerator * absorptionUnit
                } else {
                    pitTotal += numerator * absorptionUnit
                }
            }
            nextGoal.append(goalTotal / environment.slipTotal)
            nextPit.append(pitTotal / environment.slipTotal)
            nextExpected.append(absorptionUnit + stepTotal / environment.slipTotal)
        }
        goal = nextGoal
        pit = nextPit
        expected = nextExpected
    }
    return Absorption(goal: goal[world.startState], pit: pit[world.startState], expected: expected[world.startState])
}

func behaviourValue(
    _ environment: Environment, _ policy: [Int], _ epsilon: Int, _ gamma: Int, _ theta: Int
) -> (Int, Int) {
    var values = [Int](repeating: 0, count: policy.count)
    var sweeps = 0
    while true {
        sweeps += 1
        var delta = 0
        for (state, chosen) in policy.enumerated() {
            let backups = actionValues(environment, values, gamma, state)
            let total = backups.enumerated().reduce(0) { sum, pair in
                let weight = pair.offset == chosen ? epsilon + 4 * (1000 - epsilon) : epsilon
                return sum + weight * pair.element
            }
            let value = floorDivide(total, 4000)
            delta = max(delta, abs(value - values[state]))
            values[state] = value
        }
        if delta <= theta { return (values[environment.world.startState], sweeps) }
    }
}

struct RolloutSummary {
    var returns: [Int] = []
    var discounted: [Int] = []
    var steps: [Int] = []
    var endings: [Ending] = []
    var terminalCounts: [Int]
}

func performRollouts(_ environment: Environment, _ policy: [Int], _ settings: Settings) -> RolloutSummary {
    let world = environment.world
    let generator = RandomGenerator(settings.rolloutSeed)
    var summary = RolloutSummary(terminalCounts: [Int](repeating: 0, count: world.terminals.count))
    for _ in 0..<settings.rollouts {
        var state = world.startState
        var rewards: [Int] = []
        var ending = Ending.timeout
        for _ in 0..<settings.stepLimit {
            let (cell, reward) = environment.step(generator, state, policy[state])
            rewards.append(reward)
            if let next = world.stateIndex[cell] {
                state = next
            } else {
                ending = world.kinds[cell] == "G" ? .goal : .pit
                summary.terminalCounts[world.terminalIndex[cell]!] += 1
                break
            }
        }
        summary.returns.append(rewards.reduce(0, +))
        summary.discounted.append(discountedReturn(rewards, settings.gamma))
        summary.steps.append(rewards.count)
        summary.endings.append(ending)
    }
    return summary
}

struct PolicyEvaluation {
    let values: [Int]
    let sweeps: Int
    let agree: Int
    let optimalActions: Int
    let maxGap: Int
    let gapState: Int
    let improvedChanges: Int
    let improvedStart: Int
    let improvedAgree: Int
    let absorption: Absorption
    let rollouts: RolloutSummary

    init(
        _ environment: Environment, _ settings: Settings, _ policy: [Int],
        _ optimalValues: [Int], _ optimalPolicy: [Int], _ optimalActions: [[Int]]
    ) {
        let zeros = [Int](repeating: 0, count: policy.count)
        let (values, sweeps) = evaluatePolicy(environment, policy, zeros, settings.gamma, settings.theta)
        let gaps = values.indices.map { optimalValues[$0] - values[$0] }
        let gapState = firstMaximum(gaps)
        let improved = greedyPolicy(environment, values, settings.gamma)
        let (improvedValues, _) = evaluatePolicy(environment, improved, zeros, settings.gamma, settings.theta)
        self.values = values
        self.sweeps = sweeps
        agree = agreements(policy, optimalPolicy)
        self.optimalActions = policy.indices.filter { optimalActions[$0].contains(policy[$0]) }.count
        maxGap = gaps[gapState]
        self.gapState = gapState
        improvedChanges = policy.count - agreements(improved, policy)
        improvedStart = improvedValues[environment.world.startState]
        improvedAgree = agreements(improved, optimalPolicy)
        absorption = computeAbsorption(environment, policy, settings.stepLimit)
        rollouts = performRollouts(environment, policy, settings)
    }
}

final class Experiment {
    let world: World
    let settings: Settings
    let environment: Environment
    let optimal: ValueIteration
    let optimalQ: [[Int]]
    let optimalPolicy: [Int]
    let optimalActions: [[Int]]
    let inPlaceSweeps: Int
    let iteration: PolicyIteration
    let learners: [Learner]
    let policies: [[Int]]
    let evaluations: [PolicyEvaluation]

    init(_ world: World, _ settings: Settings) {
        let environment = Environment(world, settings.stepReward, settings.slipTotal, settings.floorSlip, settings.iceSlip)
        let optimal = valueIteration(environment, settings.gamma, settings.theta)
        let optimalQ = world.states.indices.map { actionValues(environment, optimal.values, settings.gamma, $0) }
        let optimalPolicy = optimalQ.map(firstMaximum)
        let optimalActions = optimalQ.map { row in row.indices.filter { row[$0] == row.max()! } }
        let inPlaceSweeps = inPlaceValueIteration(environment, settings.gamma, settings.theta)
        let iteration = policyIteration(environment, settings.gamma, settings.theta)
        let learners = Method.allCases.map { method in
            let learner = Learner(method, environment, settings)
            learner.learn(optimal.values, optimalPolicy)
            return learner
        }
        let policies = [optimalPolicy, iteration.policy] + learners.map { $0.policy }
        let evaluations = policies.map {
            PolicyEvaluation(environment, settings, $0, optimal.values, optimalPolicy, optimalActions)
        }
        self.world = world
        self.settings = settings
        self.environment = environment
        self.optimal = optimal
        self.optimalQ = optimalQ
        self.optimalPolicy = optimalPolicy
        self.optimalActions = optimalActions
        self.inPlaceSweeps = inPlaceSweeps
        self.iteration = iteration
        self.learners = learners
        self.policies = policies
        self.evaluations = evaluations
    }

    func stateText(_ state: Int) -> String { cellText(world, world.states[state]) }

    func worldPart() -> [String] {
        let distance = distances(environment)
        let reachable = world.states.filter { distance[$0] != nil }.count
        let kinds = world.kinds
        var lines = [
            "world rows \(world.rows) cols \(world.cols) states \(world.states.count) "
                + "walls \(kinds.filter { $0 == "#" }.count) floor \(kinds.filter { $0 == "." || $0 == "S" }.count) "
                + "ice \(kinds.filter { $0 == "~" }.count) goals \(kinds.filter { $0 == "G" }.count) pits \(kinds.filter { $0 == "P" }.count)",
            "start \(cellText(world, world.start)) reachable \(reachable)"
        ]
        for (index, cell) in world.terminals.enumerated() {
            let steps = distance[cell].map(String.init) ?? "-"
            lines.append("terminal \(cellText(world, cell)) \(world.terminalName(cell)) reward \(world.terminalRewards[index]) distance \(steps)")
        }
        return lines
    }

    func tiesPart() -> [String] {
        let tied = optimalActions.indices.filter { optimalActions[$0].count > 1 }
        var lines = ["ties \(tied.count)"]
        for state in tied {
            let letters = String(optimalActions[state].map { actionLetters[$0] })
            lines.append("tie \(stateText(state)) \(letters)")
        }
        var pairs = 0
        var equal = 0
        var mirrored = 0
        let mirrors = [0, 3, 2, 1]
        for (state, cell) in world.states.enumerated() {
            let row = cell / world.cols
            let col = cell % world.cols
            let mirror = world.cols - 1 - col
            if col < mirror, let other = world.stateIndex[row * world.cols + mirror] {
                pairs += 1
                if optimal.values[state] == optimal.values[other] { equal += 1 }
                if optimalPolicy[other] == mirrors[optimalPolicy[state]] { mirrored += 1 }
            }
        }
        lines.append("symmetry pairs \(pairs) equal_values \(equal) mirrored_actions \(mirrored)")
        return lines
    }

    func comparisonPart() -> [String] {
        let count = world.states.count
        let differences = optimal.values.indices.map { abs(iteration.values[$0] - optimal.values[$0]) }
        let whereMax = firstMaximum(differences)
        let policyDifferences = count - agreements(iteration.policy, optimalPolicy)
        let sweeps = iteration.rounds.reduce(0) { $0 + $1.sweeps }
        return [
            "comparison policy_differences \(policyDifferences) max_value_difference \(fixedText(differences[whereMax])) at \(stateText(whereMax))",
            "backups value_iteration \(optimal.changes.count * count * 4) in_place_iterations \(inPlaceSweeps) "
                + "in_place \(inPlaceSweeps * count * 4) policy_iteration \(sweeps * count + iteration.rounds.count * count * 4)"
        ]
    }

    func sensitivityText(_ environment: Environment, _ gamma: Int) -> String {
        let fitted = valueIteration(environment, gamma, settings.theta)
        let policy = greedyPolicy(environment, fitted.values, gamma)
        let path = nominalPath(environment, policy, world.start, settings.stepLimit)
        return "iterations \(fitted.changes.count) value_start \(fixedText(fitted.values[world.startState])) "
            + "path \(path.ending) steps \(path.steps) last \(cellText(world, path.cells.last!)) "
            + "differences \(policy.count - agreements(policy, optimalPolicy))"
    }

    func valuesReport() -> [String] {
        var valueLines = [
            "value_iteration gamma \(settings.gamma) theta \(fixedText(settings.theta)) iterations \(optimal.changes.count)"
        ]
        for (index, change) in optimal.changes.enumerated() {
            valueLines.append("iteration \(index + 1) max_change \(fixedText(change))")
        }
        var iterationLines = ["policy_iteration rounds \(iteration.rounds.count)"]
        for (index, round) in iteration.rounds.enumerated() {
            iterationLines.append("round \(index + 1) sweeps \(round.sweeps) changed \(round.changed) value_start \(fixedText(round.startValue))")
        }
        let gammaLines = ["gamma_sweep"] + settings.gammaSweep.map {
            "gamma \($0) " + sensitivityText(environment, $0)
        }
        let slipLines = ["slip_sweep"] + settings.slipSweep.map { floor, ice in
            let changed = Environment(world, settings.stepReward, settings.slipTotal, floor, ice)
            return "slip \(floor) \(ice) " + sensitivityText(changed, settings.gamma)
        }
        return joinParts([
            worldPart(), valueLines, ["optimal_values"] + valueGrid(world, optimal.values),
            ["optimal_action_counts"] + symbolGrid(world, optimalActions.map { String($0.count) }),
            tiesPart(), iterationLines, ["policy_iteration_values"] + valueGrid(world, iteration.values),
            comparisonPart(), gammaLines, slipLines
        ])
    }

    func policiesReport() -> [String] {
        let parts = policies.enumerated().map { index, policy -> [String] in
            let path = nominalPath(environment, policy, world.start, settings.stepLimit)
            let counts = (0..<4).map { action in policy.filter { $0 == action }.count }
            let risk = policy.indices.filter { state in
                environment.transitions[state][policy[state]].contains { world.kinds[$0.cell] == "P" }
            }.count
            let basins = world.states.map { cell -> String in
                let path = nominalPath(environment, policy, cell, settings.stepLimit)
                if let terminal = world.terminalIndex[path.cells.last!] {
                    return String(UnicodeScalar(97 + terminal)!)
                }
                return "*"
            }
            var lines = [policyNames[index]] + policyGrid(world, policy) + [
                "path \(path.ending) steps \(path.steps) \(cellsText(world, path.cells))",
                "actions N \(counts[0]) E \(counts[1]) S \(counts[2]) W \(counts[3]) risk \(risk)", "basins"
            ] + symbolGrid(world, basins)
            if index >= 2 {
                let digits = learners[index - 2].stateVisits.map { $0 == 0 ? "0" : String(String($0).count) }
                lines += ["visits"] + symbolGrid(world, digits)
            }
            return lines
        }
        return joinParts(parts)
    }

    func qTable() -> [String] {
        var lines = ["method,row,col,action,value,visits"] + qTableRows(world, "value_iteration", optimalQ, nil)
        for learner in learners { lines += qTableRows(world, learner.method.rawValue, learner.q, learner.visits) }
        return lines
    }

    func learningCurves() -> [String] {
        var lines = ["method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage"]
        for learner in learners {
            for (index, block) in learner.blocks.enumerated() {
                let episodes = learner.blockEpisodes(index)
                let counts = endingCounts(episodes.map { $0.ending })
                let fields = [
                    learner.method.rawValue, String(index + 1),
                    averageText(episodes.reduce(0) { $0 + $1.total }, settings.blockSize),
                    averageText(episodes.reduce(0) { $0 + $1.steps }, settings.blockSize)
                ] + counts.map(String.init) + [String(block.agree), fixedText(block.error), String(block.coverage)]
                lines.append(fields.joined(separator: ","))
            }
        }
        return lines
    }
}

extension Experiment {
    func policyValuesPart() -> [String] {
        var lines = ["policies", "policy agree optimal_actions value_start sweeps max_gap at"]
        for (name, result) in zip(policyNames, evaluations) {
            lines.append(
                "\(name) \(result.agree) \(result.optimalActions) \(fixedText(result.values[world.startState])) "
                    + "\(result.sweeps) \(fixedText(result.maxGap)) \(stateText(result.gapState))"
            )
        }
        return lines
    }

    func improvementPart() -> [String] {
        ["improvement", "policy changed value_start agree"] + zip(policyNames, evaluations).map { name, result in
            "\(name) \(result.improvedChanges) \(fixedText(result.improvedStart)) \(result.improvedAgree)"
        }
    }

    func absorptionPart() -> [String] {
        ["absorption", "policy p_goal p_pit p_timeout expected_steps"] + zip(policyNames, evaluations).map { name, result in
            let a = result.absorption
            let values = [a.goal, a.pit, absorptionUnit - a.goal - a.pit, a.expected]
            return name + " " + values.map { fixedText(floorDivide($0, 10000)) }.joined(separator: " ")
        }
    }

    func behaviourPart() -> [String] {
        let epsilon = scheduleValue(settings.epsilon, settings.episodes)
        return ["behaviour", "method epsilon value_start sweeps"] + learners.map { learner in
            let (value, sweeps) = behaviourValue(environment, learner.policy, epsilon, settings.gamma, settings.theta)
            return "\(learner.method.rawValue) \(epsilon) \(fixedText(value)) \(sweeps)"
        }
    }

    func qErrorsPart() -> [String] {
        var lines = ["q_errors", "method mean_abs max_abs at unvisited tied"]
        for learner in learners {
            let errors = learner.q.indices.map { abs(learner.q[$0].max()! - optimal.values[$0]) }
            let largest = firstMaximum(errors)
            let unvisited = learner.stateVisits.filter { $0 == 0 }.count
            let tied = learner.q.filter { row in row.filter { $0 == row.max()! }.count > 1 }.count
            lines.append(
                "\(learner.method.rawValue) \(fixedText(floorDivide(errors.reduce(0, +), errors.count))) "
                    + "\(fixedText(errors[largest])) \(stateText(largest)) \(unvisited) \(tied)"
            )
        }
        return lines
    }

    func qActionErrorsPart() -> [String] {
        var lines = ["q_action_errors", "method N E S W"]
        for learner in learners {
            let fields = (0..<4).map { action -> String in
                let states = learner.q.indices.filter { learner.visits[$0][action] > 0 }
                if states.isEmpty { return "-" }
                let total = states.reduce(0) { $0 + abs(learner.q[$1][action] - optimalQ[$1][action]) }
                return fixedText(floorDivide(total, states.count))
            }
            lines.append(([learner.method.rawValue] + fields).joined(separator: " "))
        }
        return lines
    }

    func rolloutsPart() -> [String] {
        var lines = ["rollouts", "policy mean_return mean_discounted mean_steps goals pits timeouts min median max"]
        for (name, evaluation) in zip(policyNames, evaluations) {
            let result = evaluation.rollouts
            let returns = result.returns.sorted()
            let counts = endingCounts(result.endings)
            let fields = [
                name, averageText(result.returns.reduce(0, +), settings.rollouts),
                fixedText(floorDivide(result.discounted.reduce(0, +), settings.rollouts)),
                averageText(result.steps.reduce(0, +), settings.rollouts)
            ] + counts.map(String.init) + [
                String(returns[0]), String(returns[(settings.rollouts - 1) / 2]), String(returns.last!)
            ]
            lines.append(fields.joined(separator: " "))
        }
        return lines
    }

    func terminalsPart() -> [String] {
        ["terminals", "policy " + cellsText(world, world.terminals)] + zip(policyNames, evaluations).map { name, result in
            name + " " + result.rollouts.terminalCounts.map(String.init).joined(separator: " ")
        }
    }

    func agreementPart() -> [String] {
        ["agreement", "policy " + policyNames.joined(separator: " ")] + zip(policyNames, policies).map { name, policy in
            name + " " + policies.map { String(agreements(policy, $0)) }.joined(separator: " ")
        }
    }

    func trainingPart() -> [String] {
        let size = settings.blockSize
        let optimalTotal = evaluations[0].rollouts.returns.reduce(0, +)
        var lines = ["training", "method steps goals pits timeouts best_block best_mean last_mean reach"]
        for learner in learners {
            let counts = endingCounts(learner.episodes.map { $0.ending })
            let steps = learner.episodes.reduce(0) { $0 + $1.steps }
            let totals = learner.blockReturns
            let best = firstMaximum(totals)
            let reach = totals.firstIndex { 10 * settings.rollouts * $0 >= 9 * size * optimalTotal }
                .map { String($0 + 1) } ?? "-"
            let fields = [learner.method.rawValue, String(steps)] + counts.map(String.init) + [
                String(best + 1), averageText(totals[best], size), averageText(totals.last!, size), reach
            ]
            lines.append(fields.joined(separator: " "))
        }
        return lines
    }

    func visitedPart() -> [String] {
        ["visited"] + learners.map { learner in
            let totals = learner.stateVisits
            let order = totals.indices.sorted { totals[$0] == totals[$1] ? $0 < $1 : totals[$0] > totals[$1] }
            let entries = order.prefix(3).map { "\(stateText($0)):\(totals[$0])" }
            return ([learner.method.rawValue] + entries).joined(separator: " ")
        }
    }

    func lastEpisodesPart() -> [String] {
        ["last_episodes"] + learners.map { learner in
            let episode = learner.episodes.last!
            return "\(learner.method.rawValue) return \(episode.total) steps \(episode.steps) "
                + "end \(episode.ending.rawValue) \(cellsText(world, episode.cells))"
        }
    }

    func phasesPart() -> [String] {
        let starts = Set((settings.alpha + settings.epsilon).map { $0.start }).sorted()
        let lasts = starts.dropFirst().map { $0 - 1 } + [settings.episodes]
        var lines = ["phases"]
        for learner in learners {
            for (first, last) in zip(starts, lasts) {
                let episodes = learner.episodes[(first - 1)..<last]
                let total = episodes.reduce(0) { $0 + $1.total }
                let steps = episodes.reduce(0) { $0 + $1.steps }
                let goals = episodes.filter { $0.ending == .goal }.count
                lines.append(
                    "\(learner.method.rawValue) \(first)-\(last) alpha \(scheduleValue(settings.alpha, first)) "
                        + "epsilon \(scheduleValue(settings.epsilon, first)) mean_return \(averageText(total, episodes.count)) "
                        + "mean_steps \(averageText(steps, episodes.count)) goals \(goals)"
                )
            }
        }
        return lines
    }

    func evaluationReport() -> [String] {
        let summary = [
            "summary states \(world.states.count) start \(cellText(world, world.start)) "
                + "rollouts \(settings.rollouts) step_limit \(settings.stepLimit)"
        ]
        return joinParts([
            summary, policyValuesPart(), improvementPart(), absorptionPart(), behaviourPart(), qErrorsPart(),
            qActionErrorsPart(), rolloutsPart(), terminalsPart(), agreementPart(), trainingPart(),
            visitedPart(), lastEpisodesPart(), phasesPart()
        ])
    }
}

let world = try readWorld("input/world.txt")
let settings = try Settings("input/params.txt")
let experiment = Experiment(world, settings)
for (name, lines) in [
    ("values.txt", experiment.valuesReport()), ("policies.txt", experiment.policiesReport()),
    ("q_tables.csv", experiment.qTable()), ("learning_curves.csv", experiment.learningCurves()),
    ("evaluation.txt", experiment.evaluationReport())
] {
    try writeLines(name, lines)
}
