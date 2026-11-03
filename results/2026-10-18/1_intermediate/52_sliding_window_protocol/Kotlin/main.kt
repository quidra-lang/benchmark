import kotlin.math.max
import kotlin.math.min

val keys =
    listOf(
        "PROTOCOL",
        "FRAMES",
        "WINDOW",
        "SEQBITS",
        "TIMEOUT",
        "DELAY",
        "INTERVAL",
        "MAXTICKS",
        "DUPACK",
        "NAK",
        "BACKOFF",
        "CONGESTION",
        "UNSAFE",
        "TRACE",
        "RANDOM",
        "LOSEDATA",
        "LOSECTRL",
        "CORRUPTDATA",
        "CORRUPTCTRL",
        "DELAYDATA",
        "DELAYCTRL",
        "SNAPSHOT",
    )
val output = mutableListOf<String>()

fun fixed(n: Long, d: Long, digits: Int): String {
    val scale = if (digits == 2) 100L else 10L
    val v = if (d == 0L) 0L else n * scale / d
    return "${v / scale}." + (v % scale).toString().padStart(digits, '0')
}

fun tick(t: Int) = if (t < 0) "-" else "$t"

fun onOff(b: Boolean) = if (b) "on" else "off"

class Scenario(val name: String) {
    var protocol = ""
    var error: String? = null
    var trace = "ALL"
    val values = mutableMapOf<String, List<String>>()
    val lists = mutableMapOf<String, Set<Int>>()
    val delays = mutableMapOf<String, Map<Int, Int>>()
    var n = 0
    var w = 0
    var k = 0
    var timeout = 0
    var delay = 0
    var interval = 0
    var limit = 1000
    var dupack = 0
    var nak = false
    var backoff = false
    var congestion = false
    var unsafe = false
    var random = false
    var seed = 0L
    var loss = 0
    var corruption = 0
    var completion = -1
    var end = 0
    var delivered = 0
    var data = 0

    fun number(key: String) = values.getValue(key)[0].toInt()

    fun on(key: String) = values[key]?.get(0) == "ON"

    fun line(words: List<String>) {
        if (error != null) return
        val key = words[0]
        val pos = keys.indexOf(key)
        if (pos < 0) {
            error = "unknown key $key"
            return
        }
        if (key in values) {
            error = "duplicate key $key"
            return
        }
        val count = words.size - 1
        val bad = if (key == "RANDOM") count != 3 else if (pos >= 15) count < 1 else count != 1
        if (bad) {
            error = "wrong number of values for $key"
            return
        }
        values[key] = words.drop(1)
    }

    fun valid(key: String): Boolean {
        val v = values.getValue(key)
        when (key) {
            "PROTOCOL" -> return v[0] in listOf("SW", "GBN", "SR")
            "NAK",
            "BACKOFF",
            "CONGESTION",
            "UNSAFE" -> return v[0] in listOf("ON", "OFF")
            "TRACE" -> return v[0] in listOf("ALL", "SENDER", "RECEIVER", "NONE")
            "RANDOM" -> {
                val s = v[0].toLong()
                val p = v[1].toLong()
                val c = v[2].toLong()
                return s in 1..2147483646L && p >= 0 && c >= 0 && p + c <= 100
            }
        }
        if (keys.indexOf(key) >= 15) {
            val found = mutableSetOf<Int>()
            val extra = mutableMapOf<Int, Int>()
            val delayed = key.startsWith("DELAY")
            for (item in v) {
                val pair = item.split(':')
                val a = pair[0].toInt()
                val lo = if (key == "SNAPSHOT") 0 else 1
                val hi = if (key == "SNAPSHOT") 2000 else 9999
                if (a !in lo..hi || !found.add(a)) return false
                if (delayed) {
                    val e = pair[1].toInt()
                    if (e !in 1..50) return false
                    extra[a] = e
                }
            }
            lists[key] = found
            if (delayed) delays[key] = extra
            return true
        }
        val range =
            when (key) {
                "FRAMES" -> 1..60
                "WINDOW" -> 1..32
                "SEQBITS" -> 1..6
                "TIMEOUT" -> 1..50
                "DELAY",
                "DUPACK" -> 1..10
                "INTERVAL" -> 0..10
                else -> 1..2000
            }
        return number(key) in range
    }

