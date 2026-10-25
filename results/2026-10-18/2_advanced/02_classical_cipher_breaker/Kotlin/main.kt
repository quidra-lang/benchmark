import java.io.File

class JobFault(reason: String) : Exception(reason)
data class Candidate(val key: String, val plaintext: String, val score: Int, val order: Int)
data class BreakOutcome(
    val ranked: List<Candidate>, val choice: Candidate, val length: Int = 0,
    val method: String = "", val passes: Int = 0, val changes: Int = 0,
    val kasiski: KasiskiData? = null
)
data class OptionRule(val min: Int, val max: Int, val default: Int)

object Benchmark {
    private val commands = listOf("ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY")
    private val ciphers = setOf("caesar", "affine", "vigenere", "autokey",
        "railfence", "columnar", "playfair")
    private val multipliers = listOf(1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25)
    private val messages = mutableMapOf<String, List<String>>()
    private val totals = commands.associateWith { IntArray(2) }.toMutableMap()
    private val results = mutableListOf<String>()
    private val candidatesOutput = mutableListOf<String>()
    private val analysisOutput = mutableListOf<String>()
    private lateinit var mono: IntArray
    private lateinit var bi: Array<IntArray>

    private fun fail(reason: String): Nothing = throw JobFault(reason)

    private fun name(text: String): Boolean = Regex("[a-z0-9_]{1,16}").matches(text)

    private fun digits(text: String, length: Int): Boolean =
        Regex("[0-9]{1,$length}").matches(text)

    private fun body(name: String): String = messages.getValue(name).joinToString("\n")

    private fun letters(name: String): String = Scoring.letters(body(name))

    private fun substitution(cipher: String): Boolean =
        cipher in setOf("caesar", "affine", "vigenere", "autokey")

    private fun readMessages(path: String) {
        var current: String? = null
        var lines = mutableListOf<String>()
        for (line in File(path).readLines(Charsets.US_ASCII)) {
            if (current == null) {
                if (line.isEmpty()) continue
                current = line.substring(8)
                lines = mutableListOf()
            } else if (line == "END") {
                messages[current] = lines
                current = null
            } else lines.add(line)
        }
    }

    private fun normalizedKey(cipher: String, original: String): String {
        when (cipher) {
            "caesar" -> {
                if (!digits(original, 2) || original.toInt() > 25) fail("bad key $original")
                return original.toInt().toString()
            }
            "affine" -> {
                val pieces = original.split(",")
                if (pieces.size != 2 || !digits(pieces[0], 2) || !digits(pieces[1], 2))
                    fail("bad key $original")
                val a = pieces[0].toInt()
                val b = pieces[1].toInt()
                if (a !in multipliers || b > 25) fail("bad key $original")
                return "$a,$b"
            }
            "railfence" -> {
                if (!digits(original, 2) || original.toInt() !in 2..20) fail("bad key $original")
                return original.toInt().toString()
            }
            "vigenere", "autokey" -> if (!Regex("[A-Za-z]{1,20}").matches(original))
                fail("bad key $original")
            "playfair" -> if (!Regex("[A-Za-z]{1,25}").matches(original))
                fail("bad key $original")
            "columnar" -> if (!Regex("[A-Za-z0-9]{2,9}").matches(original))
                fail("bad key $original")
        }
        val key = original.uppercase()
        return if (cipher == "playfair") key.replace('J', 'I') else key
    }

    private fun rules(command: String, cipher: String): Map<String, OptionRule> {
        val rules = mutableMapOf<String, OptionRule>()
        if (command == "ANALYZE") rules["MAXLEN"] = OptionRule(2, 20, 10)
        if (command != "BREAK") return rules

        rules["TOP"] = OptionRule(1, 20, 5)
        when (cipher) {
            "vigenere" -> {
                rules["MAXLEN"] = OptionRule(2, 20, 10)
                rules["IOC"] = OptionRule(1, 100000, 6000)
                rules["KASISKI"] = OptionRule(1, 100, 60)
                rules["REFINE"] = OptionRule(0, 10, 5)
            }
            "autokey" -> rules["MAXLEN"] = OptionRule(1, 20, 8)
            "railfence" -> rules["MAXRAILS"] = OptionRule(2, 20, 10)
            "columnar" -> rules["MAXLEN"] = OptionRule(2, 6, 6)
        }
        return rules
    }

