import java.io.BufferedReader
import java.io.InputStreamReader

private const val FILES = "abcdefgh"
private const val RANKS = "12345678"
private const val INITIAL = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
private val rook = listOf(0 to 1, 0 to -1, -1 to 0, 1 to 0)
private val bishop = listOf(1 to 1, -1 to 1, 1 to -1, -1 to -1)
private val king = rook + bishop
private val knight = listOf(1 to 2, 2 to 1, 2 to -1, 1 to -2, -1 to -2, -2 to -1, -2 to 1, -1 to 2)

private data class Rule(
    val king: Int,
    val rook: Int,
    val target: Int,
    val rookTarget: Int,
    val path: List<Int>,
)

private val rules =
    mapOf(
        'K' to Rule(4, 7, 6, 5, listOf(5, 6)),
        'Q' to Rule(4, 0, 2, 3, listOf(1, 2, 3)),
        'k' to Rule(60, 63, 62, 61, listOf(61, 62)),
        'q' to Rule(60, 56, 58, 59, listOf(57, 58, 59)),
    )

private data class Move(val source: Int, val target: Int, val promotion: Char? = null)

private data class Record(val san: String, val uci: String, val captured: Char)

private fun fail(s: String): Nothing = throw IllegalArgumentException(s)

private fun color(p: Char) = if (p.isUpperCase()) 'w' else 'b'

private fun opposite(c: Char) = if (c == 'w') 'b' else 'w'

private fun colored(p: Char, c: Char) = if (c == 'w') p else p.lowercaseChar()

private fun step(c: Char) = if (c == 'w') 8 else -8

private fun square(s: String) =
    if (s.length == 2 && s[0] in 'a'..'h' && s[1] in '1'..'8') s[0] - 'a' + 8 * (s[1] - '1') else -1

private fun name(s: Int) = "${FILES[s%8]}${RANKS[s/8]}"

private fun number(s: String, lo: Int, hi: Int): Int {
    if (!Regex("0|[1-9][0-9]{0,8}").matches(s)) return -1
    val n = s.toInt()
    return if (n in lo..hi) n else -1
}

private fun shift(s: Int, dx: Int, dy: Int): Int {
    val x = s % 8 + dx
    val y = s / 8 + dy
    return if (x in 0..7 && y in 0..7) 8 * y + x else -1
}

private fun targets(b: CharArray, s: Int): List<Int> {
    val p = b[s]
    val kind = p.uppercaseChar()
    val result = mutableListOf<Int>()
    if (kind in "PNK") {
        val dirs =
            when (kind) {
                'P' ->
                    listOf(
                        -1 to if (color(p) == 'w') 1 else -1,
                        1 to if (color(p) == 'w') 1 else -1,
                    )
                'N' -> knight
                else -> king
            }
        for ((dx, dy) in dirs) {
            val t = shift(s, dx, dy)
            if (t >= 0) result.add(t)
        }
    } else {
        val dirs =
            when (kind) {
                'Q' -> king
                'R' -> rook
                else -> bishop
            }
        for ((dx, dy) in dirs) {
            var t = shift(s, dx, dy)
            while (t >= 0) {
                result.add(t)
                if (b[t] != '.') break
                t = shift(t, dx, dy)
            }
        }
    }
    return result
}

private fun attackers(b: CharArray, t: Int, c: Char) =
    (0..63).filter { b[it] != '.' && color(b[it]) == c && t in targets(b, it) }

