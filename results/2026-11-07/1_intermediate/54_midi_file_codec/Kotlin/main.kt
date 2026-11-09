import java.util.TreeMap

private val channelKinds =
    listOf(
        "NOTE_OFF",
        "NOTE_ON",
        "POLY_PRESSURE",
        "CONTROL",
        "PROGRAM",
        "CHANNEL_PRESSURE",
        "PITCH_BEND",
    )
private val textKinds =
    listOf(
        "TEXT_EVENT",
        "COPYRIGHT",
        "TRACK_NAME",
        "INSTRUMENT_NAME",
        "LYRIC",
        "MARKER",
        "CUE_POINT",
    )
private val majorKeys = "Cb Gb Db Ab Eb Bb F C G D A E B F# C#".split(' ')
private val minorKeys = "Ab Eb Bb F C G D A E B F# C# G# D# A#".split(' ')
private val pitches = listOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
private val metaKinds =
    mapOf(
        0 to "SEQUENCE_NUMBER",
        32 to "CHANNEL_PREFIX",
        47 to "END_OF_TRACK",
        81 to "TEMPO",
        84 to "SMPTE_OFFSET",
        88 to "TIME_SIGNATURE",
        89 to "KEY_SIGNATURE",
        127 to "SEQUENCER_SPECIFIC",
    )

private class Event(var tick: Long, val code: Int, var data: MutableList<Int>) {
    fun duplicate() = Event(tick, code, data.toMutableList())

    fun channel() = code in 128..239

    fun ch() = (code and 15) + 1

    fun on() = channel() && (code shr 4) == 9 && data[1] > 0

    fun off() = channel() && ((code shr 4) == 8 || (code shr 4) == 9 && data[1] == 0)

    fun end() = code == 303

    fun kind(): String {
        if (channel()) return channelKinds[(code shr 4) - 8]
        if (code == 240) return "SYSEX"
        if (code == 247) return "SYSEX_ESCAPE"
        val type = code - 256
        return if (type in 1..7) textKinds[type - 1] else metaKinds[type] ?: "META"
    }
}

private class Song(
    var format: Int,
    val division: Int,
    var tracks: MutableList<MutableList<Event>>,
) {
    fun duplicate() =
        Song(
            format,
            division,
            tracks.map { t -> t.map { it.duplicate() }.toMutableList() }.toMutableList(),
        )

    fun count() = tracks.sumOf { it.size }

    fun length() = tracks.maxOf { it.last().tick }
}

private data class Located(val event: Event, val track: Int, val order: Int)

private data class Note(val on: Located, val off: Located) {
    fun start() = on.event.tick

    fun length() = off.event.tick - start()

    fun channel() = on.event.ch()

    fun pitch() = on.event.data[0]
}

private data class Pairing(val notes: List<Note>, val unmatched: List<Located>)

private class Failure(message: String) : RuntimeException(message)

private fun fail(message: String): Nothing = throw Failure(message)

private val output = StringBuilder()

private fun emit(line: String) {
    output.append(line).append('\n')
}

private val songs = TreeMap<String, Song>()
private var running = true
private var zeroOff = false

private fun noteName(p: Int) = pitches[p % 12] + (p / 12 - 1)

private fun noteNumber(text: String) = (0..127).find { noteName(it) == text } ?: fail("bad value")

private fun hex(n: Int, width: Int) = n.toString(16).uppercase().padStart(width, '0')

private fun dataHex(data: List<Int>) = data.joinToString("") { hex(it, 2) }

private fun value(data: List<Int>) = data.fold(0L) { a, b -> a * 256 + b }

private fun bytes(value: Long, size: Int) =
    (size - 1 downTo 0).map { ((value shr (it * 8)) and 255).toInt() }.toMutableList()

private fun global(s: Song): List<Located> {
    var order = 0
    return s.tracks
        .flatMapIndexed { t, events -> events.map { Located(it, t, order++) } }
        .sortedWith(compareBy<Located> { it.event.tick }.thenBy { it.track }.thenBy { it.order })
}

private fun description(s: Song) =
    "format ${s.format} tracks ${s.tracks.size} division ${s.division} events ${s.count()}"