    private fun parseOptions(command: String, cipher: String, words: List<String>): Map<String, String> {
        val rules = rules(command, cipher)
        val values = rules.mapValues { it.value.default.toString() }.toMutableMap()
        val seen = mutableSetOf<String>()
        for (word in words) {
            val separator = word.indexOf('=')
            val label = if (separator < 0) "" else word.substring(0, separator)
            val value = if (separator < 0) "" else word.substring(separator + 1)
            if (separator < 0 || !seen.add(label)) fail("bad option $word")
            if (label == "KEYS" && (command == "IDENTIFY" ||
                        (command == "BREAK" && cipher == "playfair"))) {
                if (!name(value)) fail("bad option $word")
                values[label] = value
                continue
            }
            val rule = rules[label]
            if (rule == null || !digits(value, 6)) fail("bad option $word")
            val number = value.toInt()
            if (number !in rule.min..rule.max) fail("bad option $word")
            values[label] = number.toString()
        }
        if (command == "BREAK" && cipher == "playfair" && "KEYS" !in values)
            fail("missing option KEYS")
        return values
    }

    private fun option(options: Map<String, String>, key: String): Int =
        options.getValue(key).toInt()

    private fun decrypt(text: String, cipher: String, key: String): String = when {
        substitution(cipher) -> Scoring.letters(Substitution.apply(text, cipher, key, false))
        cipher == "railfence" -> Transposition.railFence(text, key.toInt(), false)
        cipher == "columnar" -> Transposition.columnar(text, key, false)
        else -> Playfair.apply(text, key, false)
    }

    private fun transform(text: String, cipher: String, key: String, encrypt: Boolean): String {
        if (substitution(cipher)) return Substitution.apply(text, cipher, key, encrypt)
        val source = Scoring.letters(text)
        return when (cipher) {
            "railfence" -> Transposition.railFence(source, key.toInt(), encrypt)
            "columnar" -> Transposition.columnar(source, key, encrypt)
            else -> Playfair.apply(source, key, encrypt)
        }
    }

    private fun keyList(name: String): List<String> {
        val unique = mutableSetOf<String>()
        return Regex("[A-Za-z]+").findAll(body(name)).map { it.value.uppercase().replace('J', 'I') }
            .filter { unique.add(it) }.toList()
    }

    private fun permutations(length: Int): List<String> {
        val digits = CharArray(length) { ('1'.code + it).toChar() }
        val result = mutableListOf<String>()
        fun visit(index: Int) {
            if (index == digits.size) {
                result.add(digits.concatToString())
                return
            }
            for (next in index until digits.size) {
                val temp = digits[index]
                digits[index] = digits[next]
                digits[next] = temp
                visit(index + 1)
                digits[next] = digits[index]
                digits[index] = temp
            }
        }
        visit(0)
        return result.sorted()
    }

    private fun columnKey(text: String, length: Int, autokey: Boolean): String = buildString {
        for (j in 0 until length) {
            val column = Analysis.column(text, length, j)
            var high = Int.MIN_VALUE
            var choice = 0
            for (key in 0..25) {
                val score = if (!autokey) {
                    Scoring.monogram(Substitution.apply(column, "caesar", key.toString(), false), mono)
                } else {
                    var previous = key
                    var total = 0
                    for (c in column) {
                        previous = Substitution.mod(Scoring.value(c) - previous)
                        total += mono[previous]
                    }
                    total
                }
                if (score > high) {
                    choice = key
                    high = score
                }
            }
            append(Scoring.upper(choice))
        }
    }

    private fun candidateKeys(cipher: String, text: String,
                              options: Map<String, String>, keys: List<String>?): List<String> =
        when (cipher) {
            "caesar" -> (0..25).map(Int::toString)
            "affine" -> multipliers.flatMap { a -> (0..25).map { b -> "$a,$b" } }
            "railfence" -> (2..option(options, "MAXRAILS")).map(Int::toString)
            "columnar" -> (2..option(options, "MAXLEN")).flatMap(::permutations)
            "playfair" -> keys!!
            else -> (1..option(options, "MAXLEN")).map { columnKey(text, it, cipher == "autokey") }
        }

    private fun score(cipher: String, plaintext: String): Int =
        if (cipher == "caesar" || cipher == "affine") Scoring.monogram(plaintext, mono)
        else Scoring.bigram(plaintext, bi)