private class Position(
    val board: CharArray,
    val side: Char,
    val rights: String,
    val ep: Int,
    val half: Int,
    val full: Int,
) {
    private var cached: List<Move>? = null

    fun check(c: Char = side) =
        attackers(board, board.indexOf(colored('K', c)), opposite(c)).isNotEmpty()

    fun castle(m: Move) =
        board[m.source].uppercaseChar() == 'K' && kotlin.math.abs(m.target - m.source) == 2

    fun enpassant(m: Move) =
        board[m.source].uppercaseChar() == 'P' &&
            m.source % 8 != m.target % 8 &&
            board[m.target] == '.'

    fun capture(m: Move) = board[m.target] != '.' || enpassant(m)

    fun captured(m: Move) =
        if (board[m.target] != '.') board[m.target].lowercaseChar()
        else if (enpassant(m)) 'p' else '-'

    fun play(m: Move): Position {
        val b = board.copyOf()
        val piece = b[m.source]
        val kind = piece.uppercaseChar()
        if (enpassant(m)) b[m.target - step(side)] = '.'
        if (castle(m)) {
            val r = rules.getValue(colored(if (m.target > m.source) 'K' else 'Q', side))
            b[r.rookTarget] = b[r.rook]
            b[r.rook] = '.'
        }
        b[m.target] = m.promotion?.let { colored(it, side) } ?: piece
        b[m.source] = '.'
        val rights = rights.filter {
            (kind != 'K' || color(it) != side) &&
                rules.getValue(it).rook != m.source &&
                rules.getValue(it).rook != m.target
        }
        return Position(
            b,
            opposite(side),
            rights,
            if (kind == 'P' && kotlin.math.abs(m.target - m.source) == 16) (m.source + m.target) / 2
            else -1,
            if (kind == 'P' || capture(m)) 0 else half + 1,
            full + if (side == 'b') 1 else 0,
        )
    }

    fun pseudo(): List<Move> {
        val result = mutableListOf<Move>()
        for (s in 0..63) {
            val p = board[s]
            if (p == '.' || color(p) != side) continue
            val pawn = p.uppercaseChar() == 'P'
            val a = mutableListOf<Int>()
            if (pawn) {
                val d = step(side)
                if (board[s + d] == '.') {
                    a.add(s + d)
                    if (s / 8 == (if (side == 'w') 1 else 6) && board[s + 2 * d] == '.')
                        a.add(s + 2 * d)
                }
                a.addAll(
                    targets(board, s).filter {
                        (board[it] != '.' && color(board[it]) != side) || it == ep
                    },
                )
            } else
                a.addAll(targets(board, s).filter { board[it] == '.' || color(board[it]) != side })
            for (t in a) if (pawn && t / 8 == (if (side == 'w') 7 else 0)) {
                for (promotion in "QRBN") result.add(Move(s, t, promotion))
            } else result.add(Move(s, t))
        }
        return result
    }

    fun castlingMove(kingside: Boolean): Move {
        val r = rules.getValue(colored(if (kingside) 'K' else 'Q', side))
        return Move(r.king, r.target)
    }

    fun castlingProblem(kingside: Boolean): String {
        val right = colored(if (kingside) 'K' else 'Q', side)
        val r = rules.getValue(right)
        if (right !in rights) return "no castling right"
        if (r.path.any { board[it] != '.' }) return "path blocked"
        if (check()) return "in check"
        if (attackers(board, r.rookTarget, opposite(side)).isNotEmpty()) return "through check"
        if (play(castlingMove(kingside)).check(side)) return "into check"
        return ""
    }

    fun legal(): List<Move> {
        cached?.let {
            return it
        }
        val a = pseudo().filter { !play(it).check(side) }.toMutableList()
        for (k in listOf(true, false)) if (castlingProblem(k).isEmpty()) a.add(castlingMove(k))
        cached = a
        return a
    }

    fun mark(m: Move): String {
        val q = play(m)
        return if (q.check()) if (q.legal().isEmpty()) "#" else "+" else ""
    }

    fun disambiguation(m: Move): String {
        val a =
            legal().filter {
                !castle(it) &&
                    it.target == m.target &&
                    it.source != m.source &&
                    board[it.source] == board[m.source]
            }
        return when {
            a.isEmpty() -> ""
            a.all { it.source % 8 != m.source % 8 } -> FILES[m.source % 8].toString()
            a.all { it.source / 8 != m.source / 8 } -> RANKS[m.source / 8].toString()
            else -> name(m.source)
        }
    }

    fun san(m: Move): String {
        val kind = board[m.source].uppercaseChar()
        val text =
            when {
                castle(m) -> if (m.target > m.source) "O-O" else "O-O-O"
                kind == 'P' ->
                    (if (capture(m)) "${FILES[m.source%8]}x" else "") +
                        name(m.target) +
                        (m.promotion?.let { "=$it" } ?: "")
                else -> kind + disambiguation(m) + (if (capture(m)) "x" else "") + name(m.target)
            }
        return text + mark(m)
    }

    fun key() =
        board.concatToString() +
            " $side $rights " +
            if (ep >= 0 && legal().any { enpassant(it) }) ep else -1

    fun state() =
        if (check()) if (legal().isEmpty()) "checkmate" else "check"
        else if (legal().isEmpty()) "stalemate" else "normal"

    fun insufficient(): Boolean {
        val a = (0..63).filter { board[it] != '.' && board[it].uppercaseChar() != 'K' }
        if (a.any { board[it].uppercaseChar() in "PRQ" }) return false
        return a.size <= 1 ||
            a.all { board[it].uppercaseChar() == 'B' } &&
                a.map { (it % 8 + it / 8) % 2 }.distinct().size == 1
    }

    fun pins(): List<Pair<Int, Int>> {
        val k = board.indexOf(colored('K', side))
        val a = mutableListOf<Pair<Int, Int>>()
        for ((dx, dy) in king) {
            var first = -1
            var t = shift(k, dx, dy)
            while (t >= 0) {
                val p = board[t]
                if (p != '.') {
                    if (first < 0) {
                        if (color(p) != side) break
                        first = t
                    } else {
                        if (
                            color(p) != side &&
                                (p.uppercaseChar() == 'Q' ||
                                    p.uppercaseChar() == if (dx == 0 || dy == 0) 'R' else 'B')
                        )
                            a.add(first to t)
                        break
                    }
                }
                t = shift(t, dx, dy)
            }
        }
        return a.sortedBy { it.first }
    }

    fun fen(): String {
        val rows =
            (7 downTo 0).map { r ->
                buildString {
                    var empty = 0
                    for (f in 0..7) {
                        val p = board[r * 8 + f]
                        if (p == '.') empty++
                        else {
                            if (empty > 0) append(empty)
                            empty = 0
                            append(p)
                        }
                    }
                    if (empty > 0) append(empty)
                }
            }
        return rows.joinToString("/") +
            " $side " +
            rights.ifEmpty { "-" } +
            " " +
            (if (ep < 0) "-" else name(ep)) +
            " $half $full"
    }
}

