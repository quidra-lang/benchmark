import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log2
import kotlin.math.pow

private const val LETTERS = "CDEFGAB"
private val naturals = intArrayOf(0, 2, 4, 5, 7, 9, 11)
private val fifthsValues = intArrayOf(0, 2, 4, -1, 1, 3, 5)
private val accidentals = listOf("bb", "b", "", "#", "x")
private val sharpNames = "C C# D D# E F F# G G# A A# B".split(' ')
private val flatNames = "C Db D Eb E F Gb G Ab A Bb B".split(' ')
private val romans = listOf("I", "II", "III", "IV", "V", "VI", "VII")
private val integerPattern = Regex("0|[1-9][0-9]*")
private val frequencyPattern = Regex("[0-9]{1,5}(\\.[0-9]{1,2})?")

private class CommandError(message: String) : RuntimeException("ERROR $message")
private fun bad(kind: String, word: String): Nothing = throw CommandError("BAD $kind $word")
private fun mod(value: Int, divisor: Int): Int {
    val remainder = value % divisor
    return if (remainder < 0) remainder + divisor else remainder
}
private fun canonical(text: String, range: IntRange): Int? =
    if (integerPattern.matches(text)) text.toIntOrNull()?.takeIf { it in range } else null
private fun parseNumber(text: String): Int = canonical(text, 0..127) ?: bad("NUMBER", text)
private fun frequencyCents(text: String, tuning: Boolean): Int {
    if (!frequencyPattern.matches(text)) bad("FREQUENCY", text)
    val parts = text.split('.')
    var result = parts[0].toInt() * 100
    if (parts.size == 2) result += parts[1].toInt() * if (parts[1].length == 1) 10 else 1
    if (result == 0 || tuning && result !in 40000..48000) bad("FREQUENCY", text)
    return result
}
private fun frequencyText(cents: Int) = "${cents / 100}.${(cents % 100).toString().padStart(2, '0')}"

private data class Pitch(val letter: Int, val alteration: Int) {
    val pitchClass: Int get() = mod(naturals[letter] + alteration, 12)
    fun raise(tone: Tone): Pitch {
        val target = letter + tone.letters
        val change = naturals[letter] + alteration + tone.semitones - naturals[target % 7] - 12 * (target / 7)
        if (change !in -2..2) throw CommandError("CANNOT SPELL")
        return Pitch(target % 7, change)
    }
    override fun toString() = "${LETTERS[letter]}${accidentals[alteration + 2]}"
}
private data class PitchPrefix(val pitch: Pitch, val end: Int)
private fun pitchPrefix(text: String): PitchPrefix? {
    val letter = LETTERS.indexOf(text[0])
    if (letter < 0) return null
    var end = 1
    var alteration = 0
    when (text.getOrNull(end)) {
        'b' -> {
            alteration = -1
            end++
            if (text.getOrNull(end) == 'b') { alteration = -2; end++ }
        }
        '#' -> { alteration = 1; end++ }
        'x' -> { alteration = 2; end++ }
    }
    return PitchPrefix(Pitch(letter, alteration), end)
}
private fun parsePitch(text: String): Pitch {
    val prefix = pitchPrefix(text)
    if (prefix == null || prefix.end != text.length) bad("PITCH", text)
    return prefix.pitch
}
private fun fifthPitch(fifths: Int) =
    Pitch(LETTERS.indexOf("FCGDAEB"[mod(fifths + 1, 7)]), Math.floorDiv(fifths + 1, 7))