    private fun breaker(cipher: String, text: String, options: Map<String, String>,
                        keys: List<String>? = null): BreakOutcome {
        val raw = candidateKeys(cipher, text, options, keys).mapIndexed { index, key ->
            val plaintext = decrypt(text, cipher, key)
            Candidate(key, plaintext, score(cipher, plaintext), index)
        }
        val ranked = raw.sortedWith(compareByDescending<Candidate> { it.score }.thenBy { it.order })
        if (cipher != "vigenere") return BreakOutcome(ranked, ranked.first())
        val maxlen = option(options, "MAXLEN")
        val threshold = option(options, "IOC")
        val kasiski = Analysis.kasiski(text)
        val averages = (1..maxlen).map { Analysis.averageIoc(text, it) }
        var kasiskiLength = 0
        if (kasiski.gaps.isNotEmpty()) {
            for (length in 2..maxlen) {
                if (100 * kasiski.count(length) >= option(options, "KASISKI") * kasiski.gaps.size)
                    kasiskiLength = length
            }
        }
        val chosen: Int
        val method: String
        if (kasiskiLength > 0 && averages[kasiskiLength - 1] >= threshold) {
            chosen = kasiskiLength
            method = "kasiski"
        } else {
            val atThreshold = (1..maxlen).firstOrNull { averages[it - 1] >= threshold }
            if (atThreshold != null) {
                chosen = atThreshold
                method = "ioc"
            } else {
                chosen = (1..maxlen).maxWith(compareBy<Int> { averages[it - 1] }.thenBy { -it })
                method = "maxioc"
            }
        }
        var key = raw[chosen - 1].key
        var reference = score(cipher, decrypt(text, cipher, key))
        var passes = 0
        var changes = 0
        repeat(option(options, "REFINE")) {
            passes++
            var changed = 0
            for (index in key.indices) {
                var best = key[index]
                var high = reference
                for (value in 0..25) {
                    val current = key.substring(0, index) + Scoring.upper(value) + key.substring(index + 1)
                    val currentScore = score(cipher, decrypt(text, cipher, current))
                    if (currentScore > high) {
                        high = currentScore
                        best = Scoring.upper(value)
                    }
                }
                if (high > reference) {
                    key = key.substring(0, index) + best + key.substring(index + 1)
                    reference = high
                    changed++
                    changes++
                }
            }
            if (changed == 0) return BreakOutcome(ranked,
                Candidate(key, decrypt(text, cipher, key), reference, -1),
                chosen, method, passes, changes, kasiski)
        }
        return BreakOutcome(ranked, Candidate(key, decrypt(text, cipher, key), reference, -1),
            chosen, method, passes, changes, kasiski)
    }

    private fun writeCandidateReport(job: Int, cipher: String, source: String,
                                     broken: BreakOutcome, top: Int) {
        val trials = broken.ranked.size
        val margin = if (trials >= 2) broken.ranked[0].score - broken.ranked[1].score else 0
        candidatesOutput.add("JOB $job BREAK $cipher source=$source tried=$trials margin=$margin")
        for ((index, candidate) in broken.ranked.take(top).withIndex()) {
            val preview = candidate.plaintext.take(40)
            candidatesOutput.add("${index + 1} ${candidate.key} ${candidate.score} $preview")
        }
    }

    private fun writeBreakAnalysis(job: Int, cipher: String, source: String,
                                   text: String, options: Map<String, String>,
                                   broken: BreakOutcome) {
        if (cipher == "vigenere") {
            val info = broken.kasiski!!
            analysisOutput.add("JOB $job BREAK vigenere source=$source")
            analysisOutput.add("letters=${text.length}")
            analysisOutput.addAll(Analysis.periodTable(text, option(options, "MAXLEN"), info))
            analysisOutput.addAll(Analysis.kasiskiTable(info))
            analysisOutput.add("decision length=${broken.length} method=${broken.method}")
            analysisOutput.add("refine passes=${broken.passes} changes=${broken.changes} key=${broken.choice.key}")
        } else if (cipher == "playfair") {
            val t = text.replace('J', 'I')
            val square = Playfair.square(broken.choice.key)
            val pairs = t.chunked(2)
            analysisOutput.add("JOB $job BREAK playfair source=$source")
            analysisOutput.add("letters=${t.length}")
            analysisOutput.add("digraphs pairs=${pairs.size} distinct=${pairs.distinct().size}")
            analysisOutput.add("top ${Analysis.topPairs(t, true)}")
            analysisOutput.add("square ${square.chunked(5).joinToString(" ")}")
        }
    }

    private fun outputText(source: String, cipher: String,
                           key: String, encrypt: Boolean): List<String> {
        val result = transform(source, cipher, key, encrypt)
        return if (substitution(cipher)) result.split("\n") else Scoring.groups(result)
    }