private fun parseFen(a: List<String>): Position {
    if (a.size != 6) fail("fields")
    val rows = a[0].split('/')
    if (rows.size != 8) fail("placement")
    val b = CharArray(64) { '.' }
    for ((i, row) in rows.withIndex()) {
        var f = 0
        var digit = false
        for (c in row) {
            if (c in '1'..'8') {
                if (digit) fail("placement")
                f += c - '0'
                digit = true
            } else {
                if (c !in "KQRBNPkqrbnp" || f >= 8) fail("placement")
                b[(7 - i) * 8 + f++] = c
                digit = false
            }
        }
        if (f != 8) fail("placement")
    }
    if (b.count { it == 'K' } != 1 || b.count { it == 'k' } != 1) fail("kings")
    if ((b.take(8) + b.takeLast(8)).any { it == 'P' || it == 'p' }) fail("pawns")
    if (a[1] != "w" && a[1] != "b") fail("side")
    val side = a[1][0]
    if (a[2] != "-" && (a[2].isEmpty() || !Regex("K?Q?k?q?").matches(a[2]))) fail("castling")
    val rights = if (a[2] == "-") "" else a[2]
    for (r in rights) {
        val rule = rules.getValue(r)
        if (b[rule.king] != colored('K', color(r)) || b[rule.rook] != colored('R', color(r)))
            fail("castling")
    }
    var ep = -1
    if (a[3] != "-") {
        ep = square(a[3])
        val d = step(side)
        if (
            ep < 0 ||
                ep / 8 != (if (side == 'w') 5 else 2) ||
                b[ep] != '.' ||
                b[ep + d] != '.' ||
                b[ep - d] != colored('P', opposite(side))
        )
            fail("en passant")
    }
    val half = number(a[4], 0, 999)
    val full = number(a[5], 1, 999)
    if (half < 0 || full < 0 || (ep >= 0 && half != 0)) fail("clocks")
    val p = Position(b, side, rights, ep, half, full)
    if (p.check(opposite(side))) fail("check")
    return p
}