    fun check() {
        if (error != null) return
        for (key in keys.take(6)) if (key !in values) {
            error = "missing key $key"
            return
        }
        for (key in keys) if (key in values && !valid(key)) {
            error = "bad value for $key"
            return
        }
        protocol = values.getValue("PROTOCOL")[0]
        n = number("FRAMES")
        w = number("WINDOW")
        k = number("SEQBITS")
        timeout = number("TIMEOUT")
        delay = number("DELAY")
        if ("INTERVAL" in values) interval = number("INTERVAL")
        if ("MAXTICKS" in values) limit = number("MAXTICKS")
        if ("DUPACK" in values) dupack = number("DUPACK")
        nak = on("NAK")
        backoff = on("BACKOFF")
        congestion = on("CONGESTION")
        unsafe = on("UNSAFE")
        if ("TRACE" in values) trace = values.getValue("TRACE")[0]
        random = "RANDOM" in values
        if (random) {
            val v = values.getValue("RANDOM")
            seed = v[0].toLong()
            loss = v[1].toInt()
            corruption = v[2].toInt()
        }
        if (protocol == "SR" && dupack > 0) {
            error = "DUPACK not supported for SR"
            return
        }
        val upper =
            when (protocol) {
                "SW" -> 1
                "GBN" -> (1 shl k) - 1
                else -> 1 shl (k - 1)
            }
        if (w > upper && !(unsafe && protocol != "SW")) {
            error = "window $w exceeds limit $upper for $protocol"
            return
        }
        for (kind in listOf("DATA", "CTRL")) {
            val both = lists["LOSE$kind"].orEmpty().intersect(lists["CORRUPT$kind"].orEmpty())
            if (both.isNotEmpty()) {
                error =
                    (if (kind == "DATA") "data" else "control") +
                        " #${both.min()} both lost and corrupted"
                return
            }
        }
    }

    fun contains(key: String, i: Int) = i in lists[key].orEmpty()

    fun extra(key: String, i: Int) = delays[key]?.get(i) ?: 0
}

data class Event(
    val arrival: Int,
    val number: Int,
    val value: Int,
    val outcome: Int,
    val kind: String,
)

class Simulation(val s: Scenario) {
    var t = 0
    val modulus = 1 shl s.k
    val sr = s.protocol == "SR"
    var base = 0
    var high = 0
    var next = 0
    var timer = -1
    var length = s.timeout
    var duplicates = 0
    var r = 0
    var nakSent = false
    var cwnd = 1
    var threshold = s.w
    var growth = 0
    var controlCount = 0
    var naks = 0
    var resent = 0
    var timeouts = 0
    var fast = 0
    var lostData = 0
    var lostControl = 0
    var corruptData = 0
    var corruptControl = 0
    var errors = 0
    var discarded = 0
    var maxBuffer = 0
    var latency = 0
    var random = s.seed
    val tx = IntArray(s.n)
    val first = IntArray(s.n) { -1 }
    val delivery = IntArray(s.n) { -1 }
    val acked = IntArray(s.n) { -1 }
    val timers = IntArray(s.n) { -1 }
    val marks = BooleanArray(s.n)
    val queue = mutableListOf<Int>()
    val buffer = mutableMapOf<Int, Int>()
    val dataEvents = mutableListOf<Event>()
    val controlEvents = mutableListOf<Event>()

    fun mod(a: Int) = Math.floorMod(a, modulus)

    fun emit(side: String, text: String) {
        if (side == "ALWAYS" || s.trace == "ALL" || s.trace == side) output.add("$t $text")
    }

    fun effective() = if (s.congestion) min(s.w, cwnd) else s.w

