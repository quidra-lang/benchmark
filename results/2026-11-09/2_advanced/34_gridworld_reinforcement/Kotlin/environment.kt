import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
class Environment(stepReward: Long) {
    class Rng(var state: Long) {
        fun draw(): Long {
            state = state * 48271 % 2147483647;
            return state
        }
    }
    data class Outcome(val cell: Int, val weight: Int)
    val height: Int;
    val width: Int;
    val size: Int;
    val start: Int;
    val cells: CharArray;
    val states: IntArray;
    val terminals: IntArray;
    val wind: IntArray;
    val rewards: LongArray;
    val moves: Array<IntArray>
    init {
        val lines = Files.readAllLines(Path.of("input/world.txt"),StandardCharsets.US_ASCII);
        height = lines[0].split(' ')[1].toInt();
        width = lines[1].split(' ')[1].toInt();
        size = height * width
        cells = CharArray(size);
        rewards = LongArray(size) {
            stepReward
        };
        wind = IntArray(width);
        moves = Array(size) {
            IntArray(4)
        }
        val active = mutableListOf<Int>();
        val ends = mutableListOf<Int>();
        var origin = -1
        for (r in 0 until height) for (c in 0 until width) {
            val x = r * width + c;
            cells[x] = lines[r + 2][c];
            if (terminal(x)) ends.add(x) else if (cells[x] != '#') active.add(x);
            if (cells[x] == 'S') origin = x
        }
        start = origin;
        states = active.toIntArray();
        terminals = ends.toIntArray();
        val winds = lines[height + 2].split(' ')[1];
        for (c in 0 until width) wind[c] = winds[c] - '0'
        val values = lines[height + 3].split(' ');
        for (i in terminals.indices) rewards[terminals[i]] = values[i + 1].toLong()
        val offsets = intArrayOf(-width,1,width,-1)
        for (x in states) for (action in 0..3) {
            var y = x + offsets[action];
            if (cells[y] == '#') y = x;
            if (!terminal(y)) for (i in 0 until wind[x % width]) {
                if (cells[y - width] == '#') break;
                y -= width;
                if (terminal(y)) break
            };
            moves[x][action] = y
        }
    }
    fun terminal(x: Int) = cells[x] == 'G' || cells[x] == 'P'
    class Model(val world: Environment, val q: Int, val floorSlip: Int, val iceSlip: Int) {
        val transitions: Array<Array<List<Outcome>>> = Array(world.size) {
            Array(4) {
                emptyList()
            }
        }
        init {
            for (x in world.states) for (a in 0..3) {
                val p = slip(x);
                val directions = intArrayOf(a,(a + 1) % 4,(a + 3) % 4);
                val weights = intArrayOf(q - 2 * p,p,p);
                transitions[x][a] = (0..2).filter {
                    weights[it] > 0
                }.map {
                    Outcome(world.moves[x][directions[it]],weights[it])
                }
            }
        }
        fun slip(x: Int) = if (world.cells[x] == '~') iceSlip else floorSlip
        fun step(x: Int, action: Int, rng: Rng): Int {
            val t = rng.draw() % q;
            val p = slip(x);
            val direction = if (t < q - 2 * p) action else if (t < q - p) (action + 1) % 4 else (action + 3) % 4;
            return world.moves[x][direction]
        }
    }
}