private fun readSan(pos: Position, text: String): Move {
    val mark = if (text.last() in "+#") text.takeLast(1) else ""
    var body = if (mark.isEmpty()) text else text.dropLast(1)
    val castling = body == "O-O" || body == "O-O-O"
    var promotion: Char? = null
    var target = -1
    var capture = false
    var kind = 'P'
    var file = ""
    var rank = ""
    if (!castling) {
        if (body.length >= 2 && body[body.length - 2] == '=') {
            promotion = body.last()
            if (promotion !in "QRBN") fail("syntax")
            body = body.dropLast(2)
        }
        target = square(body.takeLast(2))
        if (target < 0) fail("syntax")
        body = body.dropLast(2)
        capture = body.endsWith('x')
        if (capture) body = body.dropLast(1)
        if (body.isNotEmpty() && body[0] in "KQRBN") {
            kind = body[0]
            val h = Regex("([a-h]?)([1-8]?)").matchEntire(body.drop(1))
            if (h == null || promotion != null) fail("syntax")
            file = h.groupValues[1]
            rank = h.groupValues[2]
        } else {
            if (!Regex(if (capture) "[a-h]" else "").matches(body)) fail("syntax")
            file = body
        }
    }
    val legal = pos.legal()
    if (legal.isEmpty()) fail("game over")
    var move: Move
    if (castling) {
        val k = body == "O-O"
        val problem = pos.castlingProblem(k)
        if (problem.isNotEmpty()) fail(problem)
        move = pos.castlingMove(k)
    } else {
        fun matches(m: Move) =
            pos.board[m.source].uppercaseChar() == kind &&
                m.target == target &&
                !pos.castle(m) &&
                (file.isEmpty() || FILES[m.source % 8] == file[0]) &&
                (rank.isEmpty() || RANKS[m.source / 8] == rank[0]) &&
                (kind != 'P' || (m.source % 8 != m.target % 8) == capture)
        val candidates = legal.filter { matches(it) }
        if (candidates.isEmpty())
            fail(if (pos.pseudo().any { matches(it) }) "leaves king in check" else "no such move")
        if (candidates.map { it.source }.distinct().size > 1) fail("ambiguous")
        move = candidates[0]
        if (pos.capture(move) != capture) fail("capture mark")
        if (move.promotion != null && promotion == null) fail("missing promotion")
        if (promotion != null && move.promotion == null) fail("invalid promotion")
        if (kind != 'P' && file + rank != pos.disambiguation(move)) fail("disambiguation")
        move = move.copy(promotion = promotion)
    }
    if (pos.mark(move) != mark) fail("check mark")
    return move
}

private fun readUci(pos: Position, text: String): Move {
    if (!Regex("[a-h][1-8][a-h][1-8][qrbn]?").matches(text)) fail("syntax")
    val s = square(text.take(2))
    val t = square(text.substring(2, 4))
    val promotion = text.getOrNull(4)?.uppercaseChar()
    val legal = pos.legal()
    if (legal.isEmpty()) fail("game over")
    if (pos.board[s] == '.' || color(pos.board[s]) != pos.side) fail("no piece")
    val move =
        legal.find { it.source == s && it.target == t }
            ?: fail(
                if (pos.pseudo().any { it.source == s && it.target == t }) "leaves king in check"
                else "no such move",
            )
    if (move.promotion != null && promotion == null) fail("missing promotion")
    if (promotion != null && move.promotion == null) fail("invalid promotion")
    return Move(s, t, promotion)
}