private fun eventText(e: Event, track: Int): String {
    val head = "${e.tick} $track ${e.kind()}"
    val d = e.data
    val meta = e.code - 256
    if (e.channel()) {
        val fields =
            when (e.code shr 4) {
                8,
                9,
                10 -> "${noteName(d[0])} ${d[1]}"
                14 -> (d[0] + 128 * d[1] - 8192).toString()
                else -> d.joinToString(" ")
            }
        return "$head ${e.ch()} $fields"
    }
    if (meta in 1..7) return "$head \"${d.map { it.toChar() }.joinToString("")}\""
    if (e.end()) return head
    if (e.code == 240 || e.code == 247 || meta == 127 || meta !in metaKinds) {
        return head +
            (if (e.kind() == "META") " ${hex(meta, 2)}" else "") +
            " ${d.size}" +
            (if (d.isEmpty()) "" else " ${dataHex(d)}")
    }
    return when (meta) {
        0,
        81 -> "$head ${value(d)}"
        32 -> "$head ${d[0] + 1}"
        84 -> "$head ${d.joinToString(" ")}"
        88 -> "$head ${d[0]}/${1 shl d[1]} ${d[2]} ${d[3]}"
        else -> {
            val sf = if (d[0] >= 128) d[0] - 256 else d[0]
            "$head " + if (d[1] == 0) "${majorKeys[sf + 7]} major" else "${minorKeys[sf + 7]} minor"
        }
    }
}

private class Parser(val data: List<Int>) {
    var position = 0
    var end = data.size
    var eventStart = 0

    fun error(offset: Int, reason: String): Nothing = fail("byte $offset: $reason")

    fun read(): Int {
        if (position >= end) error(eventStart, "truncated event")
        return data[position++]
    }

    fun vlq(): Long {
        val start = position
        var value = 0L
        repeat(4) {
            val b = read()
            value = value * 128 + (b and 127)
            if (b < 128) return value
        }
        error(start, "variable-length value too long")
    }

    fun integer(p: Int, n: Int) = value(data.subList(p, p + n))

    fun chunk(id: String): Int {
        val p = position
        if (data.size - p < 8) error(p, "truncated chunk")
        for (i in 0..3) if (data[p + i] != id[i].code) error(p, "bad chunk id")
        val length = integer(p + 4, 4)
        if (p + 8L + length > data.size) error(p, "truncated chunk")
        position += 8
        return length.toInt()
    }

    fun validateMeta(type: Int, d: List<Int>, p: Int) {
        val length =
            when (type) {
                0,
                89 -> 2
                32 -> 1
                47 -> 0
                81 -> 3
                84 -> 5
                88 -> 4
                else -> -1
            }
        if (length >= 0 && d.size != length) error(p, "bad meta length")
        val invalid =
            when (type) {
                81 -> value(d) == 0L
                32 -> d[0] > 15
                88 -> d[0] == 0 || d[1] > 6
                89 -> {
                    val sf = if (d[0] >= 128) d[0] - 256 else d[0]
                    sf !in -7..7 || d[1] > 1
                }
                else -> false
            }
        if (invalid) error(p, "bad meta data")
    }

    fun parse(): Song {
        if (chunk("MThd") != 6) error(4, "bad header length")
        val format = integer(8, 2).toInt()
        val count = integer(10, 2).toInt()
        val division = integer(12, 2).toInt()
        if (format > 2) error(8, "bad format")
        if (count == 0 || format == 0 && count != 1) error(10, "bad track count")
        if ((division and 32768) != 0) error(12, "smpte timing not supported")
        if (division == 0) error(12, "bad division")
        position = 14
        val tracks = mutableListOf<MutableList<Event>>()
        repeat(count) {
            if (position == data.size) error(position, "missing track")
            val length = chunk("MTrk")
            end = position + length
            val events = mutableListOf<Event>()
            var tick = 0L
            var status = -1
            while (position < end) {
                if (events.lastOrNull()?.end() == true) error(position, "event after end of track")
                eventStart = position
                tick += vlq()
                val statusPosition = position
                val b = read()
                if (b < 128) {
                    if (status < 0) error(statusPosition, "data byte without running status")
                    position--
                } else status = b
                var code = status
                val payload = mutableListOf<Int>()
                when (status) {
                    in 128..239 -> {
                        val n = if ((status shr 4) == 12 || (status shr 4) == 13) 1 else 2
                        repeat(n) {
                            val p = position
                            val v = read()
                            if (v >= 128) error(p, "bad data byte")
                            payload.add(v)
                        }
                    }
                    240,
                    247,
                    255 -> {
                        val meta = status == 255
                        if (meta) code = 256 + read()
                        val size = vlq()
                        if (position + size > end) error(eventStart, "truncated event")
                        payload.addAll(data.subList(position, position + size.toInt()))
                        position += size.toInt()
                        if (meta) validateMeta(code - 256, payload, statusPosition)
                        status = -1
                    }
                    else -> error(statusPosition, "unknown status byte")
                }
                events.add(Event(tick, code, payload))
            }
            if (events.lastOrNull()?.end() != true) error(end, "missing end of track")
            tracks.add(events)
            end = data.size
        }
        if (position < data.size) error(position, "extra data")
        return Song(format, division, tracks)
    }
}

