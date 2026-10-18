data class Cue(val index: Long, val start: Long, val end: Long, val text: List<String>) {
    val duration get() = end-start
    val chars get() = text.sumOf { it.length.toLong() }
    val dialogue get() = text.any { it.startsWith("- ") }
}
data class Undo(val command: String, val cues: List<Cue>)
data class Item(val text: String, val kind: Int, val digit: Int = 0)
class Problem(message: String) : RuntimeException(message)

class Editor {
    private var cues = mutableListOf<Cue>()
    private val history = ArrayDeque<Undo>()
    private val schemas = mapOf("LIST" to "", "VALIDATE" to "", "SEARCH" to "X", "AT" to "T",
        "GAPS" to "g", "STATS" to "", "PRINT" to "", "TOVTT" to "", "TOASS" to "", "FRAMES" to "F",
        "SHIFT" to "I", "SHIFTFROM" to "PI", "SCALE" to "rr", "SYNC" to "PTPT", "SNAP" to "F",
        "FIXOVERLAP" to "g", "EXTEND" to "e", "TIME" to "PTT", "SORT" to "", "RENUMBER" to "",
        "MERGE" to "g", "SPLIT" to "w", "INSERT" to "PTTX", "DELETE" to "P", "TEXT" to "PX",
        "BALANCE" to "", "STRIP" to "", "CLEANHI" to "", "REPLACE" to "X", "UNDO" to "")
    private val modifying = setOf("SHIFT","SHIFTFROM","SCALE","SYNC","SNAP","FIXOVERLAP","EXTEND",
        "TIME","SORT","RENUMBER","MERGE","SPLIT","INSERT","DELETE","TEXT","BALANCE","STRIP","CLEANHI","REPLACE")
    private fun bad(): Nothing = throw Problem("bad arguments")
    private fun number(s: String): Long {
        if (!Regex("[0-9]{1,9}").matches(s)) bad()
        return s.toLong()
    }
    private fun time(s: String): Long {
        if (!Regex("[0-9]{2}:[0-5][0-9]:[0-5][0-9],[0-9]{3}").matches(s)) bad()
        return s.substring(0,2).toLong()*3600000+s.substring(3,5).toLong()*60000+
            s.substring(6,8).toLong()*1000+s.substring(9).toLong()
    }
    private fun fps(s: String): Pair<Long,Long> {
        val parts = s.split('/')
        if (parts.size !in 1..2) bad()
        val a = number(parts[0])
        val b = if (parts.size == 2) number(parts[1]) else 1L
        if (a !in 1..100000 || b !in 1..100000) bad()
        return a to b
    }
    private fun text(s: String): List<String> {
        val parts = s.split('|')
        if (parts.any { it.isEmpty() }) bad()
        return parts
    }
    private fun pad(n: Long, width: Int) = n.toString().padStart(width,'0')
    private fun srt(t: Long) = "${pad(t/3600000,2)}:${pad(t/60000%60,2)}:${pad(t/1000%60,2)},${pad(t%1000,3)}"
    private fun ass(t: Long): String {
        val c = (t+5)/10
        return "${c/360000}:${pad(c/6000%60,2)}:${pad(c/100%60,2)}.${pad(c%100,2)}"
    }
    private fun decimal(v: Long) = "${v/100}.${pad(v%100,2)}"
    private fun round(numerator: Long, denominator: Long): Long {
        val a = if (denominator < 0) -numerator else numerator
        val b = kotlin.math.abs(denominator)
        return Math.floorDiv(2*a+b,2*b)
    }
    private fun words(lines: List<String>) = lines.joinToString(" ").split(' ').filter { it.isNotEmpty() }
    private fun normalize(s: String) = words(listOf(s)).joinToString(" ")
    private fun wrap(lines: List<String>, width: Long): List<String> {
        val result = mutableListOf<String>()
        for (word in words(lines)) {
            if (result.isEmpty() || result.last().length+1+word.length > width) {
                result.add(word)
            } else {
                result[result.lastIndex] += " $word"
            }
        }
        return result
    }
    private fun markup(line: String): List<Item> {
        val result = mutableListOf<Item>()
        var p = 0
        while (p < line.length) {
            var token = listOf("<i>","</i>","<b>","</b>","<u>","</u>").firstOrNull { line.startsWith(it,p) }
            var kind = if (token == null) 0 else 1
            var digit = 0
            if (token == null && line.startsWith("</font>",p)) {
                token = "</font>"
                kind = 2
            }
            if (token == null && line.startsWith("<font",p) && p+5 < line.length && line[p+5] in " >") {
                val end = line.indexOf('>',p+5)
                if (end >= 0) {
                    token = line.substring(p,end+1)
                    kind = 2
                }
            }
            if (token == null && p+6 <= line.length && line.startsWith("{\\an",p) && line[p+4] in '1'..'9' && line[p+5] == '}') {
                token = line.substring(p,p+6)
                kind = 3
                digit = line[p+4]-'0'
            }
            val item = token ?: line.substring(p,p+1)
            result.add(Item(item,kind,digit))
            p += item.length
        }
        return result
    }
    private fun listing(position: Int, cue: Cue) = "$position ${cue.index} ${srt(cue.start)} ${srt(cue.end)} ${cue.text.joinToString("|")}"
    fun load(blocks: List<List<String>>): List<String> {
        val output = mutableListOf<String>()
        var badCount = 0
        for ((i,block) in blocks.withIndex()) {
            var reason = ""
            var start = 0L
            var end = 0L
            if (!Regex("[0-9]{1,6}").matches(block[0])) {
                reason = "index"
            } else {
                try {
                    if (block.size < 2 || block[1].length != 29 || block[1].substring(12,17) != " --> ") bad()
                    start = time(block[1].substring(0,12))
                    end = time(block[1].substring(17))
                } catch (problem: Problem) {
                    reason = "time"
                }
                if (reason.isEmpty() && block.size < 3) reason = "no text"
            }
            if (reason.isNotEmpty()) {
                output.add("BAD CUE ${i+1}: $reason")
                badCount++
            } else {
                cues.add(Cue(block[0].toLong(),start,end,block.drop(2)))
            }
        }
        output.add("LOAD cues=${cues.size} bad=$badCount")
        return output
    }
    fun execute(line: String): List<String> {
        val command = line.substringBefore(' ')
        var schema = schemas[command] ?: throw Problem("unknown command")
        if (command == "DELETE" && line.split(' ').size == 3) schema = "PP"
        val tokens = if (schema.endsWith('X')) line.split(' ',limit = schema.length+1) else line.split(' ')
        if (tokens.size != schema.length+1) bad()
        val args = tokens.drop(1)
        val values = LongArray(args.size)
        for ((i,arg) in args.withIndex()) {
            when (val type = schema[i]) {
                'T' -> values[i] = time(arg)
                'F' -> fps(arg)
                'X' -> {
                    if (command in setOf("INSERT","TEXT")) text(arg)
                    if (command == "REPLACE") {
                        val parts = arg.split('|')
                        if (parts.size != 2 || parts.any { it.isEmpty() }) bad()
                    }
                }
                else -> {
                    val negative = type == 'I' && arg.startsWith('-')
                    values[i] = number(if (negative) arg.drop(1) else arg)*(if (negative) -1 else 1)
                    val v = values[i]
                    if (type == 'P' && v < 1 || type == 'r' && v !in 1..100000 || type == 'g' && v > 60000 ||
                        type == 'e' && v !in 1..60000 || type == 'w' && v !in 10..80) bad()
                }
            }
        }
        if (command == "DELETE" && values.size == 2 && values[1] < values[0]) bad()
        for (i in args.indices) {
            if (schema[i] == 'P' && values[i] > cues.size+(if (command == "INSERT") 1 else 0)) {
                throw Problem("no cue ${values[i]}")
            }
        }
        if (command == "SYNC" && cues[values[0].toInt()-1].start == cues[values[2].toInt()-1].start) {
            throw Problem("sync points coincide")
        }
        if (command == "UNDO") {
            if (history.isEmpty()) throw Problem("nothing to undo")
            val undo = history.removeLast()
            cues = undo.cues.toMutableList()
            return listOf("UNDO command=${undo.command}")
        }
        if (command in modifying) history.addLast(Undo(command,cues.toList()))
        val output = mutableListOf<String>()
        val n = cues.size
        val v = values.firstOrNull() ?: 0L
        when (command) {
            "LIST", "AT", "SEARCH", "GAPS" -> {
                var count = 0
                for ((i,cue) in cues.withIndex()) {
                    if (command == "LIST" || command == "AT" && cue.start <= v && v < cue.end) {
                        output.add(listing(i+1,cue))
                        count++
                    }
                    if (command == "SEARCH") {
                        val found = cue.text.firstOrNull { args[0] in it }
                        if (found != null) {
                            output.add("${i+1} ${srt(cue.start)} $found")
                            count++
                        }
                    }
                    if (command == "GAPS" && i+1 < n && cues[i+1].start-cue.end < v) {
                        output.add("${i+1} ${i+2} ${cues[i+1].start-cue.end}")
                        count++
                    }
                }
                if (command != "LIST") {
                    val label = when (command) {
                        "AT" -> "active"
                        "SEARCH" -> "found"
                        else -> "count"
                    }
                    output.add("$command $label=$count")
                }
            }
            "VALIDATE" -> {
                for ((i,c) in cues.withIndex()) {
                    val d = c.duration
                    val p = "cue ${i+1}: "
                    if (c.index != (i+1).toLong()) output.add("${p}index ${c.index} (expected ${i+1})")
                    if (d <= 0) output.add("${p}end not after start")
                    if (i > 0 && c.start < cues[i-1].end) output.add("${p}overlaps previous by ${cues[i-1].end-c.start} ms")
                    if (d in 1..699) output.add("${p}too short ($d ms)")
                    if (d > 7000) output.add("${p}too long ($d ms)")
                    for ((j,t) in c.text.withIndex()) {
                        if (t.length > 42) output.add("${p}line ${j+1} too long (${t.length} chars)")
                    }
                    if (c.text.size >= 3) output.add("${p}too many lines (${c.text.size})")
                    if (d > 0 && c.chars*1000 > 21*d) output.add("${p}too fast (${decimal(c.chars*100000/d)} cps)")
                }
                output.add("VALIDATE problems=${output.size}")
            }
            "STATS" -> {
                output.add("STATS cues=$n")
                if (n > 0) {
                    val durations = cues.map { maxOf(0,it.duration) }
                    val total = durations.sum()
                    val chars = cues.filter { it.duration > 0 }.sumOf { it.chars }
                    val longest = durations.maxOrNull()!!
                    output.add("duration total=${srt(total)} mean=${srt(total/n)}")
                    output.add("speed "+if (total == 0L) "-" else decimal(chars*100000/total))
                    output.add("longest cue=${durations.indexOf(longest)+1} duration=${srt(longest)}")
                    if (n == 1) output.add("gap none")
                    else {
                        val gaps = (0 until n-1).map { cues[it+1].start-cues[it].end }
                        val gap = gaps.maxOrNull()!!
                        output.add("gap cue=${gaps.indexOf(gap)+1} ms=$gap")
                    }
                }
            }
            "PRINT", "TOVTT", "TOASS" -> {
                if (command == "TOVTT") output.addAll(listOf("WEBVTT",""))
                if (command == "TOASS") output.addAll(listOf("[Events]","Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"))
                for (c in cues) {
                    var code = 0
                    val lines = c.text.map { t ->
                        val converted = buildString {
                            for (item in markup(t)) {
                                if (code == 0 && item.kind == 3) code = item.digit
                                when {
                                    command == "PRINT" -> append(item.text)
                                    command == "TOASS" -> {
                                        if (item.kind == 1) {
                                            val closing = item.text.startsWith("</")
                                            val tag = item.text[if (closing) 2 else 1]
                                            append("{\\$tag${if (closing) 0 else 1}}")
                                        } else if (item.kind != 2) append(item.text)
                                    }
                                    item.kind == 1 -> append(item.text)
                                    item.kind == 0 -> append(when (item.text) {
                                        "&" -> "&amp;"
                                        "<" -> "&lt;"
                                        ">" -> "&gt;"
                                        else -> item.text
                                    })
                                }
                            }
                        }
                        if (command == "TOVTT") converted.trim(' ') else converted
                    }.filter { command != "TOVTT" || it.isNotEmpty() }
                    if (command == "TOASS") output.add("Dialogue: 0,${ass(c.start)},${ass(c.end)},Default,,0,0,0,,${lines.joinToString("\\N")}")
                    else if (lines.isNotEmpty()) {
                        var settings = ""
                        if (command == "TOVTT" && code != 0) {
                            if (code >= 7) settings += " line:0"
                            else if (code >= 4) settings += " line:50%"
                            if (code%3 == 1) settings += " align:start"
                            if (code%3 == 0) settings += " align:end"
                        }
                        output.add(c.index.toString())
                        val times = "${srt(c.start)} --> ${srt(c.end)}"
                        output.add((if (command == "TOVTT") times.replace(',','.') else times)+settings)
                        output.addAll(lines)
                        output.add("")
                    }
                }
            }
            "FRAMES" -> {
                val (a,b) = fps(args[0])
                for ((i,c) in cues.withIndex()) output.add("${i+1} ${c.start*a/(1000*b)} ${c.end*a/(1000*b)}")
            }
            "SHIFT", "SHIFTFROM", "SCALE", "SYNC", "SNAP" -> {
                val first = if (command == "SHIFTFROM") v.toInt()-1 else 0
                val delta = if (command == "SHIFTFROM") values[1] else v
                val s1 = if (command == "SYNC") cues[v.toInt()-1].start else 0L
                val s2 = if (command == "SYNC") cues[values[2].toInt()-1].start else 0L
                val (a,b) = if (command == "SNAP") fps(args[0]) else (1L to 1L)
                var clamped = 0
                var changed = 0
                for (i in first until n) {
                    val c = cues[i]
                    var clamp = false
                    val times = listOf(c.start,c.end).map { old ->
                        val next = when (command) {
                            "SCALE" -> round(old*v,values[1])
                            "SYNC" -> round(values[1]*(s2-s1)+(old-s1)*(values[3]-values[1]),s2-s1)
                            "SNAP" -> round(round(old*a,1000*b)*1000*b,a)
                            else -> old+delta
                        }
                        if (next < 0) clamp = true
                        val result = maxOf(0,next)
                        if (result != old) changed++
                        result
                    }
                    if (clamp) clamped++
                    cues[i] = c.copy(start = times[0],end = times[1])
                }
                output.add(if (command == "SNAP") "SNAP changed=$changed" else
                    "$command cues=${n-first}"+(if (command == "SCALE") "" else " clamped=$clamped"))
            }
            "FIXOVERLAP", "EXTEND" -> {
                var changed = 0
                var failed = 0
                for (i in cues.indices) {
                    val c = cues[i]
                    var end = c.end
                    if (command == "FIXOVERLAP" && i+1 < n && end > cues[i+1].start-v) {
                        val candidate = cues[i+1].start-v
                        if (candidate > c.start) {
                            end = candidate
                            changed++
                        } else {
                            output.add("cue ${i+1}: cannot fix")
                            failed++
                        }
                    }
                    if (command == "EXTEND" && c.duration < v) {
                        val candidate = if (i+1 < n) minOf(c.start+v,cues[i+1].start) else c.start+v
                        if (candidate > end) {
                            end = candidate
                            changed++
                        }
                    }
                    cues[i] = c.copy(end = end)
                }
                output.add(if (command == "FIXOVERLAP") "FIXOVERLAP fixed=$changed failed=$failed" else
                    "EXTEND extended=$changed short=${cues.count { it.duration < v }}")
            }
            "TIME" -> {
                cues[v.toInt()-1] = cues[v.toInt()-1].copy(start = values[1],end = values[2])
                output.add("TIME cue=$v")
            }
            "SORT" -> {
                val old = cues.toList()
                cues.sortWith(compareBy<Cue> { it.start }.thenBy { it.end })
                output.add("SORT moved=${cues.indices.count { old[it] !== cues[it] }}")
            }
            "RENUMBER" -> {
                val changed = cues.indices.count { cues[it].index != (it+1).toLong() }
                cues = cues.mapIndexed { i,c -> c.copy(index = (i+1).toLong()) }.toMutableList()
                output.add("RENUMBER changed=$changed")
            }
            "MERGE" -> {
                val result = mutableListOf<Cue>()
                var merged = 0
                for (b in cues) {
                    val a = result.lastOrNull()
                    if (a != null && b.start-a.end < v && !a.dialogue && !b.dialogue) {
                        val wrapped = wrap(a.text+b.text,42)
                        if (wrapped.size <= 2) {
                            result[result.lastIndex] = a.copy(end = maxOf(a.end,b.end),text = wrapped)
                            merged++
                            continue
                        }
                    }
                    result.add(b)
                }
                cues = result
                output.add("MERGE merged=$merged cues=${cues.size}")
            }
            "SPLIT" -> {
                val result = mutableListOf<Cue>()
                var split = 0
                for (c in cues) {
                    if (c.duration <= 0 || c.dialogue) {
                        result.add(c)
                        continue
                    }
                    val wrapped = wrap(c.text,v)
                    if (wrapped.size <= 2) {
                        result.add(c.copy(text = wrapped))
                        continue
                    }
                    split++
                    val parts = wrapped.chunked(2)
                    val counts = parts.map { it.sumOf { line2 -> line2.length.toLong() } }
                    val total = counts.sum()
                    val durations = counts.map { c.duration*it/total }.toMutableList()
                    val order = parts.indices.sortedWith(compareByDescending<Int> { c.duration*counts[it]%total }.thenBy { it })
                    for (i in 0 until (c.duration-durations.sum()).toInt()) durations[order[i]]++
                    var start = c.start
                    for (i in parts.indices) {
                        result.add(Cue(c.index,start,start+durations[i],parts[i]))
                        start += durations[i]
                    }
                }
                cues = result
                output.add("SPLIT split=$split cues=${cues.size}")
            }
            "INSERT" -> {
                cues.add(v.toInt()-1,Cue(v,values[1],values[2],text(args[3])))
                output.add("INSERT cue=$v cues=${cues.size}")
            }
            "DELETE" -> {
                val last = values.getOrElse(1) { v }
                cues.subList(v.toInt()-1,last.toInt()).clear()
                output.add("DELETE removed=${last-v+1} cues=${cues.size}")
            }
            "TEXT" -> {
                val lines = text(args[1])
                cues[v.toInt()-1] = cues[v.toInt()-1].copy(text = lines)
                output.add("TEXT cue=$v lines=${lines.size}")
            }
            "BALANCE" -> {
                var changed = 0
                var skipped = 0
                var dialogue = 0
                for ((i,c) in cues.withIndex()) {
                    if (c.dialogue) {
                        dialogue++
                        continue
                    }
                    val parts = words(c.text)
                    val joined = parts.joinToString(" ")
                    var best: List<String>? = if (joined.length <= 42) listOf(joined) else null
                    var difference = Int.MAX_VALUE
                    var firstLength = Int.MAX_VALUE
                    if (joined.length > 42) {
                        for (j in 1 until parts.size) {
                            val a = parts.take(j).joinToString(" ")
                            val b = parts.drop(j).joinToString(" ")
                            val d = kotlin.math.abs(a.length-b.length)
                            if (a.length <= 42 && b.length <= 42 && (d < difference || d == difference && a.length < firstLength)) {
                                best = listOf(a,b)
                                difference = d
                                firstLength = a.length
                            }
                        }
                    }
                    if (best == null) skipped++
                    else if (best != c.text) {
                        changed++
                        cues[i] = c.copy(text = best)
                    }
                }
                output.add("BALANCE changed=$changed skipped=$skipped dialogue=$dialogue")
            }
            "STRIP", "CLEANHI" -> {
                val result = mutableListOf<Cue>()
                var tags = 0
                var segments = 0
                var labels = 0
                var removed = 0
                for (c in cues) {
                    val lines = mutableListOf<String>()
                    for (t in c.text) {
                        val builder = StringBuilder()
                        if (command == "STRIP") {
                            for (item in markup(t)) {
                                if (item.kind == 0) {
                                    builder.append(item.text)
                                } else {
                                    tags++
                                }
                            }
                        } else {
                            var p = 0
                            while (p < t.length) {
                                val end = when (t[p]) {
                                    '[' -> t.indexOf(']',p+1)
                                    '(' -> t.indexOf(')',p+1)
                                    else -> -1
                                }
                                if (end >= 0) {
                                    segments++
                                    p = end+1
                                } else {
                                    builder.append(t[p])
                                    p++
                                }
                            }
                        }
                        var cleaned = if (command == "STRIP") builder.toString().trim(' ') else normalize(builder.toString())
                        if (command == "CLEANHI") {
                            val prefix = if (cleaned.startsWith("- ")) "- " else ""
                            val body = cleaned.drop(prefix.length)
                            val colon = body.indexOf(':')
                            if (colon > 0 && Regex("[A-Z][A-Z0-9 ]*").matches(body.take(colon))) {
                                labels++
                                cleaned = normalize(prefix+body.drop(colon+1))
                            }
                        }
                        if (cleaned.isEmpty() || command == "CLEANHI" && cleaned == "-") {
                            removed++
                        } else {
                            lines.add(cleaned)
                        }
                    }
                    if (lines.isNotEmpty()) result.add(c.copy(text = lines))
                }
                val removedCues = n-result.size
                cues = result
                output.add(if (command == "STRIP") "STRIP tags=$tags removed_lines=$removed removed_cues=$removedCues" else
                    "CLEANHI segments=$segments labels=$labels removed_lines=$removed removed_cues=$removedCues")
            }
            "REPLACE" -> {
                val (old,replacement) = args[0].split('|')
                var count = 0
                var changed = 0
                for ((i,c) in cues.withIndex()) {
                    val before = count
                    val lines = c.text.map { t ->
                        val result = StringBuilder()
                        var cursor = 0
                        while (true) {
                            val found = t.indexOf(old,cursor)
                            if (found < 0) break
                            result.append(t.substring(cursor,found)).append(replacement)
                            cursor = found+old.length
                            count++
                        }
                        result.append(t.substring(cursor)).toString()
                    }
                    if (count > before) changed++
                    cues[i] = c.copy(text = lines)
                }
                output.add("REPLACE count=$count cues=$changed")
            }
        }
        return output
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val blocks = mutableListOf<List<String>>()
    var block = mutableListOf<String>()
    while (true) {
        val line = input.readLine()
        if (line == "###") break
        if (line.isEmpty()) {
            if (block.isNotEmpty()) blocks.add(block)
            block = mutableListOf()
        } else block.add(line)
    }
    if (block.isNotEmpty()) blocks.add(block)
    val editor = Editor()
    fun emit(lines: List<String>) {
        for (line in lines) {
            output.write(line)
            output.newLine()
        }
    }
    emit(editor.load(blocks))
    repeat(input.readLine().toInt()) {
        try {
            emit(editor.execute(input.readLine()))
        } catch (problem: Problem) {
            emit(listOf("ERROR ${problem.message}"))
        }
    }
    output.flush()
}