    private fun save(target: String?, lines: List<String>) {
        if (target != null) messages[target] = lines
    }

    private fun cipherJob(job: Int, command: String, cipher: String,
                          key: String, source: String, target: String?) {
        val text = letters(source)
        if (text.isEmpty()) fail("no letters")
        if (command == "DECRYPT" && cipher == "playfair" && !Playfair.valid(text))
            fail("bad playfair text")
        val lines = outputText(body(source), cipher, key, command == "ENCRYPT")
        val count = lines.sumOf { Scoring.letters(it).length }
        val suffix = if (target != null) " as=$target" else ""
        results.add("JOB $job $command $cipher key=$key source=$source letters=$count lines=${lines.size}$suffix")
        results.addAll(lines)
        save(target, lines)
    }

    private fun breakJob(job: Int, cipher: String, source: String,
                         target: String?, options: Map<String, String>) {
        val text = letters(source)
        if (text.length < 40) fail("text too short")
        if (cipher == "playfair" && !Playfair.valid(text)) fail("bad playfair text")
        val keys = if (cipher == "playfair") keyList(options.getValue("KEYS")) else null
        if (cipher == "playfair" && keys!!.isEmpty()) fail("empty key list")
        val broken = breaker(cipher, text, options, keys)
        val lines = outputText(body(source), cipher, broken.choice.key, false)
        val suffix = if (target != null) " as=$target" else ""
        results.add("JOB $job BREAK $cipher source=$source key=${broken.choice.key} score=${broken.choice.score} lines=${lines.size}$suffix")
        results.addAll(lines)
        writeCandidateReport(job, cipher, source, broken, option(options, "TOP"))
        writeBreakAnalysis(job, cipher, source, text, options, broken)
        save(target, lines)
    }

    private fun analyzeJob(job: Int, source: String, options: Map<String, String>) {
        val text = letters(source)
        if (text.length < 40) fail("text too short")
        results.add("JOB $job ANALYZE source=$source letters=${text.length}")
        analysisOutput.addAll(Analysis.report(job, source, text, mono, bi, option(options, "MAXLEN")))
    }

    private fun compareJob(job: Int, leftName: String, rightName: String) {
        val left = letters(leftName)
        val right = letters(rightName)
        val common = minOf(left.length, right.length)
        var first = common + 1
        var differences = 0
        for (index in 0 until common) if (left[index] != right[index]) {
            if (differences == 0) first = index + 1
            differences++
        }
        if (left == right)
            results.add("JOB $job COMPARE $leftName $rightName equal letters=${left.length}")
        else
            results.add("JOB $job COMPARE $leftName $rightName differ letters=${left.length},${right.length} first=$first mismatches=$differences")
    }

    private fun identifyJob(job: Int, source: String, options: Map<String, String>) {
        val text = letters(source)
        if (text.length < 40) fail("text too short")
        val ioc = Analysis.ioc(text)
        val mean = Scoring.monogram(text, mono) / text.length
        val distinct = Analysis.frequencies(text).count { it > 0 }
        val shape = !text.contains('J') && Playfair.valid(text)
        val family = when {
            shape -> "playfair"
            ioc >= 5500 && mean >= 44 -> "transposition"
            ioc >= 5500 -> "monoalphabetic"
            else -> "polyalphabetic"
        }
        val keys = if (family == "playfair" && "KEYS" in options)
            keyList(options.getValue("KEYS")) else null
        if (family == "playfair" && keys != null && keys.isEmpty()) fail("empty key list")
        val toTry = when (family) {
            "transposition" -> listOf("railfence", "columnar")
            "monoalphabetic" -> listOf("affine")
            "polyalphabetic" -> listOf("vigenere", "autokey")
            else -> if (keys == null) emptyList() else listOf("playfair")
        }
        val tested = toTry.map { cipher ->
            val supplied = if (cipher == "playfair") listOf("KEYS=${options.getValue("KEYS")}") else emptyList()
            val defaults = parseOptions("BREAK", cipher, supplied)
            cipher to breaker(cipher, text, defaults, keys).choice
        }
        val choice = tested.maxWithOrNull(compareBy<Pair<String, Candidate>> { it.second.score }
            .thenBy { -tested.indexOf(it) })
        var reported = choice?.first ?: ""
        var key = choice?.second?.key ?: ""
        if (reported == "affine" && key.substringBefore(",") == "1") {
            reported = "caesar"
            key = key.substringAfter(",")
        }
        var header = "JOB $job IDENTIFY source=$source family=$family"
        if (choice != null) {
            val lines = outputText(body(source), reported, key, false)
            header += " cipher=$reported key=$key score=${choice.second.score} lines=${lines.size}"
            results.add(header)
            results.addAll(lines)
        } else results.add(header)
        analysisOutput.add("JOB $job IDENTIFY source=$source")
        analysisOutput.add("letters=${text.length} ioc=$ioc mono_avg=$mean distinct=$distinct shape=${if (shape) "yes" else "no"}")
        analysisOutput.add("family=$family")
        for ((cipher, result) in tested)
            analysisOutput.add("try $cipher key=${result.key} score=${result.score}")
        if (choice != null) analysisOutput.add("choice $reported")
    }