private fun bounded(text: String, low: Long, high: Long): Long {
    val n = text.toLongOrNull() ?: fail("bad value")
    if (n !in low..high) fail("bad value")
    return n
}

private fun fields(f: List<String>, n: Int) {
    if (f.size != n) fail("bad value")
}

private fun blob(f: List<String>, start: Int): MutableList<Int> {
    if (f.size <= start) fail("bad value")
    val length = bounded(f[start], 0, 1000000).toInt()
    if (f.size != start + (if (length == 0) 1 else 2)) fail("bad value")
    if (length == 0) return mutableListOf()
    val text = f[start + 1]
    if (text.length != 2 * length || !text.matches(Regex("[0-9A-F]*"))) fail("bad value")
    return text.chunked(2).map { it.toInt(16) }.toMutableList()
}

private fun parseEvent(line: String): Event {
    val parts = line.split(' ', limit = 4)
    val tick = parts[0].toLong()
    val kind = parts[2]
    val tail = parts.getOrElse(3) { "" }
    val f = if (tail.isEmpty()) emptyList() else tail.split(' ')
    val channelIndex = channelKinds.indexOf(kind)
    val textIndex = textKinds.indexOf(kind)
    var code: Int
    var data = mutableListOf<Int>()
    if (channelIndex >= 0) {
        fields(f, if (channelIndex in 4..6) 2 else 3)
        val ch = bounded(f[0], 1, 16).toInt()
        code = (channelIndex + 8) * 16 + ch - 1
        when (channelIndex) {
            0,
            1,
            2 -> {
                data.add(noteNumber(f[1]))
                data.add(bounded(f[2], 0, 127).toInt())
            }
            6 -> {
                val bend = bounded(f[1], -8192, 8191).toInt() + 8192
                data.add(bend % 128)
                data.add(bend / 128)
            }
            else -> data.addAll(f.drop(1).map { bounded(it, 0, 127).toInt() })
        }
    } else if (textIndex >= 0) {
        if (
            tail.length < 2 ||
                tail.first() != '"' ||
                tail.last() != '"' ||
                '"' in tail.substring(1, tail.length - 1)
        )
            fail("bad value")
        code = 257 + textIndex
        data.addAll(tail.substring(1, tail.length - 1).map { it.code })
    } else if (kind == "SYSEX" || kind == "SYSEX_ESCAPE") {
        code = if (kind == "SYSEX") 240 else 247
        data = blob(f, 0)
    } else if (kind == "META") {
        if (f.size < 2 || !f[0].matches(Regex("[0-9A-F]{2}"))) fail("bad value")
        val type = f[0].toInt(16)
        if (type <= 7 || type in metaKinds) fail("bad value")
        code = 256 + type
        data = blob(f, 1)
    } else {
        val meta = metaKinds.entries.find { it.value == kind }?.key ?: fail("unknown event type")
        code = 256 + meta
        when (meta) {
            0 -> {
                fields(f, 1)
                data = bytes(bounded(f[0], 0, 65535), 2)
            }
            32 -> {
                fields(f, 1)
                data.add(bounded(f[0], 1, 16).toInt() - 1)
            }
            47 -> fields(f, 0)
            81 -> {
                fields(f, 1)
                data = bytes(bounded(f[0], 1, 16777215), 3)
            }
            84 -> {
                fields(f, 5)
                data.addAll(f.map { bounded(it, 0, 255).toInt() })
            }
            88 -> {
                fields(f, 3)
                val signature = f[0].split('/')
                if (signature.size != 2) fail("bad value")
                val numerator = bounded(signature[0], 1, 255).toInt()
                val denominator = bounded(signature[1], 1, 64).toInt()
                if ((denominator and (denominator - 1)) != 0) fail("bad value")
                data.addAll(
                    listOf(
                        numerator,
                        Integer.numberOfTrailingZeros(denominator),
                        bounded(f[1], 0, 255).toInt(),
                        bounded(f[2], 0, 255).toInt(),
                    ),
                )
            }
            89 -> {
                fields(f, 2)
                if (f[1] != "minor" && f[1] != "major") fail("bad value")
                val minor = f[1] == "minor"
                val index = (if (minor) minorKeys else majorKeys).indexOf(f[0])
                if (index < 0) fail("bad value")
                data.addAll(listOf((index - 7 + 256) % 256, if (minor) 1 else 0))
            }
            127 -> data = blob(f, 0)
        }
    }
    return Event(tick, code, data)
}