    fun outcome(kind: String, number: Int): Int {
        var result = 0
        if (s.random) {
            random = random * 48271L % 2147483647L
            val v = (random % 100).toInt()
            result = if (v < s.loss) 1 else if (v < s.loss + s.corruption) 2 else 0
        }
        val suffix = if (kind == "data") "DATA" else "CTRL"
        if (s.contains("LOSE$suffix", number)) result = 1
        if (s.contains("CORRUPT$suffix", number)) result = 2
        return result
    }

    fun control(nak: Boolean, a: Int) {
        val id = ++controlCount
        if (nak) naks++
        val kind = if (nak) "nak" else "ack"
        emit("RECEIVER", "${kind.uppercase()} a=$a #$id")
        controlEvents.add(
            Event(t + s.delay + s.extra("DELAYCTRL", id), id, a, outcome(kind, id), kind),
        )
    }

    fun deliver(payload: Int) {
        if (payload == r) {
            emit("RECEIVER", "DELIVER f=$r")
            if (delivery[payload] < 0) delivery[payload] = t
            s.delivered++
            latency += t - first[payload]
        } else {
            emit("RECEIVER", "DELIVER f=$r wrong=$payload")
            errors++
        }
        r++
        nakSent = false
    }

    fun discard(seq: Int) {
        discarded++
        emit("RECEIVER", "DISCARD seq=$seq")
    }

    fun receive(e: Event) {
        val seq = mod(e.value)
        emit("RECEIVER", "RECV seq=$seq #${e.number}")
        if (!sr) {
            if (seq == mod(r)) {
                deliver(e.value)
                control(false, seq)
            } else {
                discard(seq)
                if (s.nak && !nakSent) {
                    control(true, mod(r))
                    nakSent = true
                } else if (r > 0) control(false, mod(r - 1))
            }
        } else {
            val offset = mod(seq - r)
            if (offset < s.w) {
                val position = r + offset
                if (position in buffer) {
                    discard(seq)
                    control(false, seq)
                } else if (offset == 0) {
                    deliver(e.value)
                    while (r in buffer) deliver(buffer.remove(r)!!)
                    control(false, seq)
                } else {
                    buffer[position] = e.value
                    maxBuffer = max(maxBuffer, buffer.size)
                    emit("RECEIVER", "BUFFER f=$position")
                    control(false, seq)
                    if (s.nak && !nakSent) {
                        control(true, mod(r))
                        nakSent = true
                    }
                }
            } else {
                discard(seq)
                if (mod(r - seq) <= s.w) control(false, seq)
            }
        }
    }

    fun goBack() {
        next = base
        timer = -1
        duplicates = 0
    }

    fun increase(count: Int) {
        if (!s.congestion) return
        repeat(count) {
            if (cwnd < s.w) {
                if (cwnd < threshold) cwnd++
                else {
                    growth++
                    if (growth == cwnd) {
                        cwnd++
                        growth = 0
                    }
                }
            }
        }
    }

    fun decrease(timeout: Boolean) {
        if (!s.congestion) return
        threshold = max(cwnd / 2, 1)
        cwnd = if (timeout) 1 else threshold
        growth = 0
    }

    fun cwndLine(c: Int, h: Int) {
        if (s.congestion && (c != cwnd || h != threshold))
            emit("SENDER", "CWND $cwnd ssthresh=$threshold")
    }

