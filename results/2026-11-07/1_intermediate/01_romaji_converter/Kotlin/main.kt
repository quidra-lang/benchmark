class Problem(message: String) : RuntimeException(message)
data class Meta(val id: String, val row: String, val dan: String, val contracted: Boolean)
data class Mora(val id: String, val column: Int)
data class Word(val text: String, val start: Int, val pattern: Int = 0, val morae: List<Mora> = emptyList())
data class MatchResult(val id: String, val length: Int)
data class LongInfo(val paired: BooleanArray, val elements: BooleanArray, val vowels: CharArray)
data class Element(val base: String, val voice: Int, val size: Int)

class Converter {
    private val systems = listOf("HEPBURN","TRADITIONAL","KUNREI","NIHON","WAPURO")
    private val rows = listOf("a","ka","sa","ta","na","ha","ma","ya","ra","wa","ga","za","da","ba","pa")
    private val gojuon = "a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N"
    private val iroha = "i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N"
    private val counts = mapOf("CONVERT" to 2,"NORMALIZE" to 0,"REVERSE" to 1,"VALID" to 1,
            "DETECT" to 0,"DIFF" to 2,"SAME" to 2,"MORAE" to 1,"SYLLABLES" to 1,
            "ROW" to 1,"STATS" to 1,"SORT" to 1,"INDEX" to 1,"FIND" to 2,
            "HAIKU" to 1,"KAIBUN" to 1,"SHIRITORI" to 1)
    private val metadata = linkedMapOf<String,Meta>()
    private val readers = mutableMapOf<String,MutableMap<String,String>>()
    private var longSetting = "KEEP"
    private var caseSetting = "KEEP"
    private var orderSetting = "GOJUON"