private data class Note(val pitch: Pitch, val octave: Int) {
    val midi: Int get() = 12 * (octave + 1) + naturals[pitch.letter] + pitch.alteration
    val position: Int get() = 7 * octave + pitch.letter
    val valid: Boolean get() = octave in -1..9 && midi in 0..127
    override fun toString() = "$pitch$octave"
}
private fun parseNote(text: String): Note {
    val prefix = pitchPrefix(text) ?: bad("NOTE", text)
    val rest = text.substring(prefix.end)
    val octave = when {
        rest == "-1" -> -1
        rest.length == 1 && rest[0] in '0'..'9' -> rest[0] - '0'
        else -> bad("NOTE", text)
    }
    return Note(prefix.pitch, octave).also { if (!it.valid) bad("NOTE", text) }
}
private fun fromPitch(pitch: Pitch, midi: Int) =
    Note(pitch, (midi - naturals[pitch.letter] - pitch.alteration) / 12 - 1)
private fun spelling(midi: Int, flat: Boolean) =
    Note(parsePitch((if (flat) flatNames else sharpNames)[midi % 12]), midi / 12 - 1)

private enum class Quality(val text: String) {
    PERFECT("P"), MAJOR("M"), MINOR("m"), AUGMENTED("A"), DIMINISHED("d"), DOUBLE_AUGMENTED("AA"), DOUBLE_DIMINISHED("dd");
    fun delta(perfect: Boolean): Int? = when (this) {
        PERFECT -> if (perfect) 0 else null
        MAJOR -> if (perfect) null else 0
        MINOR -> if (perfect) null else -1
        AUGMENTED -> 1
        DIMINISHED -> if (perfect) -1 else -2
        DOUBLE_AUGMENTED -> 2
        DOUBLE_DIMINISHED -> if (perfect) -2 else -3
    }
    fun inverse(): Quality = when (this) {
        PERFECT -> PERFECT
        MAJOR -> MINOR
        MINOR -> MAJOR
        AUGMENTED -> DIMINISHED
        DIMINISHED -> AUGMENTED
        DOUBLE_AUGMENTED -> DOUBLE_DIMINISHED
        DOUBLE_DIMINISHED -> DOUBLE_AUGMENTED
    }
}
private fun perfectType(number: Int) = (number - 1) % 7 in listOf(0, 3, 4)
private data class Tone(val letters: Int, val semitones: Int)
private data class Interval(val quality: Quality, val number: Int) {
    val forbidden: Boolean get() = number == 1 && quality in listOf(Quality.DIMINISHED, Quality.DOUBLE_DIMINISHED)
    val tone: Tone get() {
        val distance = number - 1
        return Tone(distance, 12 * (distance / 7) + naturals[distance % 7] + quality.delta(perfectType(number))!!)
    }
    fun simple(): Interval {
        var n = number
        while (n > 8) n -= 7
        return copy(number = n)
    }
    fun consonance(): String {
        val simple = simple()
        if (quality == Quality.PERFECT && simple.number in listOf(1, 5, 8)) return "perfect"
        if (quality in listOf(Quality.MAJOR, Quality.MINOR) && simple.number in listOf(3, 6)) return "imperfect"
        return "dissonant"
    }
    override fun toString() = "${quality.text}$number"
}
private fun parseInterval(text: String): Interval {
    for (quality in Quality.entries) {
        if (!text.startsWith(quality.text)) continue
        val number = canonical(text.substring(quality.text.length), 1..99) ?: continue
        if (quality.delta(perfectType(number)) == null) continue
        val result = Interval(quality, number)
        if (!result.forbidden) return result
    }
    bad("INTERVAL", text)
}
private data class Motion(val interval: Interval, val down: Boolean, val semitones: Int)
private fun between(first: Note, second: Note): Motion {
    var distance = second.position - first.position
    var semitones = second.midi - first.midi
    val down = distance < 0 || distance == 0 && semitones < 0
    if (down) { distance = -distance; semitones = -semitones }
    val difference = semitones - 12 * (distance / 7) - naturals[distance % 7]
    for (quality in Quality.entries) {
        if (quality.delta(perfectType(distance + 1)) == difference) return Motion(Interval(quality, distance + 1), down, semitones)
    }
    throw CommandError("UNNAMEABLE INTERVAL")
}

