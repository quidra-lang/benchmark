object TdLearning {
    fun choose(q: Array<LongArray>, x: Int, epsilon: Int, rng: Environment.Rng) = if (rng.draw() % 1000 < epsilon) (rng.draw() % 4).toInt() else DynamicProgramming.first(q[x])
    fun next(row: LongArray, epsilon: Int, expected: Boolean): Long {
        val maximum = row[DynamicProgramming.first(row)];
        return if (expected) DynamicProgramming.floor(epsilon * row.sum() + 4L * (1000 - epsilon) * maximum,4000) else maximum
    }
    fun update(q: Array<LongArray>, world: Environment, x: Int, action: Int, y: Int, next: Long, gamma: Int, alpha: Int) {
        val target = 10000 * world.rewards[y] + if (world.terminal(y)) 0L else DynamicProgramming.floor(gamma * next,100);
        q[x][action] += DynamicProgramming.floor(alpha * (target - q[x][action]),100)
    }
    data class Pair(val cell: Int, val action: Int)
    class Dyna(size: Int) {
        val reached = Array(size) {
            IntArray(4)
        };
        val seen = Array(size) {
            BooleanArray(4)
        };
        val observed = mutableListOf<Pair>()
        fun observe(x: Int, action: Int, y: Int) {
            if (!seen[x][action]) {
                seen[x][action] = true;
                observed.add(Pair(x,action))
            };
            reached[x][action] = y
        }
        fun plan(q: Array<LongArray>, world: Environment, count: Int, gamma: Int, alpha: Int, rng: Environment.Rng) {
            repeat(count) {
                val pair = observed[(rng.draw() % observed.size).toInt()];
                val y = reached[pair.cell][pair.action];
                update(q,world,pair.cell,pair.action,y,if (world.terminal(y)) 0L else next(q[y],0,false),gamma,alpha)
            }
        }
    }
}
