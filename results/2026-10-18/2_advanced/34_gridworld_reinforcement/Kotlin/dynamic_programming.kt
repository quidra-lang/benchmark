import kotlin.math.abs
object DynamicProgramming {
    data class Iteration(val values: LongArray, val changes: List<Long>)
    data class Evaluation(val values: LongArray, val sweeps: Int)
    data class Round(val sweeps: Int, val changes: Int, val value: Long)
    data class PolicyIteration(val policy: IntArray, val values: LongArray, val rounds: List<Round>)
    fun floor(value: Long, divisor: Long) = Math.floorDiv(value,divisor)
    fun first(values: LongArray): Int {
        var best = 0;
        for (a in 1 until values.size) if (values[a] > values[best]) best = a;
        return best
    }
    fun bellman(model: Environment.Model, values: LongArray, x: Int, action: Int, gamma: Int): Long {
        var sum = 0L;
        for (transition in model.transitions[x][action]) {
            val y = transition.cell;
            sum += transition.weight * (10000 * model.world.rewards[y] + if (model.world.terminal(y)) 0L else floor(gamma * values[y],100))
        };
        return floor(sum,model.q.toLong())
    }
    fun actions(model: Environment.Model, values: LongArray, x: Int, gamma: Int) = LongArray(4) {
        bellman(model,values,x,it,gamma)
    }
    fun policy(model: Environment.Model, values: LongArray, gamma: Int): IntArray {
        val result = IntArray(model.world.size);
        for (x in model.world.states) result[x] = first(actions(model,values,x,gamma));
        return result
    }
    fun iterate(model: Environment.Model, gamma: Int, theta: Long, inPlace: Boolean): Iteration {
        var values = LongArray(model.world.size);
        val changes = mutableListOf<Long>();
        while (true) {
            val next = if (inPlace) values else values.copyOf();
            var delta = 0L;
            for (x in model.world.states) {
                val row = actions(model,values,x,gamma);
                val v = row[first(row)];
                delta = maxOf(delta,abs(v - values[x]));
                next[x] = v
            };
            values = next;
            changes.add(delta);
            if (delta <= theta) return Iteration(values,changes)
        }
    }
    fun evaluate(model: Environment.Model, policy: IntArray, gamma: Int, theta: Long, initial: LongArray): Evaluation {
        val values = initial.copyOf();
        var sweeps = 0;
        while (true) {
            var delta = 0L;
            for (x in model.world.states) {
                val v = bellman(model,values,x,policy[x],gamma);
                delta = maxOf(delta,abs(v - values[x]));
                values[x] = v
            };
            sweeps++;
            if (delta <= theta) return Evaluation(values,sweeps)
        }
    }
    fun policyIteration(model: Environment.Model, gamma: Int, theta: Long): PolicyIteration {
        var currentPolicy = IntArray(model.world.size);
        var values = LongArray(model.world.size);
        val rounds = mutableListOf<Round>();
        while (true) {
            val evaluation = evaluate(model,currentPolicy,gamma,theta,values);
            values = evaluation.values;
            val next = policy(model,values,gamma);
            val changes = model.world.states.count {
                next[it] != currentPolicy[it]
            };
            rounds.add(Round(evaluation.sweeps,changes,values[model.world.start]));
            currentPolicy = next;
            if (changes == 0) return PolicyIteration(currentPolicy,values,rounds)
        }
    }
}