private data class Scale(val name: String, val tones: List<Tone>)
private data class Chord(val name: String, val suffix: String, val numeralSuffix: String, val lower: Boolean, val tones: List<Tone>)
private data class Mode(val name: String, val scale: Int, val offset: Int)
private fun tones(text: String) = text.split(' ').map { parseInterval(it).tone }
private val scales = listOf(
    Scale("major", tones("P1 M2 M3 P4 P5 M6 M7")),
    Scale("natural_minor", tones("P1 M2 m3 P4 P5 m6 m7")),
    Scale("harmonic_minor", tones("P1 M2 m3 P4 P5 m6 M7")),
    Scale("melodic_minor", tones("P1 M2 m3 P4 P5 M6 M7")),
    Scale("ionian", tones("P1 M2 M3 P4 P5 M6 M7")),
    Scale("dorian", tones("P1 M2 m3 P4 P5 M6 m7")),
    Scale("phrygian", tones("P1 m2 m3 P4 P5 m6 m7")),
    Scale("lydian", tones("P1 M2 M3 A4 P5 M6 M7")),
    Scale("mixolydian", tones("P1 M2 M3 P4 P5 M6 m7")),
    Scale("aeolian", tones("P1 M2 m3 P4 P5 m6 m7")),
    Scale("locrian", tones("P1 m2 m3 P4 d5 m6 m7")),
    Scale("major_pentatonic", tones("P1 M2 M3 P5 M6")),
    Scale("minor_pentatonic", tones("P1 m3 P4 P5 m7")),
    Scale("blues", tones("P1 m3 P4 A4 P5 m7")),
    Scale("whole_tone", tones("P1 M2 M3 A4 A5 A6"))
)
private val chords = listOf(
    Chord("maj", "", "", false, tones("P1 M3 P5")),
    Chord("min", "m", "", true, tones("P1 m3 P5")),
    Chord("dim", "dim", "o", true, tones("P1 m3 d5")),
    Chord("aug", "aug", "+", false, tones("P1 M3 A5")),
    Chord("sus2", "sus2", "sus2", false, tones("P1 M2 P5")),
    Chord("sus4", "sus4", "sus4", false, tones("P1 P4 P5")),
    Chord("6", "6", "6", false, tones("P1 M3 P5 M6")),
    Chord("m6", "m6", "6", true, tones("P1 m3 P5 M6")),
    Chord("7", "7", "7", false, tones("P1 M3 P5 m7")),
    Chord("maj7", "maj7", "maj7", false, tones("P1 M3 P5 M7")),
    Chord("m7", "m7", "7", true, tones("P1 m3 P5 m7")),
    Chord("mMaj7", "mMaj7", "maj7", true, tones("P1 m3 P5 M7")),
    Chord("m7b5", "m7b5", "h7", true, tones("P1 m3 d5 m7")),
    Chord("dim7", "dim7", "o7", true, tones("P1 m3 d5 d7")),
    Chord("9", "9", "9", false, tones("P1 M3 P5 m7 M9")),
    Chord("add9", "add9", "add9", false, tones("P1 M3 P5 M9"))
)
private val modes = listOf(
    Mode("major", 0, 0), Mode("minor", 1, -3), Mode("ionian", 4, 0), Mode("dorian", 5, -2),
    Mode("phrygian", 6, -4), Mode("lydian", 7, 1), Mode("mixolydian", 8, -1), Mode("aeolian", 9, -3), Mode("locrian", 10, -5)
)
private fun parseScale(text: String): Scale = scales.find { it.name == text } ?: bad("SCALE", text)
private fun parseQuality(text: String): Int = chords.indexOfFirst { it.name == text }.takeIf { it >= 0 } ?: bad("QUALITY", text)
private fun parseMode(text: String): Int = modes.indexOfFirst { it.name == text }.takeIf { it >= 0 } ?: bad("MODE", text)
private fun build(root: Pitch, tones: List<Tone>) = tones.map(root::raise)
private fun symbol(root: Pitch, quality: Int, bass: Pitch? = null) =
    "$root${chords[quality].suffix}${if (bass == null) "" else "/$bass"}"