private fun textSong(lines: List<String>): Song {
    val h = lines[0].split(' ')
    var format = 0
    var count = 0
    var division = 0
    try {
        if (h.size != 4 || h[0] != "HEADER") fail("bad header")
        format = bounded(h[1], 0, 2).toInt()
        count = bounded(h[2], 1, 65535).toInt()
        division = bounded(h[3], 1, 32767).toInt()
        if (format == 0 && count != 1) fail("bad header")
    } catch (error: Failure) {
        fail("line 1: bad header")
    }
    val tracks = mutableListOf(mutableListOf<Event>())
    var current = 0
    for (i in 1 until lines.size) {
        try {
            val e = parseEvent(lines[i])
            val track = lines[i].split(' ', limit = 4)[1].toInt()
            if (track >= count) fail("bad track")
            var events = tracks[current]
            val end = events.lastOrNull()?.end() == true
            if (track < current) fail("out of order")
            if (track > current && (!end || track > current + 1)) fail("missing end of track")
            if (track == current && end) fail("event after end of track")
            if (track == current + 1) {
                current++
                events = mutableListOf()
                tracks.add(events)
            }
            if (events.isNotEmpty() && e.tick < events.last().tick) fail("out of order")
            events.add(e)
        } catch (error: Failure) {
            fail("line ${i + 1}: ${error.message}")
        }
    }
    if (current + 1 < count || tracks[current].lastOrNull()?.end() != true)
        fail("line ${lines.size + 1}: missing end of track")
    return Song(format, division, tracks)
}

private fun vlq(number: Long): List<Int> {
    var n = number
    val result = mutableListOf((n and 127).toInt())
    n = n shr 7
    while (n > 0) {
        result.add(0, (n and 127).toInt() or 128)
        n = n shr 7
    }
    return result
}

private fun encode(s: Song) {
    val result = mutableListOf<Int>()
    fun chunk(target: MutableList<Int>, id: String, data: List<Int>) {
        target.addAll(id.map { it.code })
        target.addAll(bytes(data.size.toLong(), 4))
        target.addAll(data)
    }
    chunk(
        result,
        "MThd",
        bytes(s.format.toLong(), 2) +
            bytes(s.tracks.size.toLong(), 2) +
            bytes(s.division.toLong(), 2),
    )
    for (track in s.tracks) {
        val data = mutableListOf<Int>()
        var last = 0L
        var previous = -1
        for (e in track) {
            data.addAll(vlq(e.tick - last))
            last = e.tick
            if (e.channel()) {
                var code = e.code
                var payload: List<Int> = e.data
                if (zeroOff && (code shr 4) == 8) {
                    code += 16
                    payload = listOf(e.data[0], 0)
                }
                if (!running || previous != code) data.add(code)
                data.addAll(payload)
                previous = code
            } else {
                previous = -1
                if (e.code < 256) data.add(e.code) else data.addAll(listOf(255, e.code - 256))
                data.addAll(vlq(e.data.size.toLong()))
                data.addAll(e.data)
            }
        }
        chunk(result, "MTrk", data)
    }
    for (i in result.indices step 16) emit(
        "${hex(i, 4)}: ${result.subList(i, minOf(i + 16, result.size)).joinToString(" ") { hex(it, 2) }}",
    )
    emit("${result.size} bytes")
}