private fun perft(p: Position, d: Int, stats: LongArray? = null): Long {
    if (d == 0) return 1
    var total = 0L
    for (m in p.legal()) {
        val q = p.play(m)
        total += perft(q, d - 1, stats)
        if (d == 1 && stats != null) {
            stats[0]++
            if (p.capture(m)) stats[1]++
            if (p.enpassant(m)) stats[2]++
            if (p.castle(m)) stats[3]++
            if (m.promotion != null) stats[4]++
            if (q.check()) {
                stats[5]++
                if (q.legal().isEmpty()) stats[6]++
            }
        }
    }
    return total
}

private class Game(start: Position = parseFen(INITIAL.split(' ')), val loaded: Boolean = false) {
    val positions = mutableListOf(start)
    val records = mutableListOf<Record>()

    fun current() = positions.last()

    fun play(m: Move) {
        val p = current()
        records.add(
            Record(
                p.san(m),
                name(m.source) + name(m.target) + (m.promotion?.lowercaseChar()?.toString() ?: ""),
                p.captured(m),
            ),
        )
        positions.add(p.play(m))
    }

    fun repetition(): Int {
        val key = current().key()
        return positions.count { it.key() == key }
    }

    fun draws() = buildList {
        if (current().half >= 100) add("fifty")
        if (repetition() >= 3) add("threefold")
        if (current().insufficient()) add("insufficient")
    }

    fun result(): String {
        val s = current().state()
        return if (s == "checkmate") if (current().side == 'b') "1-0" else "0-1"
        else if (s == "stalemate" || draws().isNotEmpty()) "1/2-1/2" else "*"
    }
}

private class Session {
    var game = Game()