private fun roman(degree: Int, quality: Int): String {
    val chord = chords[quality]
    return (if (chord.lower) romans[degree].lowercase() else romans[degree]) + chord.numeralSuffix
}
private data class Key(val tonic: Pitch, val mode: Int, val fifths: Int, val scale: List<Pitch>) {
    fun degree(pitch: Pitch) = mod(pitch.letter - tonic.letter, 7)
    fun prefix(pitch: Pitch): String {
        val difference = pitch.alteration - scale[degree(pitch)].alteration
        return if (difference < 0) "b".repeat(-difference) else "#".repeat(difference)
    }
    fun label(pitch: Pitch) = "${prefix(pitch)}${degree(pitch) + 1}"
    fun pitchSet(): Int = scale.fold(0) { mask, pitch -> mask or (1 shl pitch.pitchClass) }
    override fun toString() = "$tonic ${modes[mode].name}"
}
private fun makeKey(tonic: Pitch, mode: Int): Key {
    val fifths = fifthsValues[tonic.letter] + 7 * tonic.alteration + modes[mode].offset
    if (fifths !in -7..7) throw CommandError("THEORETICAL KEY")
    return Key(tonic, mode, fifths, build(tonic, scales[modes[mode].scale].tones))
}
private fun parseKey(words: List<String>, start: Int = 0): Key {
    val tonic = parsePitch(words[start])
    val mode = parseMode(words[start + 1])
    return makeKey(tonic, mode)
}
private data class Numeral(val alteration: Int, val degree: Int, val quality: Int)
private data class ChordSymbol(val root: Pitch, val quality: Int)
private fun parseNumeral(text: String): Numeral {
    val start = if (text[0] == 'b' || text[0] == '#') 1 else 0
    val alteration = if (start == 0) 0 else if (text[0] == 'b') -1 else 1
    var end = start
    while (end < text.length && text[end] in "IViv") end++
    val part = text.substring(start, end)
    val suffix = text.substring(end)
    for (degree in 0..6) {
        for ((quality, chord) in chords.withIndex()) {
            val expected = if (chord.lower) romans[degree].lowercase() else romans[degree]
            if (part == expected && suffix == chord.numeralSuffix) return Numeral(alteration, degree, quality)
        }
    }
    bad("NUMERAL", text)
}
private fun parseSymbol(text: String): ChordSymbol {
    val prefix = pitchPrefix(text)
    if (prefix != null) {
        val quality = chords.indexOfFirst { it.suffix == text.substring(prefix.end) }
        if (quality >= 0) return ChordSymbol(prefix.pitch, quality)
    }
    bad("SYMBOL", text)
}