private fun pairing(s: Song): Pairing {
    val queues = mutableMapOf<Int, ArrayDeque<Located>>()
    val notes = mutableListOf<Note>()
    val unmatched = mutableListOf<Located>()
    val events = global(s)
    for (l in events) {
        val e = l.event
        if (!e.on() && !e.off()) continue
        val q = queues.getOrPut(e.ch() * 128 + e.data[0]) { ArrayDeque() }
        if (e.on()) q.addLast(l)
        else if (q.isEmpty()) unmatched.add(l) else notes.add(Note(q.removeFirst(), l))
    }
    queues.values.forEach { unmatched.addAll(it) }
    val order = events.mapIndexed { i, l -> l.event to i }.toMap()
    notes.sortWith(
        compareBy<Note> { it.start() }
            .thenBy { it.channel() }
            .thenBy { it.pitch() }
            .thenBy { order.getValue(it.on.event) },
    )
    unmatched.sortBy { order.getValue(it.event) }
    return Pairing(notes, unmatched)
}

private fun time(s: Song, tick: Long): String {
    var total = 0L
    var last = 0L
    var tempo = 500000L
    for (l in global(s)) if (l.event.tick <= tick && l.event.code == 337) {
        total += (l.event.tick - last) * tempo
        last = l.event.tick
        tempo = value(l.event.data)
    }
    val us = (total + (tick - last) * tempo) / s.division
    return "${us / 1000}.${(us % 1000).toString().padStart(3, '0')}"
}

private fun bar(s: Song, tick: Long): String {
    var start = 0L
    var number = 1L
    var numerator = 4L
    var beat = s.division.toLong()
    for (l in global(s)) if (l.event.tick <= tick && l.event.code == 344) {
        val length = numerator * beat
        number += (l.event.tick - start + length - 1) / length
        start = l.event.tick
        numerator = l.event.data[0].toLong()
        beat = s.division * 4L / (1L shl l.event.data[1])
    }
    val x = tick - start
    val length = numerator * beat
    return "${number + x / length}:${x % length / beat + 1}:${x % beat}"
}

private fun printNotes(p: Pairing) {
    emit("notes ${p.notes.size} unmatched ${p.unmatched.size}")
    for (n in p.notes) emit(
        "${n.start()} ${n.length()} ${n.channel()} ${noteName(n.pitch())} ${n.on.event.data[1]}",
    )
    for (l in p.unmatched) emit(
        "unmatched ${if (l.event.on()) "on" else "off"} ${l.event.tick} ${l.track} ${l.event.ch()} ${noteName(l.event.data[0])}",
    )
}