    init {
        val contents = listOf("a i u e o", "ka ki ku ke ko", "sa si su se so", "ta ti tu te to",
            "na ni nu ne no", "ha hi hu he ho", "ma mi mu me mo", "ya yu yo", "ra ri ru re ro",
            "wa wi we wo", "ga gi gu ge go", "za zi zu ze zo", "da di du de do", "ba bi bu be bo", "pa pi pu pe po")
        for ((i,row) in contents.withIndex()) {
            for (id in row.split(' ')) {
                metadata[id] = Meta(id,rows[i],id.last().toString(),false)
            }
        }
        for (row in listOf("ka","sa","ta","na","ha","ma","ra","ga","za","da","ba","pa")) {
            for (dan in listOf("ya","yu","yo")) {
                val id = row.take(1)+dan
                metadata[id] = Meta(id,row,dan,true)
            }
        }
        for (system in systems + "ANY") {
            readers[system] = mutableMapOf()
        }
        for (meta in metadata.values) {
            for (system in systems) {
                val spelling = spelling(system,meta.id)
                readers.getValue(system).putIfAbsent(spelling,meta.id)
                readers.getValue("ANY").putIfAbsent(spelling,meta.id)
            }
        }
    }
    private fun fail(message: String): Nothing = throw Problem(message)
    private fun column(value: Int, message: String): Nothing = fail("col $value: $message")
    private fun letter(c: Char): Boolean = c in 'a'..'z' || c in 'A'..'Z'
    private fun begins(text: String, choices: String): Boolean = text.isNotEmpty() && text[0] in choices
    private fun regular(id: String): Boolean = id in metadata
    private fun vowel(id: String): Boolean = id.length == 1 && id[0] in "aiueo"
    private fun devoice(id: String): String {
        val index = "gzdbp".indexOf(id[0])
        return if (index < 0) id else "ksthh"[index]+id.substring(1)
    }
    private fun baseRow(row: String): String = when (row) {
        "ga" -> "ka"
        "za" -> "sa"
        "da" -> "ta"
        "ba", "pa" -> "ha"
        else -> row
    }
    private fun voice(row: String): Int = if (row == "pa") 2 else if (row in setOf("ga","za","da","ba")) 1 else 0
    private fun spelling(system: String, id: String): String {
        val hepburn = system in setOf("HEPBURN","TRADITIONAL")
        if (hepburn || system == "WAPURO") {
            val result = when (id) {
                "si" -> "shi"
                "ti" -> "chi"
                "tu" -> "tsu"
                "hu" -> "fu"
                "zi" -> "ji"
                "di" -> if (hepburn) "ji" else id
                "du" -> if (hepburn) "zu" else id
                "wi" -> if (hepburn) "i" else id
                "we" -> if (hepburn) "e" else id
                "wo" -> if (hepburn) "o" else id
                else -> id
            }
            if (id.startsWith("sy")) {
                return "sh"+id.last()
            }
            if (id.startsWith("ty")) {
                return "ch"+id.last()
            }
            if (id.startsWith("zy") || hepburn && id.startsWith("dy")) {
                return "j"+id.last()
            }
            return result
        }
        if (system == "KUNREI") {
            return when (id) {
                "di" -> "zi"
                "du" -> "zu"
                "wi" -> "i"
                "we" -> "e"
                "wo" -> "o"
                else -> if (id.startsWith("dy")) "z"+id.substring(1) else id
            }
        }
        return id
    }
    private fun match(text: String, position: Int, system: String): MatchResult? {
        for (length in minOf(3,text.length-position) downTo 1) {
            val id = readers.getValue(system)[text.substring(position,position+length)]
            if (id != null) {
                return MatchResult(id,length)
            }
        }
        return null
    }
    private fun parse(word: Word, system: String): List<Mora> {
        val text = word.text.lowercase()
        val result = mutableListOf<Mora>()
        val normalize = system == "ANY"
        var p = 0
        while (p < text.length) {
            val c = text[p]
            val next = text.getOrElse(p+1) { '\u0000' }
            val at = word.start+p+1
            val id: String
            val advance: Int
            if (c == '-') {
                if (result.isEmpty() || !regular(result.last().id)) {
                    column(at,"misplaced long mark")
                }
                id = "L"
                advance = 1
            } else if (c == '\'') {
                column(at,"misplaced apostrophe")
            } else {
                val syllable = match(text,p,system)
                if (syllable != null) {
                    id = syllable.id
                    advance = syllable.length
                } else if ((normalize || system == "WAPURO") && text.startsWith("xtu",p)) {
                    id = "Q"
                    advance = 3
                } else if (c == 'n') {
                    id = "N"
                    advance = if (normalize) {
                        val third = text.getOrElse(p+2) { '\u0000' }
                        if (next == '\'' || next == 'n' && third !in "aiueoy'") 2 else 1
                    } else if (system == "WAPURO") {
                        if (next == 'n') 2 else 1
                    } else if (next == '\'') 2 else 1
                } else if ((normalize || system == "TRADITIONAL") && c == 'm' && next in "bmp") {
                    id = "N"
                    advance = 1
                } else if (letter(c) && c !in "aiueon" && c == next && match(text,p+1,system) != null) {
                    id = "Q"
                    advance = 1
                } else if ((normalize || system in setOf("HEPBURN","TRADITIONAL")) &&
                    c == 't' && text.startsWith("ch",p+1) && match(text,p+1,system) != null) {
                    id = "Q"
                    advance = 1
                } else {
                    column(at,"unknown syllable")
                }
            }
            result.add(Mora(id,at))
            p += advance
        }
        return result
    }
    private fun scan(text: String): List<Word> = Regex("[A-Za-z'-]+").findAll(text)
        .map { Word(it.value,it.range.first) }.toList()
    private fun pattern(text: String): Int {
        val letters = text.filter(::letter)
        if (letters.all { it in 'a'..'z' }) {
            return 0
        }
        if (text[0] in 'A'..'Z' && letters.drop(1).all { it in 'a'..'z' }) {
            return 1
        }
        if (letters.length >= 2 && letters.all { it in 'A'..'Z' }) {
            return 2
        }
        return -1
    }
    private fun longInfo(morae: List<Mora>): LongInfo {
        val paired = BooleanArray(morae.size)
        val elements = BooleanArray(morae.size)
        val vowels = CharArray(morae.size)
        for (i in morae.indices) {
            if (morae[i].id == "L") {
                elements[i] = true
                vowels[i] = morae[i-1].id.last()
            }
        }
        var p = 0
        while (p+1 < morae.size) {
            val a = morae[p].id
            val b = morae[p+1].id
            val v = a.last()
            if (regular(a) && vowel(b) && (v == b.last() || v == 'o' && b == "u" || v == 'e' && b == "i")) {
                paired[p+1] = true
                if (v == 'o' && b in setOf("o","u") || v == 'u' && b == "u") {
                    elements[p+1] = true
                    vowels[p+1] = v
                }
                p += 2
            } else {
                p++
            }
        }
        return LongInfo(paired,elements,vowels)
    }
    private fun parts(word: Word, system: String, longMode: String): List<String> {
        val info = longInfo(word.morae)
        val result = mutableListOf<String>()
        for ((i,mora) in word.morae.withIndex()) {
            val id = mora.id
            val nextId = word.morae.getOrNull(i+1)?.id ?: ""
            val next = if (regular(nextId)) spelling(system,nextId) else ""
            val part: String
            if (info.elements[i]) {
                val v = info.vowels[i]
                part = when (longMode) {
                    "KEEP" -> if (id == "L") "-" else spelling(system,id)
                    "DROP" -> ""
                    "PASSPORT" -> if (v == 'o' && !begins(next,"aiueo")) "h" else ""
                    "HYPHEN" -> "-"
                    else -> v.toString()
                }
            } else if (regular(id)) {
                part = spelling(system,id)
            } else if (id == "N") {
                part = if (system == "WAPURO") {
                    if (nextId == "N" || begins(next,"aiueoyn")) "nn" else "n"
                } else if (system == "TRADITIONAL" && begins(next,"bmp")) "m"
                else if (begins(next,"aiueoy")) "n'" else "n"
            } else {
                part = if (next.isNotEmpty() && !begins(next,"aiueon")) {
                    if (system in setOf("HEPBURN","TRADITIONAL") && next.startsWith("ch")) "t" else next.take(1)
                } else if (system == "WAPURO") "xtu"
                else column(mora.column,"small tsu cannot be written")
            }
            result.add(part)
        }
        return result
    }
    private fun write(word: Word, system: String, longMode: String, caseMode: String): String {
        var result = parts(word,system,longMode).joinToString("")
        val pattern = when (caseMode) {
            "KEEP" -> word.pattern
            "LOWER" -> 0
            "TITLE" -> 1
            else -> 2
        }
        if (pattern == 1) {
            result = result.take(1).uppercase()+result.drop(1)
        }
        if (pattern == 2) {
            result = result.uppercase()
        }
        return result
    }
    private fun canonical(word: Word, system: String): String = write(word,system,"KEEP","KEEP")
    private fun ids(word: Word): List<String> = word.morae.map { it.id }
    private fun loose(word: Word): List<String> {
        val info = longInfo(word.morae)
        return word.morae.filterIndexed { i,_ -> !info.elements[i] }.map { it.id }
    }
    private fun elements(word: Word): List<Element> {
        val result = mutableListOf<Element>()
        for (mora in word.morae) {
            val id = mora.id
            if (id == "L") {
                continue
            }
            if (id == "N") {
                result.add(Element("N",0,0))
            } else if (id == "Q") {
                result.add(Element("tu",0,1))
            } else {
                val meta = metadata.getValue(id)
                if (meta.contracted) {
                    result.add(Element(devoice(meta.row.take(1)+"i"),voice(meta.row),0))
                    result.add(Element("y"+id.last(),0,1))
                } else {
                    result.add(Element(devoice(id),voice(meta.row),0))
                }
            }
        }
        return result
    }
    private fun compare(a: List<Int>, b: List<Int>): Int {
        for (i in 0 until minOf(a.size,b.size)) {
            if (a[i] != b[i]) {
                return a[i].compareTo(b[i])
            }
        }
        return a.size.compareTo(b.size)
    }
    private fun sorted(words: List<Word>): List<Word> {
        val ranks = (if (orderSetting == "GOJUON") gojuon else iroha).split(' ').withIndex().associate { it.value to it.index }
        fun key(word: Word): List<List<Int>> {
            val collation = elements(word)
            return listOf(collation.map { ranks.getValue(it.base) },collation.map { it.voice },
                collation.map { it.size },word.morae.map { if (it.id == "L") 1 else 0 })
        }
        return words.map { it to key(it) }.sortedWith { a,b ->
            val left = a.second
            val right = b.second
            var result = 0
            for (i in 0 until 4) {
                result = compare(left[i],right[i])
                if (result != 0) {
                    break
                }
            }
            result
        }.map { it.first }
    }
    private fun patternMorae(pattern: String, system: String): List<String> {
        if (!Regex("[a-z'?*\\-]+").matches(pattern)) {
            fail("invalid pattern")
        }
        val result = mutableListOf<String>()
        var start = 0
        try {
            for (i in 0..pattern.length) {
                if (i == pattern.length || pattern[i] == '?' || pattern[i] == '*') {
                    if (i > start) {
                        result.addAll(parse(Word(pattern.substring(start,i),0),system).map { it.id })
                    }
                    if (i < pattern.length) {
                        result.add(pattern[i].toString())
                    }
                    start = i+1
                }
            }
        } catch (problem: Problem) {
            fail("invalid pattern")
        }
        return result
    }
    private fun matches(pattern: List<String>, word: List<String>): Boolean {
        var dp = BooleanArray(word.size+1)
        dp[0] = true
        for (token in pattern) {
            val next = BooleanArray(word.size+1)
            next[0] = token == "*" && dp[0]
            for (j in 1..word.size) {
                next[j] = if (token == "*") dp[j] || next[j-1] else dp[j-1] && (token == "?" || token == word[j-1])
            }
            dp = next
        }
        return dp[word.size]
    }
    private fun detect(words: List<Word>): String = systems.joinToString(" ") { system ->
        val verdict = try {
            val parsed = words.map { it.copy(morae = parse(it,system)) }
            if (parsed.all { it.text == canonical(it,system) }) "canonical" else "readable"
        } catch (problem: Problem) {
            "error"
        }
        "$system=$verdict"
    }
    fun execute(line: String): String {
        val command = line.substringBefore(' ')
        if (command !in counts && command !in setOf("SET","TABLE")) {
            fail("unknown command $command")
        }
        if (command in setOf("SET","TABLE")) {
            val tokens = line.split(' ')
            if (tokens.size < 3) {
                fail("missing argument")
            }
            if (tokens.size > 3) {
                fail("too many arguments")
            }
            if (command == "SET") {
                val allowed = when (tokens[1]) {
                    "LONG" -> setOf("KEEP","DROP","PASSPORT","HYPHEN","DOUBLE")
                    "CASE" -> setOf("KEEP","LOWER","UPPER","TITLE")
                    "ORDER" -> setOf("GOJUON","IROHA")
                    else -> fail("unknown option ${tokens[1]}")
                }
                if (tokens[2] !in allowed) {
                    fail("unknown value ${tokens[2]}")
                }
                when (tokens[1]) {
                    "LONG" -> longSetting = tokens[2]
                    "CASE" -> caseSetting = tokens[2]
                    "ORDER" -> orderSetting = tokens[2]
                }
                return "${tokens[1]}=${tokens[2]}"
            }
            if (tokens[1] !in systems) {
                fail("unknown system ${tokens[1]}")
            }
            if (tokens[2] !in rows) {
                fail("unknown row ${tokens[2]}")
            }
            return metadata.values.filter { it.row == tokens[2] }.joinToString(" ") { spelling(tokens[1],it.id) }
        }
        val fixed = counts.getValue(command)
        val chunks = line.split(' ',limit = fixed+2)
        if (chunks.size < fixed+2) {
            fail("missing argument")
        }
        val arguments = chunks.subList(1,fixed+1)
        val text = chunks[fixed+1]
        val systemCount = if (command in setOf("NORMALIZE","DETECT")) 0 else if (command in setOf("CONVERT","DIFF","SAME")) 2 else 1
        for (i in 0 until systemCount) {
            if (arguments[i] !in systems) {
                fail("unknown system ${arguments[i]}")
            }
        }
        val searchPattern = if (command == "FIND") patternMorae(arguments[1],arguments[0]) else emptyList()
        val slash = command in setOf("SAME","HAIKU")
        for ((i,c) in text.withIndex()) {
            if (!letter(c) && c != '\'' && c != '-' && c !in " 0123456789.,!?;:()\"" && !(slash && c == '/')) {
                column(i+1,"invalid character")
            }
        }
        val poem = text.split('/')
        if (command == "SAME" && (poem.size != 2 || scan(poem[0]).isEmpty() || scan(poem[1]).isEmpty())) {
            fail("expected two texts")
        }
        if (command == "HAIKU") {
            if (poem.size != 3 && poem.size != 5) {
                fail("expected 3 or 5 lines")
            }
            if (poem.any { scan(it).isEmpty() }) {
                fail("expected 3 or 5 lines")
            }
        }
        var words = scan(text)
        if (words.isEmpty()) {
            fail("no words")
        }
        words = words.map { word ->
            val pattern = pattern(word.text)
            if (pattern < 0) {
                column(word.start+1,"mixed case")
            }
            word.copy(pattern = pattern)
        }
        if (command == "DETECT") {
            return detect(words)
        }
        words = words.map { word ->
            val source = if (command == "NORMALIZE") "ANY" else
                if (command == "SAME" && word.start > text.indexOf('/')) arguments[1] else arguments[0]
            word.copy(morae = parse(word,source))
        }
        val system = if (command == "NORMALIZE") "HEPBURN" else arguments[0]
        when (command) {
            "CONVERT", "NORMALIZE", "REVERSE" -> {
                val target = if (command == "CONVERT") arguments[1] else system
                val result = StringBuilder()
                var cursor = 0
                for (word in words) {
                    result.append(text.substring(cursor,word.start))
                    val written = if (command == "REVERSE") {
                        val reversed = word.morae.mapIndexed { i,mora ->
                            val id = if (mora.id == "L") word.morae[i-1].id.last().toString() else mora.id
                            Mora(id,mora.column)
                        }.reversed()
                        word.copy(morae = reversed)
                    } else {
                        word
                    }
                    result.append(write(written,target,longSetting,caseSetting))
                    cursor = word.start+word.text.length
                }
                result.append(text.substring(cursor))
                return result.toString()
            }
            "VALID" -> {
                for (word in words) {
                    val expected = canonical(word,system)
                    if (word.text != expected) {
                        var i = 0
                        while (i < minOf(word.text.length,expected.length) && word.text[i] == expected[i]) {
                            i++
                        }
                        return "INVALID col ${word.start+i+1}: expected $expected"
                    }
                }
                return "VALID"
            }
            "DIFF" -> {
                val changes = mutableListOf<String>()
                for (word in words) {
                    val a = write(word,system,longSetting,caseSetting)
                    val b = write(word,arguments[1],longSetting,caseSetting)
                    if (a != b) {
                        changes.add("$a>$b")
                    }
                }
                return "${changes.size} of ${words.size}" + if (changes.isEmpty()) "" else ": ${changes.joinToString(" ")}"
            }
            "SAME" -> {
                val left = words.filter { it.start < text.indexOf('/') }
                val right = words.filter { it.start > text.indexOf('/') }
                var exact = true
                for (i in 0 until minOf(left.size,right.size)) {
                    if (loose(left[i]) != loose(right[i])) {
                        return "DIFFERENT at word ${i+1}"
                    }
                    if (ids(left[i]) != ids(right[i])) {
                        exact = false
                    }
                }
                if (left.size != right.size) {
                    return "DIFFERENT at word ${minOf(left.size,right.size)+1}"
                }
                return if (exact) "EXACT" else "LOOSE"
            }
            "MORAE" -> {
                var count = 0
                val result = words.map { word ->
                    val pieces = word.morae.map { if (regular(it.id)) spelling(system,it.id) else if (it.id == "L") "-" else it.id }
                    count += pieces.size
                    pieces.joinToString(".")
                }
                return "$count: ${result.joinToString(" ")}"
            }
            "SYLLABLES" -> {
                var count = 0
                val result = words.map { word ->
                    val pieces = parts(word,system,"KEEP")
                    val syllables = mutableListOf<String>()
                    val info = longInfo(word.morae)
                    for (i in pieces.indices) {
                        if (i == 0 || regular(word.morae[i].id) && !info.paired[i]) {
                            syllables.add(pieces[i])
                        } else {
                            syllables[syllables.lastIndex] += pieces[i]
                        }
                    }
                    count += syllables.size
                    syllables.joinToString(".")
                }
                return "$count: ${result.joinToString(" ")}"
            }
            "ROW" -> return words.flatMap { it.morae }.joinToString(", ") { mora ->
                val meta = metadata[mora.id]
                if (meta == null) (if (mora.id == "L") "-" else mora.id)+": special"
                else "${spelling(system,meta.id)}: ${meta.row} ${meta.dan}"
            }
            "STATS" -> {
                val morae = words.flatMap { it.morae }
                val regular = morae.mapNotNull { metadata[it.id] }
                val rowCounts = regular.groupingBy { baseRow(it.row) }.eachCount()
                val result = mutableListOf("morae=${morae.size}")
                result += rows.take(10).filter { it in rowCounts }.map { "$it=${rowCounts.getValue(it)}" }
                result += listOf(
                    "voiced=${regular.count { voice(it.row) == 1 }}",
                    "semivoiced=${regular.count { voice(it.row) == 2 }}",
                    "contracted=${regular.count { it.contracted }}",
                    "N=${morae.count { it.id == "N" }}",
                    "Q=${morae.count { it.id == "Q" }}",
                    "L=${morae.count { it.id == "L" }}"
                )
                return result.joinToString(" ")
            }
            "SORT", "INDEX" -> {
                val sorted = sorted(words)
                if (command == "SORT") {
                    return sorted.joinToString(" ") { it.text }
                }
                val groups = mutableListOf<String>()
                val group = mutableListOf<String>()
                var previous = ""
                for (word in sorted) {
                    val base = elements(word).first().base
                    val heading = if (orderSetting == "IROHA" || base == "N") base else metadata.getValue(base).row
                    if (heading != previous && group.isNotEmpty()) {
                        groups.add("$previous: ${group.joinToString(" ")}")
                        group.clear()
                    }
                    previous = heading
                    group.add(word.text)
                }
                groups.add("$previous: ${group.joinToString(" ")}")
                return groups.joinToString("; ")
            }
            "FIND" -> {
                val found = words.filter { matches(searchPattern,ids(it)) }.map { it.text }
                return "${found.size} of ${words.size}" + if (found.isEmpty()) "" else ": ${found.joinToString(" ")}"
            }
            "HAIKU" -> {
                val totals = IntArray(poem.size)
                for (word in words) {
                    totals[text.take(word.start).count { it == '/' }] += word.morae.size
                }
                val expected = if (poem.size == 3) listOf(5,7,5) else listOf(5,7,5,7,7)
                return (if (totals.toList() == expected) "OK " else "NG ") +
                    (if (poem.size == 3) "haiku " else "tanka ") + totals.joinToString("-")
            }
            "KAIBUN" -> {
                val bases = words.flatMap { elements(it) }.map { it.base }
                return (if (bases == bases.reversed()) "YES " else "NO ") + bases.joinToString(".")
            }
            "SHIRITORI" -> {
                val seen = mutableSetOf<List<String>>()
                var previous = ""
                for ((i,word) in words.withIndex()) {
                    val collation = elements(word)
                    val head = collation.first().base
                    val tail = collation.last().base
                    val prefix = "NG ${i+1}: ${word.text}"
                    if (i > 0 && head != previous) {
                        return "$prefix must start with ${spelling(system,previous)}"
                    }
                    if (!seen.add(ids(word))) {
                        return "$prefix is repeated"
                    }
                    if (tail == "N") {
                        return "$prefix ends with N"
                    }
                    previous = tail
                }
                return "OK ${words.size}"
            }
            else -> error("Unreachable command")
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val count = input.readLine().toInt()
    val converter = Converter()
    repeat(count) {
        val result = try {
            converter.execute(input.readLine())
        } catch (problem: Problem) {
            "ERROR ${problem.message}"
        }
        output.write(result)
        output.newLine()
    }
    output.flush()
}