private fun chordCommand(command: String, args: List<String>): String {
    val input = if (command == "VOICE") parseNote(args[0]) else null
    val root = input?.pitch ?: parsePitch(args[0])
    val quality = parseQuality(args[1])
    val chord = chords[quality]
    val inversion = if (args.size == 3) canonical(args[2], chord.tones.indices) ?: bad("INVERSION", args[2]) else 0
    val tones = build(root, chord.tones)
    val ordered = tones.drop(inversion) + tones.take(inversion)
    val name = symbol(root, quality, if (inversion == 0) null else ordered.first())
    if (input == null) return "CHORD $name ${ordered.joinToString(" ")}"
    var value = input.midi
    val notes = ordered.mapIndexed { i, pitch ->
        if (i != 0 || inversion != 0) {
            val difference = mod(pitch.pitchClass - value, 12)
            value += if (difference == 0) 12 else difference
        }
        fromPitch(pitch, value).also { if (!it.valid) throw CommandError("OUT OF RANGE") }
    }
    return "VOICE $name ${notes.joinToString(" ")} midi=${notes.joinToString(",") { it.midi.toString() }}"
}
private fun identify(notes: List<Note>): String {
    val candidates = notes.sortedBy { it.midi }.distinctBy { it.pitch.pitchClass }
    val bass = candidates.first().pitch
    val set = candidates.map { it.pitch.pitchClass }.toSet()
    for (root in candidates) {
        for ((quality, chord) in chords.withIndex()) {
            if (chord.tones.map { mod(root.midi + it.semitones, 12) }.toSet() != set) continue
            val inversion = chord.tones.indexOfFirst { mod(root.midi + it.semitones, 12) == bass.pitchClass }
            return "IDENTIFY ${symbol(root.pitch, quality, if (inversion == 0) null else bass)} root=${root.pitch} quality=${chord.name} inversion=$inversion"
        }
    }
    return "IDENTIFY UNKNOWN"
}
private fun melody(notes: List<Note>): String {
    var low = notes.first()
    var high = low
    for (note in notes) {
        if (note.midi < low.midi) low = note
        if (note.midi > high.midi) high = note
    }
    val range = between(low, high).interval
    var leaps = 0
    val steps = (1 until notes.size).map { i ->
        val motion = between(notes[i - 1], notes[i])
        if (abs(notes[i].midi - notes[i - 1].midi) >= 3) leaps++
        "${if (motion.down) "-" else "+"}${motion.interval}"
    }
    return "MELODY n=${notes.size} low=$low high=$high range=$range leaps=$leaps steps=${steps.joinToString(",")}"
}
private fun cadence(numerals: List<Numeral>): String {
    if (numerals.size < 2) return "none"
    val x = numerals[numerals.size - 2]
    val y = numerals.last()
    if (x.alteration == 0 && y.alteration == 0) {
        if (x.degree == 4 && y.degree == 0) return "authentic"
        if (x.degree == 3 && y.degree == 0) return "plagal"
        if (x.degree == 4 && y.degree == 5) return "deceptive"
    }
    return if (y.alteration == 0 && y.degree == 4) "half" else "none"
}
private fun diatonic(key: Key): String {
    val rows = mutableListOf("DIATONIC $key")
    for (size in 3..4) {
        val items = key.scale.mapIndexed { i, root ->
            val third = mod(key.scale[(i + 2) % 7].pitchClass - root.pitchClass, 12)
            val fifth = mod(key.scale[(i + 4) % 7].pitchClass - root.pitchClass, 12)
            val quality = if (size == 3) {
                if (third == 4) 0 else if (fifth == 7) 1 else 2
            } else {
                val seventh = mod(key.scale[(i + 6) % 7].pitchClass - root.pitchClass, 12)
                if (third == 4) (if (seventh == 11) 9 else 8) else if (fifth == 7) 10 else 12
            }
            "${roman(i, quality)}=${symbol(root, quality)}"
        }
        rows += (if (size == 3) "TRIADS " else "SEVENTHS ") + items.joinToString(" ")
    }
    return rows.joinToString("\n")
}