    fun acknowledge(e: Event) {
        val oldC = cwnd
        val oldS = threshold
        val oldBase = base
        val a = e.value
        val f = base + mod(a - base)
        val nak = e.kind == "nak"
        var accepted = false
        if (sr) {
            if (f < high && !marks[f]) {
                accepted = true
                timers[f] = -1
                if (nak) {
                    if (f !in queue) queue.add(f)
                } else {
                    marks[f] = true
                    if (acked[f] < 0) acked[f] = t
                    queue.remove(f)
                    while (base < high && marks[base]) base++
                    increase(1)
                }
            }
        } else if (if (nak) f <= high else f < high) {
            accepted = true
            base = if (nak) f else f + 1
            increase(base - oldBase)
            for (i in oldBase until base) if (acked[i] < 0) acked[i] = t
            if (nak) goBack() else if (next < base) next = base
        }
        if (base > oldBase) {
            length = s.timeout
            duplicates = 0
        }
        if (accepted && !sr && !nak) timer = if (base == next) -1 else t + length
        val label = if (nak) "NAK" else "ACK"
        emit(
            "SENDER",
            (if (accepted) "GOT" else "OLD") +
                "$label a=$a #${e.number}" +
                if (accepted) " base=$base" else "",
        )
        if (accepted && nak) decrease(false)
        if (!accepted && !nak && !sr && s.dupack > 0 && base >= 1 && a == mod(base - 1)) {
            duplicates++
            if (duplicates == s.dupack) {
                fast++
                emit("SENDER", "FASTRETX f=$base")
                goBack()
                decrease(false)
            }
        }
        cwndLine(oldC, oldS)
    }

    fun timeout(f: Int) {
        val oldC = cwnd
        val oldS = threshold
        timeouts++
        emit("SENDER", "TIMEOUT f=$f")
        if (sr) {
            timers[f] = -1
            queue.add(f)
        } else goBack()
        if (s.backoff) length = min(length * 2, 8 * s.timeout)
        decrease(true)
        cwndLine(oldC, oldS)
    }

    fun send(f: Int) {
        val id = ++s.data
        val again = tx[f]++ > 0
        if (again) resent++ else first[f] = t
        emit("SENDER", (if (again) "RESEND" else "SEND") + " f=$f seq=${mod(f)} #$id")
        dataEvents.add(
            Event(t + s.delay + s.extra("DELAYDATA", id), id, f, outcome("data", id), "data"),
        )
    }

    fun arrivals(events: MutableList<Event>, data: Boolean) {
        val ready = events.filter { it.arrival == t }.sortedBy { it.number }
        events.removeAll(ready.toSet())
        for (e in ready) {
            if (e.outcome != 0) {
                val lost = e.outcome == 1
                if (data) {
                    if (lost) lostData++ else corruptData++
                } else {
                    if (lost) lostControl++ else corruptControl++
                }
                emit(
                    if (data) "RECEIVER" else "SENDER",
                    (if (lost) "LOST" else "CORRUPT") + " ${e.kind} #${e.number}",
                )
            } else if (data) receive(e) else acknowledge(e)
        }
    }

    fun snapshot() {
        val x = StringBuilder()
        val y = StringBuilder()
        for (f in 0 until s.n) {
            val ack = if (sr) marks[f] else f < base
            val retransmit = if (sr) f in queue else next <= f && f < high
            val sent = if (sr) f < high else f < next
            x.append(
                if (ack) 'A'
                else if (retransmit) 'R'
                else if (sent) 'O' else if (f < base + effective()) 'W' else '.',
            )
            y.append(
                if (f < r) 'D'
                else if (sr && f in buffer) 'B'
                else if (if (sr) f < r + s.w else f == r) 'W' else '.',
            )
        }
        emit("ALWAYS", "SNAPSHOT sender=$x receiver=$y")
    }