    private fun checkReferences(parts: List<String>, command: String, options: Map<String, String>) {
        val source = if (command in setOf("ENCRYPT", "DECRYPT", "BREAK"))
            parts[if (command == "BREAK") 2 else 3] else parts[1]
        if (source !in messages) fail("unknown message $source")
        val keys = options["KEYS"]
        if (keys != null && keys !in messages) fail("unknown message $keys")
        if (command == "COMPARE" && parts[2] !in messages)
            fail("unknown message ${parts[2]}")
    }

    private fun execute(job: Int, line: String) {
        val parts = line.split(' ').toMutableList()
        val command = parts[0]
        if (command !in commands) fail("unknown command")
        var target: String? = null
        if (command in setOf("ENCRYPT", "DECRYPT", "BREAK")
            && parts.size >= 5 && parts[parts.size - 2] == "AS") {
            target = parts.last()
            parts.subList(parts.size - 2, parts.size).clear()
            if (!name(target)) fail("bad syntax")
        }
        val valid = when (command) {
            "ENCRYPT", "DECRYPT" -> parts.size == 4
            "BREAK" -> parts.size >= 3
            "ANALYZE", "IDENTIFY" -> parts.size == 2 || parts.size == 3
            else -> parts.size == 3
        }
        if (!valid) fail("bad syntax")
        val cipher = if (command in setOf("ENCRYPT", "DECRYPT", "BREAK")) parts[1] else ""
        if (cipher.isNotEmpty() && cipher !in ciphers) fail("unknown cipher $cipher")
        val key = if (command in setOf("ENCRYPT", "DECRYPT")) normalizedKey(cipher, parts[2]) else ""
        val optionWords = when (command) {
            "BREAK" -> parts.drop(3)
            "ANALYZE", "IDENTIFY" -> parts.drop(2)
            else -> emptyList()
        }
        val opts = parseOptions(command, cipher, optionWords)
        checkReferences(parts, command, opts)
        if (target != null && target in messages) fail("duplicate message $target")
        when (command) {
            "ENCRYPT", "DECRYPT" -> cipherJob(job, command, cipher, key, parts[3], target)
            "BREAK" -> breakJob(job, cipher, parts[2], target, opts)
            "ANALYZE" -> analyzeJob(job, parts[1], opts)
            "COMPARE" -> compareJob(job, parts[1], parts[2])
            "IDENTIFY" -> identifyJob(job, parts[1], opts)
        }
    }

    private fun runJobs(path: String) {
        var count = 0
        var success = 0
        var failures = 0
        for (line in File(path).readLines(Charsets.US_ASCII)) {
            if (line.isEmpty() || line.startsWith("#")) continue
            count++
            val command = line.substringBefore(' ')
            try {
                execute(count, line)
                success++
                totals[command]?.let { it[0]++ }
            } catch (fault: JobFault) {
                failures++
                totals[command]?.let { it[1]++ }
                results.add("JOB $count ERROR ${fault.message}")
            }
        }
        for (command in commands) {
            val values = totals.getValue(command)
            results.add("TOTAL $command ok=${values[0]} errors=${values[1]}")
        }
        results.add("SUMMARY jobs=$count ok=$success errors=$failures messages=${messages.size}")
    }

    private fun write(filename: String, lines: List<String>) {
        val text = if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n")
        File("output/$filename").writeText(text, Charsets.US_ASCII)
    }

    fun run() {
        val weights = Scoring.read("input/weights.txt")
        mono = weights.first
        bi = weights.second
        readMessages("input/messages.txt")
        runJobs("input/jobs.txt")
        File("output").mkdirs()
        write("results.txt", results)
        write("candidates.txt", candidatesOutput)
        write("analysis.txt", analysisOutput)
    }
}

fun main() = Benchmark.run()