private fun keyCommand(command: String, args: List<String>): String {
    val key = parseKey(args)
    return when (command) {
        "KEYSIG" -> {
            val p = key.fifths
            if (p == 0) "KEYSIG $key none"
            else {
                val names = (if (p > 0) "F# C# G# D# A# E# B#" else "Bb Eb Ab Db Gb Cb Fb").split(' ')
                "KEYSIG $key ${if (p > 0) "sharps" else "flats"}=${abs(p)} ${names.take(abs(p)).joinToString(" ")}"
            }
        }
        "RELATIVE" -> "RELATIVE $key major=${fifthPitch(key.fifths)} minor=${fifthPitch(key.fifths + 3)}"
        "DEGREE" -> {
            val pitch = parsePitch(args[2])
            "DEGREE $key ${args[2]} ${key.label(pitch)}"
        }
        "KEYDIST" -> {
            val other = parseKey(args, 2)
            var distance = mod(other.fifths - key.fifths, 12)
            if (distance > 6) distance -= 12
            val sameTonic = key.tonic.pitchClass == other.tonic.pitchClass
            val relation = when {
                key.pitchSet() == other.pitchSet() -> if (sameTonic) "same" else "relative"
                sameTonic -> "parallel"
                abs(distance) == 1 -> "close"
                else -> "distant"
            }
            val common = Integer.bitCount(key.pitchSet() and other.pitchSet())
            "KEYDIST $key $other fifths=${if (distance > 0) "+" else ""}$distance common=$common relation=$relation"
        }
        "DIATONIC" -> diatonic(key)
        "ANALYZE" -> {
            val symbols = args.drop(2).map(::parseSymbol)
            val items = symbols.map { key.prefix(it.root) + roman(key.degree(it.root), it.quality) }
            "ANALYZE $key ${items.joinToString(" ")}"
        }
        "PROGRESSION" -> {
            val numerals = args.drop(2).map(::parseNumeral)
            val rows = mutableListOf("PROGRESSION $key ${numerals.size}")
            for ((i, numeral) in numerals.withIndex()) {
                val degree = key.scale[numeral.degree]
                val root = degree.copy(alteration = degree.alteration + numeral.alteration)
                val tones = build(root, chords[numeral.quality].tones)
                rows += "${args[i + 2]} ${symbol(root, numeral.quality)} ${tones.joinToString(" ")}"
            }
            rows += "CADENCE ${cadence(numerals)}"
            rows.joinToString("\n")
        }
        else -> throw CommandError("UNKNOWN COMMAND $command")
    }
}

private class Calculator {
    private var tuning = 44000