    fun execute(line: String) {
        val w = line.split(' ')
        val cmd = w[0]
        val a = w.drop(1)
        if (
            cmd !in
                setOf(
                    "NEW",
                    "LOAD",
                    "FEN",
                    "BOARD",
                    "MOVE",
                    "UCI",
                    "LEGAL",
                    "STATUS",
                    "UNDO",
                    "PERFT",
                    "DIVIDE",
                    "ATTACKS",
                    "PINS",
                    "HISTORY",
                    "PGN",
                )
        ) {
            println("ERROR unknown command")
            return
        }
        var bad =
            cmd in setOf("NEW", "FEN", "BOARD", "STATUS", "PINS", "HISTORY", "PGN") &&
                a.isNotEmpty()
        if (cmd == "MOVE" || cmd == "UCI") bad = a.isEmpty()
        if (cmd == "LEGAL") bad = a.size > 1 || (a.size == 1 && square(a[0]) < 0)
        if (cmd == "ATTACKS") bad = a.size != 1 || (a.size == 1 && square(a[0]) < 0)
        var n = -1
        if (cmd in setOf("UNDO", "PERFT", "DIVIDE")) {
            n = if (a.size == 1) number(a[0], 1, if (cmd == "UNDO") 9999 else 3) else -1
            bad = n < 0
        }
        if (bad) {
            println("ERROR bad arguments")
            return
        }
        val p = game.current()
        when (cmd) {
            "NEW" -> {
                game = Game()
                println("OK")
            }
            "LOAD" ->
                try {
                    val q = parseFen(a)
                    game = Game(q, true)
                    println("OK")
                } catch (e: IllegalArgumentException) {
                    println("ERROR bad fen (${e.message})")
                }
            "FEN" -> println(p.fen())
            "BOARD" -> {
                for (r in 7 downTo 0) println(
                    (listOf((r + 1).toString()) + (0..7).map { p.board[8 * r + it].toString() })
                        .joinToString(" "),
                )
                println("  a b c d e f g h")
            }
            "MOVE",
            "UCI" -> {
                val played = mutableListOf<String>()
                var failure = ""
                for ((i, text) in a.withIndex()) {
                    try {
                        val m =
                            if (cmd == "MOVE") readSan(game.current(), text)
                            else readUci(game.current(), text)
                        game.play(m)
                        played.add(game.records.last().san)
                    } catch (e: IllegalArgumentException) {
                        failure = "ILLEGAL move ${i+1}: $text (${e.message})"
                        break
                    }
                }
                if (cmd == "UCI" && played.isNotEmpty()) println("san " + played.joinToString(" "))
                if (failure.isNotEmpty()) println(failure) else if (cmd == "MOVE") println("OK")
            }
            "LEGAL" -> {
                val list =
                    p.legal()
                        .filter { a.isEmpty() || it.source == square(a[0]) }
                        .map { p.san(it) }
                        .sorted()
                println((listOf("legal", list.size.toString()) + list).joinToString(" "))
            }
            "STATUS" ->
                println(
                    (listOf(
                            "status",
                            if (p.side == 'w') "white" else "black",
                            p.state(),
                            "rep",
                            game.repetition().toString(),
                        ) + game.draws())
                        .joinToString(" "),
                )
            "UNDO" ->
                if (n > game.records.size) println("ERROR cannot undo")
                else {
                    repeat(n) {
                        game.records.removeLast()
                        game.positions.removeLast()
                    }
                    println("OK")
                }
            "PERFT" -> {
                val stats = LongArray(7)
                perft(p, n, stats)
                println(
                    "perft $n " +
                        listOf(
                                "nodes",
                                "captures",
                                "ep",
                                "castles",
                                "promotions",
                                "checks",
                                "mates",
                            )
                            .mapIndexed { i, f -> "$f ${stats[i]}" }
                            .joinToString(" "),
                )
            }
            "DIVIDE" -> {
                val rows =
                    p.legal().map { p.san(it) to perft(p.play(it), n - 1) }.sortedBy { it.first }
                for ((san, v) in rows) println("$san $v")
                println("total ${rows.sumOf{it.second}}")
            }
            "ATTACKS" -> {
                val row = mutableListOf("attacks", a[0])
                for (c in listOf('w', 'b')) {
                    val found = attackers(p.board, square(a[0]), c)
                    row.add(if (c == 'w') "white" else "black")
                    row.add(found.size.toString())
                    row.addAll(found.map { name(it) })
                }
                println(row.joinToString(" "))
            }
            "PINS" -> {
                val pins = p.pins()
                println(
                    (listOf("pins", pins.size.toString()) +
                            pins.map { (s, t) -> name(s) + "-" + name(t) })
                        .joinToString(" "),
                )
            }
            "HISTORY" -> {
                println("history ${game.records.size}")
                for ((i, r) in game.records.withIndex()) println(
                    "${i+1} ${r.uci} ${r.san} ${r.captured}",
                )
            }
            "PGN" -> {
                val result = game.result()
                println("[Result \"$result\"]")
                if (game.loaded) {
                    println("[SetUp \"1\"]")
                    println("[FEN \"${game.positions[0].fen()}\"]")
                }
                val row = mutableListOf<String>()
                for ((i, r) in game.records.withIndex()) {
                    val q = game.positions[i]
                    if (q.side == 'w') row.add("${q.full}.")
                    else if (i == 0) row.add("${q.full}...")
                    row.add(r.san)
                }
                row.add(result)
                println(row.joinToString(" "))
            }
        }
    }
}

fun main() {
    val input = BufferedReader(InputStreamReader(System.`in`))
    val count = input.readLine().toInt()
    val session = Session()
    repeat(count) { session.execute(input.readLine()) }
}
