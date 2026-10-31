import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import java.util.ArrayDeque
import kotlin.math.abs
val methods = listOf("mc","sarsa","q_learning","expected_sarsa","dyna_q")
val policyNames = listOf("value_iteration","policy_iteration") + methods
class Settings {
    val entries = Files.readAllLines(Path.of("input/params.txt"),StandardCharsets.US_ASCII).associate {
        val parts = it.split(' ');
        parts[0] to parts.drop(1).map(String::toLong).toLongArray()
    }
    fun get(key: String) = entries.getValue(key)[0].toInt()
    fun values(key: String) = entries.getValue(key)
    fun schedule(key: String, episode: Int): Int {
        val values = values(key);
        var result = values[1].toInt();
        for (i in values.indices step 2) if (values[i] <= episode) result = values[i + 1].toInt();
        return result
    }
}
data class Episode(val total: Long, val steps: Int, val ending: Int)
data class Block(val total: Long, val steps: Long, val goals: Int, val pits: Int, val timeouts: Int, val agree: Int, val error: Long, val coverage: Int)
data class Route(val cells: List<Int>, val ending: String) {
    fun steps() = cells.size - 1;
    fun last() = cells.last()
}
class Learning(val name: String, size: Int) {
    val q = Array(size) {
        LongArray(4)
    };
    val visits = Array(size) {
        LongArray(4)
    };
    val episodes = mutableListOf<Episode>();
    val blocks = mutableListOf<Block>();
    var last = listOf<Int>();
    var policy = IntArray(size)
}
fun agree(world: Environment, first: IntArray, second: IntArray) = world.states.count {
    first[it] == second[it]
}
fun greedy(world: Environment, q: Array<LongArray>): IntArray {
    val result = IntArray(world.size);
    for (x in world.states) result[x] = DynamicProgramming.first(q[x]);
    return result
}
fun ending(world: Environment, x: Int) = when (world.cells[x]) {
    'G' -> 0;
    'P' -> 1;
    else -> 2
}
fun endingName(kind: Int) = listOf("goal","pit","timeout")[kind]
fun learn(name: String, model: Environment.Model, settings: Settings, optimal: LongArray, optimalPolicy: IntArray): Learning {
    val world = model.world;
    val gamma = settings.get("GAMMA");
    val limit = settings.get("STEP_LIMIT");
    val blockSize = settings.get("BLOCK_SIZE");
    val count = settings.get("EPISODES")
    val learning = Learning(name,world.size);
    val sums = Array(world.size) {
        LongArray(4)
    };
    val counts = Array(world.size) {
        LongArray(4)
    };
    val rng = Environment.Rng(settings.get("SEED").toLong());
    val dyna = TdLearning.Dyna(world.size)
    for (episode in 1..count) {
        val alpha = settings.schedule("ALPHA",episode);
        val epsilon = settings.schedule("EPSILON",episode);
        var x = world.start;
        var action = if (name == "sarsa") TdLearning.choose(learning.q,x,epsilon,rng) else 0
        var total = 0L;
        val records = mutableListOf<MonteCarlo.Step>();
        val cells = mutableListOf(x);
        var steps = 0
        while (steps < limit) {
            if (name != "sarsa") action = TdLearning.choose(learning.q,x,epsilon,rng)
            val y = model.step(x,action,rng);
            learning.visits[x][action]++;
            val reward = world.rewards[y];
            total += reward;
            steps++;
            cells.add(y)
            if (name == "mc") records.add(MonteCarlo.Step(x,action,reward))
            else {
                val nextAction = if (name == "sarsa" && !world.terminal(y)) TdLearning.choose(learning.q,y,epsilon,rng) else 0;
                val nextValue = if (world.terminal(y)) 0L else if (name == "sarsa") learning.q[y][nextAction] else TdLearning.next(learning.q[y],
                    epsilon,name == "expected_sarsa");
                TdLearning.update(learning.q,world,x,action,y,nextValue,gamma,alpha);
                if (name == "dyna_q") {
                    dyna.observe(x,action,y);
                    dyna.plan(learning.q,world,settings.get("PLANNING_STEPS"),gamma,alpha,rng)
                };
                action = nextAction
            }
            x = y;
            if (world.terminal(x)) break
        }
        if (name == "mc") MonteCarlo.update(learning.q,sums,counts,records,gamma)
        learning.episodes.add(Episode(total,steps,ending(world,x)));
        if (episode == count) learning.last = cells
        if (episode % blockSize == 0) {
            val block = learning.episodes.subList(episode - blockSize,episode);
            var error = 0L;
            var agreement = 0;
            var coverage = 0;
            for (state in world.states) {
                val best = DynamicProgramming.first(learning.q[state]);
                if (best == optimalPolicy[state]) agreement++;
                error += abs(learning.q[state][best] - optimal[state]);
                if (learning.visits[state].sum() > 0) coverage++
            };
            learning.blocks.add(Block(block.sumOf {
                it.total
            },block.sumOf {
                it.steps.toLong()
            },block.count {
                it.ending == 0
            },block.count {
                it.ending == 1
            },block.count {
                it.ending == 2
            },agreement,DynamicProgramming.floor(error,world.states.size.toLong()),coverage))
        }
    }
    learning.policy = greedy(world,learning.q);
    return learning
}
fun route(world: Environment, policy: IntArray, start: Int, limit: Int): Route {
    val cells = mutableListOf(start);
    val seen = mutableSetOf(start);
    var x = start;
    while (true) {
        val y = world.moves[x][policy[x]];
        val repeated = y in seen;
        cells.add(y);
        if (world.terminal(y)) return Route(cells,endingName(ending(world,y)));
        if (repeated) return Route(cells,"loop");
        if (cells.size - 1 >= limit) return Route(cells,"limit");
        seen.add(y);
        x = y
    }
}
fun cells(world: Environment, cells: List<Int>) = cells.joinToString(" ") {
    Report.cell(world,it)
}
fun distances(model: Environment.Model): IntArray {
    val world = model.world;
    val distance = IntArray(world.size) {
        -1
    };
    distance[world.start] = 0;
    val queue = ArrayDeque<Int>();
    queue.add(world.start);
    while (queue.isNotEmpty()) {
        val x = queue.removeFirst();
        if (world.terminal(x)) continue;
        for (a in 0..3) for (t in model.transitions[x][a]) {
            val y = t.cell;
            if (distance[y] < 0) {
                distance[y] = distance[x] + 1;
                queue.addLast(y)
            }
        }
    };
    return distance
}
fun absorption(model: Environment.Model, policy: IntArray, limit: Int): LongArray {
    val world = model.world;
    var goals = LongArray(world.size);
    var pits = LongArray(world.size);
    var steps = LongArray(world.size)
    repeat(limit) {
        val nextGoals = LongArray(world.size);
        val nextPits = LongArray(world.size);
        val nextSteps = LongArray(world.size);
        for (x in world.states) {
            var g = 0L;
            var p = 0L;
            var e = 0L;
            for (t in model.transitions[x][policy[x]]) {
                val y = t.cell;
                g += t.weight * if (world.cells[y] == 'G') 100000000L else if (world.terminal(y)) 0L else goals[y];
                p += t.weight * if (world.cells[y] == 'P') 100000000L else if (world.terminal(y)) 0L else pits[y];
                e += t.weight * if (world.terminal(y)) 0L else steps[y]
            };
            nextGoals[x] = g / model.q;
            nextPits[x] = p / model.q;
            nextSteps[x] = 100000000 + e / model.q
        };
        goals = nextGoals;
        pits = nextPits;
        steps = nextSteps
    }
    return longArrayOf(goals[world.start] / 10000,pits[world.start] / 10000,(100000000 - goals[world.start] - pits[world.start]) / 10000,
        steps[world.start] / 10000)
}
fun behaviour(model: Environment.Model, policy: IntArray, settings: Settings): DynamicProgramming.Evaluation {
    val world = model.world;
    val values = LongArray(world.size);
    var sweeps = 0;
    val epsilon = settings.schedule("EPSILON",settings.get("EPISODES"));
    while (true) {
        var delta = 0L;
        for (x in world.states) {
            var weighted = 0L;
            for (a in 0..3) weighted += (epsilon + if (a == policy[x]) 4L * (1000 - epsilon) else 0L) * DynamicProgramming.bellman(model,
                values,x,a,settings.get("GAMMA"));
            val v = DynamicProgramming.floor(weighted,4000);
            delta = maxOf(delta,abs(v - values[x]));
            values[x] = v
        };
        sweeps++;
        if (delta <= settings.values("THETA")[0]) return DynamicProgramming.Evaluation(values,sweeps)
    }
}
class Rollouts(count: Int) {
    var total = 0L;
    var discounted = 0L;
    var steps = 0L;
    val endings = IntArray(3);
    val terminals = IntArray(count);
    val returns = mutableListOf<Long>()
}
fun rollouts(model: Environment.Model, policy: IntArray, settings: Settings): Rollouts {
    val world = model.world;
    val rng = Environment.Rng(settings.get("ROLLOUT_SEED").toLong());
    val result = Rollouts(world.terminals.size);
    repeat(settings.get("ROLLOUTS")) {
        var x = world.start;
        var steps = 0;
        val rewards = mutableListOf<Long>();
        var total = 0L;
        while (steps < settings.get("STEP_LIMIT")) {
            x = model.step(x,policy[x],rng);
            rewards.add(world.rewards[x]);
            total += world.rewards[x];
            steps++;
            if (world.terminal(x)) break
        };
        result.total += total;
        result.discounted += MonteCarlo.discounted(rewards,settings.get("GAMMA"));
        result.steps += steps;
        result.endings[ending(world,x)]++;
        result.returns.add(total);
        for (j in world.terminals.indices) if (x == world.terminals[j]) result.terminals[j]++
    };
    result.returns.sort();
    return result
}
fun part(output: MutableList<String>, lines: List<String>) {
    if (output.isNotEmpty()) output.add("");
    output.addAll(lines)
}
fun maxIndex(world: Environment, values: LongArray): Int {
    var best = world.states[0];
    for (x in world.states) if (values[x] > values[best]) best = x;
    return best
}
fun valueLines(model: Environment.Model, settings: Settings, vi: DynamicProgramming.Iteration,
     inPlace: DynamicProgramming.Iteration, pi: DynamicProgramming.PolicyIteration, q: Array<LongArray>,
     optimalPolicy: IntArray, distance: IntArray): List<String> {
    val world = model.world;
    val output = mutableListOf<String>();
    var section = mutableListOf<String>();
    val counts = world.cells.toList().groupingBy {
        it
    }.eachCount()
    section.add("world rows ${world.height} cols ${world.width} states ${world.states.size} walls ${counts.getOrDefault('#',0)} floor ${counts.getOrDefault('.',0) + counts.getOrDefault('S',0)} ice ${counts.getOrDefault('~',0)} goals ${counts.getOrDefault('G',0)} pits ${counts.getOrDefault('P',0)}")
    section.add("start ${Report.cell(world,world.start)} reachable ${world.states.count { distance[it] >= 0 }}")
    for (x in world.terminals) section.add("terminal ${Report.cell(world,x)} ${endingName(ending(world,x))} reward ${world.rewards[x]} distance ${if (distance[x] < 0) "-" else distance[x].toString()}")
    part(output,section);
    section = mutableListOf("value_iteration gamma ${settings.get("GAMMA")} theta ${Report.fixed(settings.values("THETA")[0])} iterations ${vi.changes.size}")
    for (k in vi.changes.indices) section.add("iteration ${k + 1} max_change ${Report.fixed(vi.changes[k])}")
    part(output,section);
    part(output,listOf("optimal_values") + Report.grid(world,true) {
        Report.fixed(vi.values[it])
    })
    val optimalCounts = IntArray(world.size);
    val ties = mutableListOf<String>()
    for (x in world.states) {
        val actions = (0..3).filter {
            q[x][it] == q[x][optimalPolicy[x]]
        };
        optimalCounts[x] = actions.size;
        if (actions.size > 1) ties.add("tie ${Report.cell(world,x)} ${actions.joinToString("") { "NESW"[it].toString() }}")
    }
    part(output,listOf("optimal_action_counts") + Report.grid(world,false) {
        optimalCounts[it].toString()
    })
    section = mutableListOf("ties ${ties.size}");
    section.addAll(ties);
    var pairs = 0;
    var equal = 0;
    var mirrored = 0;
    val mirror = intArrayOf(0,3,2,1);
    val nonterminal = world.states.toSet()
    for (x in world.states) {
        val row = x / world.width;
        val column = x % world.width;
        val other = row * world.width + world.width - 1 - column;
        if (column < world.width - 1 - column && other in nonterminal) {
            pairs++;
            if (vi.values[x] == vi.values[other]) equal++;
            if (optimalPolicy[other] == mirror[optimalPolicy[x]]) mirrored++
        }
    }
    section.add("symmetry pairs $pairs equal_values $equal mirrored_actions $mirrored");
    part(output,section)
    section = mutableListOf("policy_iteration rounds ${pi.rounds.size}");
    for (i in pi.rounds.indices) {
        val round = pi.rounds[i];
        section.add("round ${i + 1} sweeps ${round.sweeps} changed ${round.changes} value_start ${Report.fixed(round.value)}")
    };
    part(output,section)
    part(output,listOf("policy_iteration_values") + Report.grid(world,true) {
        Report.fixed(pi.values[it])
    })
    val differences = LongArray(world.size);
    for (x in world.states) differences[x] = abs(pi.values[x] - vi.values[x]);
    val at = maxIndex(world,differences);
    val n = world.states.size.toLong();
    val evaluationSweeps = pi.rounds.sumOf {
        it.sweeps.toLong()
    }
    part(output,listOf("comparison policy_differences ${world.states.size - agree(world,pi.policy,optimalPolicy)} max_value_difference ${Report.fixed(differences[at])} at ${Report.cell(world,at)}",
        "backups value_iteration ${vi.changes.size * n * 4} in_place_iterations ${inPlace.changes.size} in_place ${inPlace.changes.size * n * 4} policy_iteration ${evaluationSweeps * n + pi.rounds.size * n * 4}"))
    part(output,listOf("gamma_sweep") + settings.values("GAMMA_SWEEP").map {
        sensitivity("gamma $it",model,settings,it.toInt(),optimalPolicy)
    })
    val slips = settings.values("SLIP_SWEEP");
    section = mutableListOf("slip_sweep");
    for (i in slips.indices step 2) {
        val changed = Environment.Model(world,model.q,slips[i].toInt(),slips[i + 1].toInt());
        section.add(sensitivity("slip ${slips[i]} ${slips[i + 1]}",changed,settings,settings.get("GAMMA"),optimalPolicy))
    };
    part(output,section);
    return output
}
fun sensitivity(prefix: String, model: Environment.Model, settings: Settings, gamma: Int, optimalPolicy: IntArray): String {
    val iteration = DynamicProgramming.iterate(model,gamma,settings.values("THETA")[0],false);
    val policy = DynamicProgramming.policy(model,iteration.values,gamma);
    val route = route(model.world,policy,model.world.start,settings.get("STEP_LIMIT"));
    return "$prefix iterations ${iteration.changes.size} value_start ${Report.fixed(iteration.values[model.world.start])} path ${route.ending} steps ${route.steps()} last ${Report.cell(model.world,route.last())} differences ${model.world.states.size - agree(model.world,policy,optimalPolicy)}"
}
fun policyLines(model: Environment.Model, settings: Settings, policies: List<IntArray>, learning: List<Learning>): List<String> {
    val world = model.world;
    val output = mutableListOf<String>();
    val limit = settings.get("STEP_LIMIT")
    for (i in policies.indices) {
        val policy = policies[i];
        val section = mutableListOf(policyNames[i]);
        section.addAll(Report.grid(world,false) {
            "^>v<"[policy[it]].toString()
        });
        val route = route(world,policy,world.start,limit);
        section.add("path ${route.ending} steps ${route.steps()} ${cells(world,route.cells)}");
        val counts = IntArray(4);
        var risk = 0
        for (x in world.states) {
            counts[policy[x]]++;
            if (model.transitions[x][policy[x]].any {
                world.cells[it.cell] == 'P'
            }) risk++
        }
        section.add("actions N ${counts[0]} E ${counts[1]} S ${counts[2]} W ${counts[3]} risk $risk");
        section.add("basins");
        section.addAll(Report.grid(world,false) {
            x -> val basin = route(world,policy,x,limit);
            if (!world.terminal(basin.last())) "*" else ('a' + world.terminals.indexOf(basin.last())).toString()
        })
        if (i >= 2) {
            val result = learning[i - 2];
            section.add("visits");
            section.addAll(Report.grid(world,false) {
                x -> val count = result.visits[x].sum();
                if (count == 0L) "0" else count.toString().length.toString()
            })
        };
        part(output,section)
    }
    return output
}
fun learningLines(settings: Settings, learning: List<Learning>): List<String> {
    val output = mutableListOf("method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage");
    val count = settings.get("BLOCK_SIZE").toLong();
    for (result in learning) for (i in result.blocks.indices) {
        val b = result.blocks[i];
        output.add("${result.name},${i + 1},${Report.average(b.total,count)},${Report.average(b.steps,count)},${b.goals},${b.pits},${b.timeouts},${b.agree},${Report.fixed(b.error)},${b.coverage}")
    };
    return output
}
fun evaluationLines(model: Environment.Model, settings: Settings, vi: DynamicProgramming.Iteration,
     optimalQ: Array<LongArray>, optimalPolicy: IntArray, policies: List<IntArray>, learning: List<Learning>): List<String> {
    val world = model.world;
    val output = mutableListOf<String>();
    part(output,listOf("summary states ${world.states.size} start ${Report.cell(world,world.start)} rollouts ${settings.get("ROLLOUTS")} step_limit ${settings.get("STEP_LIMIT")}"))
    val policyValues = mutableListOf("policies","policy agree optimal_actions value_start sweeps max_gap at");
    val improvements = mutableListOf("improvement","policy changed value_start agree");
    val absorptions = mutableListOf("absorption","policy p_goal p_pit p_timeout expected_steps");
    val behaviours = mutableListOf("behaviour","method epsilon value_start sweeps");
    val qErrors = mutableListOf("q_errors","method mean_abs max_abs at unvisited tied");
    val actionErrors = mutableListOf("q_action_errors","method N E S W");
    val rolloutLines = mutableListOf("rollouts","policy mean_return mean_discounted mean_steps goals pits timeouts min median max");
    val terminalLines = mutableListOf("terminals","policy " + world.terminals.joinToString(" ") {
        Report.cell(world,it)
    });
    val agreementLines = mutableListOf("agreement","policy " + policyNames.joinToString(" "));
    val training = mutableListOf("training","method steps goals pits timeouts best_block best_mean last_mean reach");
    val visited = mutableListOf("visited");
    val lastEpisodes = mutableListOf("last_episodes");
    val phases = mutableListOf("phases")
    val rolloutResults = mutableListOf<Rollouts>();
    val m = settings.get("ROLLOUTS");
    val limit = settings.get("STEP_LIMIT");
    val gamma = settings.get("GAMMA");
    val theta = settings.values("THETA")[0]
    for (i in policies.indices) {
        val policy = policies[i];
        val name = policyNames[i];
        val evaluation = DynamicProgramming.evaluate(model,policy,gamma,theta,LongArray(world.size));
        val gaps = LongArray(world.size);
        var optimalActions = 0
        for (x in world.states) {
            gaps[x] = vi.values[x] - evaluation.values[x];
            if (optimalQ[x][policy[x]] == optimalQ[x][optimalPolicy[x]]) optimalActions++
        }
        var at = maxIndex(world,gaps);
        policyValues.add("$name ${agree(world,policy,optimalPolicy)} $optimalActions ${Report.fixed(evaluation.values[world.start])} ${evaluation.sweeps} ${Report.fixed(gaps[at])} ${Report.cell(world,at)}")
        val improved = DynamicProgramming.policy(model,evaluation.values,gamma);
        val improvedValue = DynamicProgramming.evaluate(model,improved,gamma,theta,LongArray(world.size));
        improvements.add("$name ${world.states.size - agree(world,policy,improved)} ${Report.fixed(improvedValue.values[world.start])} ${agree(world,improved,optimalPolicy)}")
        absorptions.add(name + absorption(model,policy,limit).joinToString("") {
            " ${Report.fixed(it)}"
        })
        if (i >= 2) {
            val result = learning[i - 2];
            val behaviour = behaviour(model,policy,settings);
            behaviours.add("$name ${settings.schedule("EPSILON",settings.get("EPISODES"))} ${Report.fixed(behaviour.values[world.start])} ${behaviour.sweeps}")
            val errors = LongArray(world.size);
            var total = 0L;
            var unvisited = 0;
            var tied = 0
            for (x in world.states) {
                val maximum = result.q[x][policy[x]];
                errors[x] = abs(maximum - vi.values[x]);
                total += errors[x];
                if (result.visits[x].sum() == 0L) unvisited++;
                if (result.q[x].count {
                    it == maximum
                }
                > 1) tied++
            }
            at = maxIndex(world,errors);
            qErrors.add("$name ${Report.fixed(DynamicProgramming.floor(total,world.states.size.toLong()))} ${Report.fixed(errors[at])} ${Report.cell(world,at)} $unvisited $tied")
            val actionValues = (0..3).map {
                a -> val selected = world.states.filter {
                    result.visits[it][a] > 0
                };
                if (selected.isEmpty()) "-" else Report.fixed(DynamicProgramming.floor(selected.sumOf {
                    abs(result.q[it][a] - optimalQ[it][a])
                },selected.size.toLong()))
            };
            actionErrors.add(name + " " + actionValues.joinToString(" "))
        }
        val rollouts = rollouts(model,policy,settings);
        rolloutResults.add(rollouts);
        rolloutLines.add("$name ${Report.average(rollouts.total,m.toLong())} ${Report.fixed(DynamicProgramming.floor(rollouts.discounted,m.toLong()))} ${Report.average(rollouts.steps,m.toLong())} ${rollouts.endings[0]} ${rollouts.endings[1]} ${rollouts.endings[2]} ${rollouts.returns.first()} ${rollouts.returns[(m - 1) / 2]} ${rollouts.returns.last()}")
        terminalLines.add(name + rollouts.terminals.joinToString("") {
            " $it"
        });
        agreementLines.add(name + policies.joinToString("") {
            " ${agree(world,policy,it)}"
        })
    }
    val blockSize = settings.get("BLOCK_SIZE");
    val episodeCount = settings.get("EPISODES");
    val starts = listOf("ALPHA","EPSILON").flatMap {
        schedule -> settings.values(schedule).indices.step(2).map {
            settings.values(schedule)[it].toInt()
        }
    }.distinct().sorted()
    for (result in learning) {
        val steps = result.episodes.sumOf {
            it.steps.toLong()
        };
        val endings = IntArray(3);
        result.episodes.forEach {
            endings[it.ending]++
        };
        var best = 0;
        var reach = "-"
        for (j in result.blocks.indices) {
            if (result.blocks[j].total > result.blocks[best].total) best = j;
            if (reach == "-" && 10L * m * result.blocks[j].total >= 9L * blockSize * rolloutResults.first().total) reach = (j + 1).toString()
        }
        training.add("${result.name} $steps ${endings[0]} ${endings[1]} ${endings[2]} ${best + 1} ${Report.average(result.blocks[best].total,blockSize.toLong())} ${Report.average(result.blocks.last().total,blockSize.toLong())} $reach")
        val ordered = world.states.sortedWith(compareByDescending<Int> {
            result.visits[it].sum()
        }.thenBy {
            it
        });
        visited.add(result.name + ordered.take(3).joinToString("") {
            " ${Report.cell(world,it)}:${result.visits[it].sum()}"
        })
        val last = result.episodes.last();
        lastEpisodes.add("${result.name} return ${last.total} steps ${last.steps} end ${endingName(last.ending)} ${cells(world,result.last)}")
        for (i in starts.indices) {
            val start = starts[i];
            val end = if (i + 1 < starts.size) starts[i + 1] - 1 else episodeCount;
            val selected = result.episodes.subList(start - 1,end);
            phases.add("${result.name} $start-$end alpha ${settings.schedule("ALPHA",start)} epsilon ${settings.schedule("EPSILON",start)} mean_return ${Report.average(selected.sumOf { it.total },selected.size.toLong())} mean_steps ${Report.average(selected.sumOf { it.steps.toLong() },selected.size.toLong())} goals ${selected.count { it.ending == 0 }}")
        }
    }
    for (section in listOf(policyValues,improvements,absorptions,behaviours,qErrors,actionErrors,
        rolloutLines,terminalLines,agreementLines,training,visited,lastEpisodes,phases)) part(output,
        section)
    return output
}
fun main() {
    val settings = Settings();
    val world = Environment(settings.get("STEP_REWARD").toLong());
    val slip = settings.values("SLIP");
    val model = Environment.Model(world,slip[0].toInt(),slip[1].toInt(),slip[2].toInt());
    val gamma = settings.get("GAMMA");
    val theta = settings.values("THETA")[0]
    val vi = DynamicProgramming.iterate(model,gamma,theta,false);
    val inPlace = DynamicProgramming.iterate(model,gamma,theta,true);
    val pi = DynamicProgramming.policyIteration(model,gamma,theta);
    val optimalQ = Array(world.size) {
        LongArray(4)
    };
    for (x in world.states) optimalQ[x] = DynamicProgramming.actions(model,vi.values,x,gamma);
    val optimalPolicy = greedy(world,optimalQ)
    val learning = mutableListOf<Learning>();
    val policies = mutableListOf(optimalPolicy,pi.policy);
    for (method in methods) {
        val result = learn(method,model,settings,vi.values,optimalPolicy);
        learning.add(result);
        policies.add(result.policy)
    }
    val qLines = mutableListOf("method,row,col,action,value,visits");
    Report.qRows(qLines,"value_iteration",world,optimalQ,null);
    for (result in learning) Report.qRows(qLines,result.name,world,result.q,result.visits)
    Files.createDirectories(Path.of("output"));
    Report.write("values.txt",valueLines(model,settings,vi,inPlace,pi,optimalQ,optimalPolicy,distances(model)));
    Report.write("policies.txt",policyLines(model,settings,policies,learning));
    Report.write("q_tables.csv",qLines);
    Report.write("learning_curves.csv",learningLines(settings,learning));
    Report.write("evaluation.txt",evaluationLines(model,settings,vi,optimalQ,optimalPolicy,policies,learning))
}