    fun execute(line: String): String {
        val words = line.split(' ')
        val command = words[0]
        val args = words.drop(1)
        val arity = when (command) {
            "MIDI", "NOTE", "FREQ", "TUNING", "PITCH", "INVERT", "ENHARMONIC", "CIRCLE" -> 1..1
            "INTERVAL", "SCALE", "KEYSIG", "RELATIVE", "DIATONIC" -> 2..2
            "TRANSPOSE", "DEGREE", "SPELL" -> 3..3
            "KEYDIST" -> 4..4
            "CHORD", "VOICE" -> 2..3
            "IDENTIFY", "MELODY" -> 2..15
            "PROGRESSION", "ANALYZE" -> 3..15
            "FINDKEY" -> 1..15
            else -> throw CommandError("UNKNOWN COMMAND $command")
        }
        if (args.size !in arity) throw CommandError("ARGUMENT COUNT")
        return when (command) {
            "MIDI", "FREQ", "ENHARMONIC" -> {
                val note = parseNote(args[0])
                val value = note.midi
                when (command) {
                    "MIDI" -> "MIDI ${args[0]} $value"
                    "FREQ" -> {
                        val cents = floor(tuning * 2.0.pow((value - 69) / 12.0) + 0.5).toInt()
                        "FREQ ${args[0]} ${frequencyText(cents)}"
                    }
                    else -> {
                        val equivalents = buildList {
                            for (octave in -1..9) {
                                for (letter in 0..6) {
                                    val alteration = value - 12 * (octave + 1) - naturals[letter]
                                    if (alteration in -2..2) add(Note(Pitch(letter, alteration), octave))
                                }
                            }
                        }
                        "ENHARMONIC ${args[0]} ${equivalents.joinToString(" ")}"
                    }
                }
            }
            "NOTE" -> {
                val value = parseNumber(args[0])
                "NOTE $value ${spelling(value, false)} ${spelling(value, true)}"
            }
            "TUNING", "PITCH" -> {
                val value = frequencyCents(args[0], command == "TUNING")
                if (command == "TUNING") {
                    tuning = value
                    "TUNING ${frequencyText(value)}"
                } else {
                    val x = 69 + 12 * log2(value.toDouble() / tuning)
                    val nearest = floor(x + 0.5).toInt()
                    if (nearest !in 0..127) throw CommandError("OUT OF RANGE")
                    val cents = floor(100 * (x - nearest) + 0.5).toInt()
                    "PITCH ${frequencyText(value)} ${spelling(nearest, false)} ${if (cents >= 0) "+" else ""}$cents"
                }
            }
            "INTERVAL" -> {
                val first = parseNote(args[0])
                val second = parseNote(args[1])
                val motion = between(first, second)
                "INTERVAL ${args[0]} ${args[1]} ${motion.interval} ${if (motion.down) "down" else "up"} semitones=${motion.semitones} simple=${motion.interval.simple()} class=${motion.interval.consonance()}"
            }
            "INVERT" -> {
                val simple = parseInterval(args[0]).simple()
                val inverse = Interval(simple.quality.inverse(), 9 - simple.number)
                if (inverse.forbidden) throw CommandError("CANNOT INVERT")
                "INVERT ${args[0]} $simple $inverse"
            }
            "TRANSPOSE" -> {
                val note = parseNote(args[0])
                val interval = parseInterval(args[1])
                val direction = args[2]
                if (direction != "UP" && direction != "DOWN") bad("DIRECTION", direction)
                val sign = if (direction == "UP") 1 else -1
                val tone = interval.tone
                val position = note.position + sign * tone.letters
                val value = note.midi + sign * tone.semitones
                val letter = mod(position, 7)
                val octave = Math.floorDiv(position, 7)
                val alteration = value - 12 * (octave + 1) - naturals[letter]
                if (alteration !in -2..2) throw CommandError("CANNOT SPELL")
                val result = Note(Pitch(letter, alteration), octave)
                if (!result.valid) throw CommandError("OUT OF RANGE")
                "TRANSPOSE ${args[0]} ${args[1]} $direction $result"
            }
            "SCALE" -> {
                val root = parsePitch(args[0])
                val scale = parseScale(args[1])
                val pitches = build(root, scale.tones)
                val steps = scale.tones.mapIndexed { i, tone -> (scale.tones.getOrNull(i + 1)?.semitones ?: 12) - tone.semitones }
                "SCALE ${args[0]} ${args[1]} ${pitches.joinToString(" ")} steps=${steps.joinToString(",")}"
            }
            "CHORD", "VOICE" -> chordCommand(command, args)
            "IDENTIFY" -> identify(args.map(::parseNote))
            "MELODY" -> melody(args.map(::parseNote))
            "CIRCLE" -> {
                val mode = parseMode(args[0])
                val pitches = (-7..7).map { fifthPitch(it - modes[mode].offset) }
                "CIRCLE ${args[0]} ${pitches.joinToString(" ")}"
            }
            "FINDKEY" -> {
                val pitches = args.map(::parsePitch)
                val keys = buildList {
                    for (p in -7..7) {
                        for (mode in 0..1) {
                            val key = makeKey(fifthPitch(p - modes[mode].offset), mode)
                            if (key.scale.containsAll(pitches)) add(key)
                        }
                    }
                }
                "FINDKEY ${keys.size}${if (keys.isEmpty()) "" else " " + keys.joinToString(", ")}"
            }
            "SPELL" -> {
                val value = parseNumber(args[0])
                val key = parseKey(args, 1)
                val pitch = key.scale.find { it.pitchClass == value % 12 } ?: spelling(value, key.fifths < 0).pitch
                val note = fromPitch(pitch, value)
                if (!note.valid) throw CommandError("OUT OF RANGE")
                "SPELL $value $key $note ${key.label(pitch)}"
            }
            else -> keyCommand(command, args)
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val count = input.readLine().toInt()
    val calculator = Calculator()
    repeat(count) {
        val response = try { calculator.execute(input.readLine()) }
        catch (error: CommandError) { error.message!! }
        output.append(response).append('\n')
    }
    output.flush()
}