    fun run() {
        for (time in 0..s.limit) {
            t = time
            arrivals(dataEvents, true)
            arrivals(controlEvents, false)
            val done = base == s.n
            if (!done) {
                if (sr) {
                    for (f in base until high) if (timers[f] == t) timeout(f)
                } else if (timer == t) timeout(base)
                if (sr) {
                    var f = -1
                    if (queue.isNotEmpty()) f = queue.removeAt(0)
                    else if (high < s.n && high < base + effective() && high * s.interval <= t)
                        f = high++
                    if (f >= 0) {
                        send(f)
                        timers[f] = t + length
                    }
                } else if (
                    next < s.n &&
                        next < base + effective() &&
                        (next < high || next * s.interval <= t)
                ) {
                    send(next)
                    next++
                    high = max(high, next)
                    if (timer < 0) timer = t + length
                }
            }
            if (s.contains("SNAPSHOT", t)) snapshot()
            if (done || t == s.limit) {
                s.end = t
                if (done) s.completion = t
                emit("ALWAYS", if (done) "DONE" else "ABORT")
                break
            }
        }
        for (f in 0 until s.n) output.add(
            "frame $f: seq=${mod(f)} tx=${tx[f]} first=${tick(first[f])} delivered=${tick(delivery[f])} acked=${tick(acked[f])}",
        )
        output.add(
            "totals: data=${s.data} resent=$resent control=$controlCount nak=$naks timeouts=$timeouts fastretx=$fast",
        )
        output.add(
            "channel: lost_data=$lostData lost_ctrl=$lostControl corrupt_data=$corruptData corrupt_ctrl=$corruptControl",
        )
        output.add(
            "receiver: delivered=${s.delivered} errors=$errors discarded=$discarded max_buffer=$maxBuffer",
        )
        val goodput =
            if (s.completion < 0) "-" else fixed(s.delivered.toLong(), s.completion.toLong(), 2)
        val latencyText =
            if (s.delivered == 0) "-" else fixed(latency.toLong(), s.delivered.toLong(), 2)
        output.add(
            "result: completion=${tick(s.completion)} goodput=$goodput efficiency=${fixed(s.delivered * 100L, s.data.toLong(), 1)}% utilization=${fixed(s.data * 100L, (s.end + 1).toLong(), 1)}% latency=$latencyText",
        )
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val scenarios = mutableListOf<Scenario>()
    repeat(input.readLine().toInt()) {
        val s = Scenario(input.readLine().split(' ')[1])
        while (true) {
            val line = input.readLine()
            if (line == "END") break
            s.line(line.split(' '))
        }
        s.check()
        scenarios.add(s)
        output.add("== ${s.name} ==")
        if (s.error != null) output.add("error: ${s.error}")
        else {
            output.add(
                "config: ${s.protocol} n=${s.n} w=${s.w} k=${s.k} T=${s.timeout} d=${s.delay}",
            )
            val random = if (s.random) "${s.seed}/${s.loss}/${s.corruption}" else "off"
            output.add(
                "options: interval=${s.interval} limit=${s.limit} dupack=${if (s.dupack == 0) "off" else s.dupack} nak=${onOff(s.nak)} backoff=${onOff(s.backoff)} congestion=${onOff(s.congestion)} unsafe=${onOff(s.unsafe)} trace=${s.trace.lowercase()} random=$random",
            )
            Simulation(s).run()
        }
    }
    output.add("== ranking ==")
    val completed =
        scenarios
            .filter { it.completion >= 0 }
            .sortedWith { a, b ->
                val c =
                    (b.delivered.toLong() * a.completion).compareTo(
                        a.delivered.toLong() * b.completion,
                    )
                if (c != 0) c
                else (b.delivered.toLong() * a.data).compareTo(a.delivered.toLong() * b.data)
            }
    for ((i, s) in completed.withIndex()) output.add(
        "${i + 1}. ${s.name} ${s.protocol} goodput=${fixed(s.delivered.toLong(), s.completion.toLong(), 2)} efficiency=${fixed(s.delivered * 100L, s.data.toLong(), 1)}%",
    )
    for (s in scenarios) if (s.completion < 0)
        output.add("- ${s.name} " + if (s.error != null) "invalid" else "aborted")
    output.add("== protocols ==")
    for (p in listOf("SW", "GBN", "SR")) {
        val runs = completed.filter { it.protocol == p }
        if (runs.isNotEmpty())
            output.add(
                "$p: runs=${runs.size} goodput=${fixed(runs.sumOf { it.delivered.toLong() }, runs.sumOf { it.completion.toLong() }, 2)} efficiency=${fixed(runs.sumOf { it.delivered * 100L }, runs.sumOf { it.data.toLong() }, 1)}%",
            )
    }
    print(output.joinToString("\n", postfix = "\n"))
}