private fun execute(w: List<String>, read: () -> String) {
    val c = w[0]
    if (c == "HEX" || c == "TEXT") {
        val lines = List(w[2].toInt()) { read() }
        val s =
            if (c == "TEXT") textSong(lines)
            else Parser(lines.flatMap { it.split(' ').map { b -> b.toInt(16) } }).parse()
        songs[w[1]] = s
        emit("loaded ${w[1]} ${description(s)}")
        return
    }
    if (
        c !in
            listOf(
                "DECODE",
                "ENCODE",
                "TIMING",
                "NOTES",
                "STATS",
                "ROLL",
                "TRANSPOSE",
                "QUANTIZE",
                "VELOCITY",
                "TEMPO",
                "FILTER",
                "MERGE",
                "SPLIT",
                "COPY",
                "LIST",
                "RUNNING",
                "NOTEOFF",
            )
    )
        fail("unknown command")
    if (c == "LIST") {
        if (songs.isEmpty()) emit("no songs")
        else songs.forEach { (name, s) -> emit("$name ${description(s)}") }
        return
    }
    if (c == "RUNNING" || c == "NOTEOFF") {
        if (w[1] !in (if (c == "RUNNING") listOf("ON", "OFF") else listOf("ZERO", "KEEP")))
            fail("bad argument")
        if (c == "RUNNING") running = w[1] == "ON" else zeroOff = w[1] == "ZERO"
        emit("${c.lowercase()} ${w[1].lowercase()}")
        return
    }
    val s = songs[w[1]] ?: fail("no song ${w[1]}")
    var a = 0L
    var b = 0L
    var d = 0L
    if (c in listOf("TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO", "ROLL")) {
        a = w[2].toLong()
        if (w.size > 3) b = w[3].toLong()
        if (c == "ROLL") d = w[4].toLong()
        val valid =
            when (c) {
                "TRANSPOSE" -> a in -127L..127L && (w.size == 3 || b in 1L..16L)
                "QUANTIZE" -> a in 1L..1000000L && b in 0L..100L
                "VELOCITY" -> a in 0L..1000L && b in -127L..127L
                "TEMPO" -> a in 1L..1000L && b in 1L..1000L
                else ->
                    a in 0L..10000000L &&
                        b in 1L..10000000L &&
                        d in 1L..10000000L &&
                        b > a &&
                        (b - a + d - 1) / d <= 64
            }
        if (!valid) fail("bad argument")
    }
    if (c == "FILTER" && w.drop(2).any { it.toLong() !in 1L..16L }) fail("bad argument")
    if (c in listOf("TIMING", "STATS") && s.format == 2) fail("format 2 not supported")
    when (c) {
        "COPY" -> {
            songs[w[2]] = s.duplicate()
            emit("copied ${w[1]} to ${w[2]}")
        }
        "DECODE" -> {
            emit("HEADER ${s.format} ${s.tracks.size} ${s.division}")
            s.tracks.forEachIndexed { t, events -> events.forEach { emit(eventText(it, t)) } }
        }
        "ENCODE" -> encode(s)
        "TIMING" -> {
            for (l in global(s)) emit(
                "${l.event.tick} ${l.track} ${l.event.kind()} ${time(s, l.event.tick)} ${bar(s, l.event.tick)}",
            )
            emit("end ${s.length()} ${time(s, s.length())} ${bar(s, s.length())}")
        }
        "NOTES" -> printNotes(pairing(s))
        "TRANSPOSE" -> {
            var kept = 0
            val removed = mutableListOf<String>()
            s.tracks.forEachIndexed { t, track ->
                val iterator = track.iterator()
                while (iterator.hasNext()) {
                    val e = iterator.next()
                    if (
                        e.channel() && (e.code shr 4) <= 10 && (w.size == 3 || e.ch().toLong() == b)
                    ) {
                        val original = e.data[0]
                        val pitch = original + a
                        if (pitch !in 0L..127L) {
                            removed.add(
                                "dropped ${e.tick} $t ${e.kind()} ${e.ch()} ${noteName(original)}",
                            )
                            iterator.remove()
                        } else {
                            e.data[0] = pitch.toInt()
                            kept++
                        }
                    }
                }
            }
            emit("transposed $kept dropped ${removed.size}")
            removed.forEach { emit(it) }
        }
        "QUANTIZE" -> {
            val p = pairing(s)
            val targets = p.notes + p.unmatched.filter { it.event.on() }.map { Note(it, it) }
            var moved = 0
            for (n in targets) {
                val tick = n.start()
                val lower = tick / a * a
                val g = if (tick - lower <= lower + a - tick) lower else lower + a
                val delta = Math.floorDiv(2 * (g - tick) * b + 100, 200L)
                n.on.event.tick += delta
                if (n.off.event !== n.on.event) n.off.event.tick += delta
                if (delta != 0L) moved++
            }
            for (track in s.tracks) {
                val end = track.removeAt(track.lastIndex)
                track.sortBy { it.tick }
                end.tick = maxOf(end.tick, track.maxOfOrNull { it.tick } ?: 0L)
                track.add(end)
            }
            emit("quantized ${targets.size} moved $moved")
        }
        "VELOCITY" -> {
            var count = 0
            var clamped = 0
            for (l in global(s)) if (l.event.on()) {
                val v = (l.event.data[1] * a + 50) / 100 + b
                if (v !in 1L..127L) clamped++
                l.event.data[1] = v.coerceIn(1, 127).toInt()
                count++
            }
            emit("velocity $count clamped $clamped")
        }
        "TEMPO" -> {
            val edited = s.duplicate()
            var count = 0
            var atZero = false
            for (l in global(edited)) if (l.event.code == 337) {
                val v = (2 * value(l.event.data) * b + a) / (2 * a)
                if (v !in 1L..16777215L) fail("tempo out of range")
                l.event.data = bytes(v, 3)
                count++
                if (l.event.tick == 0L) atZero = true
            }
            val inserted = (1000000 * b + a) / (2 * a)
            if (!atZero) {
                if (inserted !in 1L..16777215L) fail("tempo out of range")
                edited.tracks[0].add(0, Event(0, 337, bytes(inserted, 3)))
            }
            songs[w[1]] = edited
            emit("scaled $count")
            if (!atZero) emit("inserted 0 0 TEMPO $inserted")
        }
        "FILTER" -> {
            val channels = w.drop(2).map { it.toInt() }.toSet()
            val before = s.count()
            s.tracks.forEach { it.removeAll { e -> e.channel() && e.ch() !in channels } }
            emit("removed ${before - s.count()}")
        }
        "MERGE" -> {
            if (s.format != 1) fail("not format 1")
            val original = s.tracks.size
            val length = s.length()
            val events = global(s).filter { !it.event.end() }.map { it.event }.toMutableList()
            events.add(Event(length, 303, mutableListOf()))
            s.tracks = mutableListOf(events)
            s.format = 0
            emit("merged $original tracks events ${s.count()}")
        }
        "SPLIT" -> {
            if (s.format != 0) fail("not format 0")
            val length = s.length()
            val groups = TreeMap<Int, MutableList<Event>>()
            groups[0] = mutableListOf()
            for (e in s.tracks[0]) if (!e.end())
                groups.getOrPut(if (e.channel()) e.ch() else 0) { mutableListOf() }.add(e)
            s.tracks = groups.values.toMutableList()
            s.tracks.forEach { it.add(Event(length, 303, mutableListOf())) }
            s.format = 1
            emit("split tracks ${s.tracks.size} events ${s.count()}")
        }
        "STATS" -> {
            val p = pairing(s)
            emit(description(s))
            emit("notes ${p.notes.size} unmatched ${p.unmatched.size}")
            for (ch in 1..16) {
                val notes = p.notes.filter { it.channel() == ch }
                if (notes.isNotEmpty())
                    emit(
                        "channel $ch notes ${notes.size} range ${noteName(notes.minOf { it.pitch() })} ${noteName(notes.maxOf { it.pitch() })}",
                    )
            }
            emit(
                if (p.notes.isEmpty()) "range none"
                else
                    "range ${noteName(p.notes.minOf { it.pitch() })} ${noteName(p.notes.maxOf { it.pitch() })}",
            )
            emit("length ${s.length()} ticks ${time(s, s.length())} ms")
            val changes = TreeMap<Long, Int>()
            for (n in p.notes) if (n.length() > 0) {
                changes[n.start()] = (changes[n.start()] ?: 0) + 1
                val end = n.start() + n.length()
                changes[end] = (changes[end] ?: 0) - 1
            }
            var active = 0
            var maximum = 0
            var first = 0L
            for ((tick, change) in changes) {
                active += change
                if (active > maximum) {
                    maximum = active
                    first = tick
                }
            }
            emit(if (maximum == 0) "polyphony 0" else "polyphony $maximum at $first")
        }
        "ROLL" -> {
            val p = pairing(s)
            val columns = ((b - a + d - 1) / d).toInt()
            var any = false
            for (pitch in 127 downTo 0) {
                val line = StringBuilder()
                var visible = false
                for (i in 0 until columns) {
                    val tick = a + i * d
                    val notes = p.notes.filter { it.pitch() == pitch }
                    val mark =
                        if (notes.any { tick <= it.start() && it.start() < tick + d }) '#'
                        else if (
                            notes.any { it.start() <= tick && tick < it.start() + it.length() }
                        )
                            '='
                        else '.'
                    line.append(mark)
                    if (mark != '.') visible = true
                }
                if (visible) {
                    emit("${noteName(pitch).padEnd(4)} $line")
                    any = true
                }
            }
            if (!any) emit("empty")
        }
    }
}

fun main() {
    val reader = System.`in`.bufferedReader()
    val n = reader.readLine().toInt()
    repeat(n) {
        val words = reader.readLine().split(' ')
        try {
            execute(words) { reader.readLine() }
        } catch (error: Failure) {
            emit("error: ${error.message}")
        }
    }
    print(output)
}
