import java.util.EnumSet
import java.util.TreeSet

const val NUL = '\u0000'
const val BEL = '\u0007'
const val BS = '\u0008'
const val HT = '\u0009'
const val LF = '\u000A'
const val VT = '\u000B'
const val FF = '\u000C'
const val CR = '\u000D'
const val SO = '\u000E'
const val SI = '\u000F'
const val CAN = '\u0018'
const val SUB = '\u001A'
const val ESC = '\u001B'
val CARET_BYTES = mapOf(
    '@' to NUL, 'G' to BEL, 'H' to BS, 'I' to HT, 'J' to LF, 'K' to VT, 'L' to FF,
    'M' to CR, 'N' to SO, 'O' to SI, 'X' to CAN, 'Z' to SUB, '[' to ESC, '^' to '^',
)

val CHARSETS = mapOf('0' to Charset.LINE_DRAWING, 'B' to Charset.ASCII)

const val MAX_PARAMETER = 9999
const val MAX_FIELDS = 16
const val SCROLLBACK_LIMIT = 100
const val SCROLLBACK_SHOWN = 5
const val TAB_WIDTH = 8

val LINE_DRAWING_CHARS = mapOf(
    '`' to '*', 'a' to '#', 'j' to '+', 'k' to '+', 'l' to '+', 'm' to '+', 'n' to '+',
    't' to '+', 'u' to '+', 'v' to '+', 'w' to '+', 'q' to '-', 'x' to '|', '~' to 'o',
)
val COLOR_NAMES = listOf("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")
val FLAG_NAMES =
    listOf("bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike")
val SGR_FLAGS_ON = mapOf(1 to 0, 2 to 1, 3 to 2, 4 to 3, 5 to 4, 7 to 5, 8 to 6, 9 to 7)
val SGR_FLAGS_OFF = mapOf(
    22 to listOf(0, 1), 23 to listOf(2), 24 to listOf(3), 25 to listOf(4),
    27 to listOf(5), 28 to listOf(6), 29 to listOf(7),
)

val SOFT_RESET_MODES =
    listOf(Mode.IRM, Mode.DECCKM, Mode.DECOM, Mode.DECAWM, Mode.DECTCEM, Mode.DECKPAM)
val ANSI_MODES = mapOf(4 to Mode.IRM, 20 to Mode.LNM)
val DEC_MODES = mapOf(
    1 to Mode.DECCKM, 5 to Mode.DECSCNM, 6 to Mode.DECOM, 7 to Mode.DECAWM,
    25 to Mode.DECTCEM, 2004 to Mode.BRACKETED,
)
val SCREEN_MODES = setOf(47, 1047, 1049)
val DEC_MODE_NUMBERS = setOf(1, 5, 6, 7, 25, 47, 1047, 1048, 1049, 2004)

val CSI_CONDITIONS = mapOf(
    "J" to setOf(0, 1, 2, 3),
    "K" to setOf(0, 1, 2),
    "g" to setOf(0, 3),
    " q" to setOf(0, 1, 2, 3, 4, 5, 6),
    "n" to setOf(5, 6),
    "?n" to setOf(6),
    "c" to setOf(0),
    ">c" to setOf(0),
    "t" to setOf(18),
)
const val WRAP_CLEARING_CSI = "ABCDEFGHIJKLMPSTXZ`adef@"

val CURSOR_KEYS = mapOf(
    "UP" to 'A', "DOWN" to 'B', "RIGHT" to 'C', "LEFT" to 'D', "HOME" to 'H', "END" to 'F',
)
val FIXED_KEYS = mapOf(
    "INSERT" to "^[[2~", "DELETE" to "^[[3~", "PAGEUP" to "^[[5~", "PAGEDOWN" to "^[[6~",
    "F1" to "^[OP", "F2" to "^[OQ", "F3" to "^[OR", "F4" to "^[OS",
    "F5" to "^[[15~", "F6" to "^[[17~", "F7" to "^[[18~", "F8" to "^[[19~",
    "F9" to "^[[20~", "F10" to "^[[21~", "F11" to "^[[23~", "F12" to "^[[24~",
    "TAB" to "^I", "BACKSPACE" to "^?", "ESCAPE" to "^[",
)
const val KEY_PREFIX = "%%KEY "
const val PASTE_PREFIX = "%%PASTE "

enum class ParserState {
    GROUND,
    ESCAPE,
    ESCAPE_INTERMEDIATE,
    CSI_ENTRY,
    CSI_PARAM,
    CSI_INTERMEDIATE,
    CSI_IGNORE,
    OSC_STRING,
}

enum class Reason { UNSUPPORTED, MALFORMED, CANCELED, INVALID }

enum class Display { MAIN, ALTERNATE }

enum class Charset { ASCII, LINE_DRAWING }

enum class Mode(val initial: Boolean) {
    IRM(false),
    LNM(false),
    DECCKM(false),
    DECSCNM(false),
    DECOM(false),
    DECAWM(true),
    DECTCEM(true),
    DECKPAM(false),
    BRACKETED(false),
}

class SequenceIgnored(val reason: Reason) : Exception()

fun ensure(condition: Boolean, reason: Reason = Reason.UNSUPPORTED) {
    if (!condition) throw SequenceIgnored(reason)
}

fun isIntermediate(ch: Char) = ch in ' '..'/'

fun isParameter(ch: Char) = ch in '0'..'9' || ch == ';'

fun isPrivateMarker(ch: Char) = ch in '<'..'?'

fun isFinal(ch: Char) = ch in '@'..'~'

fun decodeStream(line: String): String = buildString {
    var index = 0
    while (index < line.length) {
        if (line[index] == '^') {
            append(CARET_BYTES.getValue(line[index + 1]))
            index += 2
        } else {
            append(line[index])
            index++
        }
    }
}

fun fieldValue(field: String): Int =
    field.fold(0) { value, digit -> minOf(value * 10 + digit.digitToInt(), MAX_PARAMETER) }

fun parameter(params: List<Int>, index: Int) = params.getOrElse(index) { 0 }

fun amount(params: List<Int>) = maxOf(parameter(params, 0), 1)

fun paletteColor(number: Int): String = when {
    number < 8 -> COLOR_NAMES[number]
    number < 16 -> "bright-" + COLOR_NAMES[number - 8]
    else -> number.toString()
}

fun rgbColor(red: Int, green: Int, blue: Int) = "#%02x%02x%02x".format(red, green, blue)

fun extendedColor(values: List<Int>, start: Int): Pair<String, Int> {
    val rest = values.drop(start)
    if (rest.size >= 2 && rest[0] == 5 && rest[1] <= 255) {
        return paletteColor(rest[1]) to 2
    }
    if (rest.size >= 4 && rest[0] == 2 && rest.subList(1, 4).all { it <= 255 }) {
        return rgbColor(rest[1], rest[2], rest[3]) to 4
    }
    throw SequenceIgnored(Reason.UNSUPPORTED)
}

fun modeState(enabled: Boolean) = if (enabled) 1 else 2

fun rowText(cells: Array<Cell>) = cells.joinToString("") { it.char.toString() }.trimEnd(' ')

data class Attributes(
    val flags: Int = 0,
    val foreground: String? = null,
    val background: String? = null,
) {
    fun isDefault() = this == DEFAULT

    fun describe(): String = buildList {
        FLAG_NAMES.forEachIndexed { index, name -> if (flags shr index and 1 == 1) add(name) }
        foreground?.let { add("fg=$it") }
        background?.let { add("bg=$it") }
    }.joinToString(" ")

    companion object {
        val DEFAULT = Attributes()
    }
}

data class Cell(val char: Char, val attributes: Attributes) {
    companion object {
        val BLANK = Cell(' ', Attributes.DEFAULT)
    }
}

data class SavedCursor(
    val row: Int = 1,
    val column: Int = 1,
    val attributes: Attributes = Attributes.DEFAULT,
    val origin: Boolean = false,
    val g0: Charset = Charset.ASCII,
    val g1: Charset = Charset.ASCII,
    val gl: Int = 0,
)

class Screen(private val width: Int, private val height: Int) {
    var rows: MutableList<Array<Cell>> = MutableList(height) { blankRow() }
        private set

    fun blankRow() = Array(width) { Cell.BLANK }

    fun clear() {
        rows = MutableList(height) { blankRow() }
    }

    fun fill(char: Char) {
        val cell = Cell(char, Attributes.DEFAULT)
        rows = MutableList(height) { Array(width) { cell } }
    }

    fun put(row: Int, column: Int, cell: Cell) {
        rows[row - 1][column - 1] = cell
    }

    fun erase(row: Int, first: Int, last: Int) {
        rows[row - 1].fill(Cell.BLANK, first - 1, last)
    }

    fun eraseRows(first: Int, last: Int) {
        for (row in first..last) {
            rows[row - 1] = blankRow()
        }
    }

    fun scrollUp(top: Int, bottom: Int): Array<Cell> {
        val removed = rows.removeAt(top - 1)
        rows.add(bottom - 1, blankRow())
        return removed
    }

    fun scrollDown(top: Int, bottom: Int) {
        rows.removeAt(bottom - 1)
        rows.add(top - 1, blankRow())
    }

    fun insertCells(row: Int, column: Int, count: Int) {
        val cells = rows[row - 1]
        cells.copyInto(cells, column - 1 + count, column - 1, width - count)
        cells.fill(Cell.BLANK, column - 1, column - 1 + count)
    }

    fun deleteCells(row: Int, column: Int, count: Int) {
        val cells = rows[row - 1]
        cells.copyInto(cells, column - 1, column - 1 + count, width)
        cells.fill(Cell.BLANK, width - count, width)
    }

    fun text(row: Int) = rowText(rows[row - 1])
}

class Terminal(private val width: Int, private val height: Int) {
    val output = StringBuilder()
    private val ignored = IntArray(Reason.entries.size)
    private var streamBytes = 0
    private var printed = 0
    private var sequences = 0
    private var bells = 0
    private var replies = 0
    private var dumps = 0

    private val screens = List(2) { Screen(width, height) }
    private var display = Display.MAIN
    private var row = 1
    private var column = 1
    private var pendingWrap = false
    private var attributes = Attributes.DEFAULT
    private var g0 = Charset.ASCII
    private var g1 = Charset.ASCII
    private var gl = 0
    private val modes = EnumSet.noneOf(Mode::class.java)
    private var cursorShape = 1
    private var top = 1
    private var bottom = height
    private val tabStops = TreeSet<Int>()
    private val saved = arrayOfNulls<SavedCursor>(2)
    private val scrollback = ArrayDeque<String>()
    private var title: String? = null
    private var lastChar: Char? = null
    private var state = ParserState.GROUND
    private var marker = ""
    private var parameters = ""
    private var intermediates = ""
    private var osc = ""

    private val screen: Screen
        get() = screens[display.ordinal]

    init {
        reset()
    }

    private fun reset() {
        screens.forEach { it.clear() }
        display = Display.MAIN
        row = 1
        column = 1
        pendingWrap = false
        attributes = Attributes.DEFAULT
        g0 = Charset.ASCII
        g1 = Charset.ASCII
        gl = 0
        modes.clear()
        Mode.entries.filterTo(modes) { it.initial }
        cursorShape = 1
        top = 1
        bottom = height
        tabStops.clear()
        tabStops.addAll(TAB_WIDTH + 1..width step TAB_WIDTH)
        saved.fill(null)
        scrollback.clear()
        title = null
        lastChar = null
        state = ParserState.GROUND
        clearSequence()
    }

    private fun clearSequence() {
        marker = ""
        parameters = ""
        intermediates = ""
        osc = ""
    }

    private fun emit(line: String) {
        output.append(line).append('\n')
    }

    private fun ignore(reason: Reason) {
        ignored[reason.ordinal]++
    }

    private fun setMode(mode: Mode, enabled: Boolean) {
        if (enabled) modes.add(mode) else modes.remove(mode)
    }

    fun receive(ch: Char) {
        streamBytes++
        if (ch < ' ') {
            receiveControl(ch)
            return
        }
        when (state) {
            ParserState.GROUND -> printChar(ch)
            ParserState.ESCAPE, ParserState.ESCAPE_INTERMEDIATE -> escapeByte(ch)
            ParserState.OSC_STRING -> osc += ch
            ParserState.CSI_IGNORE -> {
                if (isFinal(ch)) {
                    ignore(Reason.MALFORMED)
                    state = ParserState.GROUND
                }
            }
            ParserState.CSI_INTERMEDIATE -> csiIntermediateByte(ch)
            ParserState.CSI_ENTRY -> {
                if (isPrivateMarker(ch)) {
                    marker = ch.toString()
                    state = ParserState.CSI_PARAM
                } else {
                    csiParamByte(ch)
                }
            }
            ParserState.CSI_PARAM -> csiParamByte(ch)
        }
    }

    private fun receiveControl(ch: Char) {
        when {
            ch == ESC -> {
                if (state == ParserState.OSC_STRING) {
                    executeOsc()
                } else if (state != ParserState.GROUND) {
                    ignore(Reason.CANCELED)
                }
                clearSequence()
                state = ParserState.ESCAPE
            }
            ch == CAN || ch == SUB -> {
                if (state != ParserState.GROUND) {
                    ignore(Reason.CANCELED)
                    state = ParserState.GROUND
                }
            }
            state == ParserState.OSC_STRING -> {
                if (ch == BEL) {
                    executeOsc()
                    state = ParserState.GROUND
                }
            }
            else -> executeControl(ch)
        }
    }

    private fun escapeByte(ch: Char) {
        when {
            isIntermediate(ch) -> {
                intermediates += ch
                state = ParserState.ESCAPE_INTERMEDIATE
            }
            state == ParserState.ESCAPE && ch == '[' -> state = ParserState.CSI_ENTRY
            state == ParserState.ESCAPE && ch == ']' -> state = ParserState.OSC_STRING
            else -> {
                executeEsc(intermediates + ch)
                state = ParserState.GROUND
            }
        }
    }

    private fun csiParamByte(ch: Char) {
        when {
            isParameter(ch) -> {
                parameters += ch
                state = ParserState.CSI_PARAM
            }
            isIntermediate(ch) -> {
                intermediates += ch
                state = ParserState.CSI_INTERMEDIATE
            }
            isFinal(ch) -> {
                executeCsi(ch)
                state = ParserState.GROUND
            }
            else -> state = ParserState.CSI_IGNORE
        }
    }

    private fun csiIntermediateByte(ch: Char) {
        when {
            isIntermediate(ch) -> intermediates += ch
            isFinal(ch) -> {
                executeCsi(ch)
                state = ParserState.GROUND
            }
            else -> state = ParserState.CSI_IGNORE
        }
    }

    private fun executeControl(ch: Char) {
        when (ch) {
            BEL -> bells++
            BS -> {
                pendingWrap = false
                column = maxOf(column - 1, 1)
            }
            HT -> {
                pendingWrap = false
                tabMove(1)
            }
            LF, VT, FF -> {
                pendingWrap = false
                lineFeed()
                if (Mode.LNM in modes) {
                    column = 1
                }
            }
            CR -> {
                pendingWrap = false
                column = 1
            }
            SO -> gl = 1
            SI -> gl = 0
        }
    }

    private fun printChar(ch: Char) {
        val charset = if (gl == 1) g1 else g0
        write(if (charset == Charset.LINE_DRAWING) LINE_DRAWING_CHARS[ch] ?: ch else ch)
    }

    private fun write(char: Char) {
        printed++
        lastChar = char
        if (pendingWrap) {
            pendingWrap = false
            column = 1
            lineFeed()
        }
        if (Mode.IRM in modes) {
            screen.insertCells(row, column, 1)
        }
        screen.put(row, column, Cell(char, attributes))
        if (column < width) {
            column++
        } else if (Mode.DECAWM in modes) {
            pendingWrap = true
        }
    }

    private fun scrollRegionUp() {
        val removed = screen.scrollUp(top, bottom)
        if (display == Display.MAIN && top == 1) {
            scrollback.addLast(rowText(removed))
            if (scrollback.size > SCROLLBACK_LIMIT) {
                scrollback.removeFirst()
            }
        }
    }

    private fun scrollRegionDown() {
        screen.scrollDown(top, bottom)
    }

    private fun lineFeed() {
        if (row == bottom) {
            scrollRegionUp()
        } else if (row < height) {
            row++
        }
    }

    private fun reverseLineFeed() {
        if (row == top) {
            scrollRegionDown()
        } else if (row > 1) {
            row--
        }
    }

    private fun tabMove(count: Int) {
        repeat(count) {
            if (column == width) return
            column = tabStops.higher(column) ?: width
        }
    }

    private fun reverseTabMove(count: Int) {
        repeat(count) {
            if (column == 1) return
            column = tabStops.lower(column) ?: 1
        }
    }

    private fun addressRow(value: Int) =
        if (Mode.DECOM in modes) minOf(top + value - 1, bottom) else minOf(value, height)

    private fun home() {
        row = addressRow(1)
        column = 1
    }

    private fun saveCursor() {
        saved[display.ordinal] =
            SavedCursor(row, column, attributes, Mode.DECOM in modes, g0, g1, gl)
    }

    private fun restoreCursor() {
        pendingWrap = false
        val cursor = saved[display.ordinal] ?: SavedCursor()
        row = cursor.row
        column = cursor.column
        attributes = cursor.attributes
        setMode(Mode.DECOM, cursor.origin)
        g0 = cursor.g0
        g1 = cursor.g1
        gl = cursor.gl
    }

    private fun screenAlignment() {
        pendingWrap = false
        screen.fill('E')
        top = 1
        bottom = height
        setMode(Mode.DECOM, false)
        row = 1
        column = 1
    }

    private fun executeEsc(key: String) {
        when (key) {
            "7" -> saveCursor()
            "8" -> restoreCursor()
            "D" -> {
                pendingWrap = false
                lineFeed()
            }
            "E" -> {
                pendingWrap = false
                column = 1
                lineFeed()
            }
            "M" -> {
                pendingWrap = false
                reverseLineFeed()
            }
            "H" -> tabStops.add(column)
            "c" -> reset()
            "=", ">" -> setMode(Mode.DECKPAM, key == "=")
            "\\" -> {}
            "(0", "(B" -> g0 = CHARSETS.getValue(key[1])
            ")0", ")B" -> g1 = CHARSETS.getValue(key[1])
            "#8" -> screenAlignment()
            else -> {
                ignore(Reason.UNSUPPORTED)
                return
            }
        }
        sequences++
    }

    private fun executeOsc() {
        if (osc.startsWith("0;") || osc.startsWith("2;")) {
            title = osc.substring(2)
            sequences++
        } else {
            ignore(Reason.UNSUPPORTED)
        }
    }

    private fun executeCsi(finalByte: Char) {
        val key = marker + intermediates + finalByte
        val fields = if (parameters.isEmpty()) emptyList() else parameters.split(";")
        try {
            ensure(fields.size <= MAX_FIELDS, Reason.INVALID)
            val params = fields.map(::fieldValue)
            val allowed = CSI_CONDITIONS[key]
            ensure(allowed == null || parameter(params, 0) in allowed)
            if (key.length == 1 && key in WRAP_CLEARING_CSI) {
                pendingWrap = false
            }
            dispatchCsi(key, params)
        } catch (ignoredSequence: SequenceIgnored) {
            ignore(ignoredSequence.reason)
            return
        }
        sequences++
    }

    private fun dispatchCsi(key: String, params: List<Int>) {
        when (key) {
            "A" -> moveUp(amount(params))
            "B", "e" -> moveDown(amount(params))
            "C", "a" -> column = minOf(column + amount(params), width)
            "D" -> column = maxOf(column - amount(params), 1)
            "E" -> {
                moveDown(amount(params))
                column = 1
            }
            "F" -> {
                moveUp(amount(params))
                column = 1
            }
            "G", "`" -> column = minOf(amount(params), width)
            "H", "f" -> {
                row = addressRow(amount(params))
                column = parameter(params, 1).coerceIn(1, width)
            }
            "d" -> row = addressRow(amount(params))
            "I" -> tabMove(amount(params))
            "Z" -> reverseTabMove(amount(params))
            "J" -> eraseInDisplay(parameter(params, 0))
            "K" -> eraseInLine(parameter(params, 0))
            "X" -> screen.erase(row, column, minOf(column + amount(params) - 1, width))
            "@" -> screen.insertCells(row, column, minOf(amount(params), width - column + 1))
            "P" -> screen.deleteCells(row, column, minOf(amount(params), width - column + 1))
            "L" -> insertLines(amount(params))
            "M" -> deleteLines(amount(params))
            "S" -> repeat(minOf(amount(params), bottom - top + 1)) { scrollRegionUp() }
            "T" -> repeat(minOf(amount(params), bottom - top + 1)) { scrollRegionDown() }
            "b" -> lastChar?.let { char -> repeat(amount(params)) { write(char) } }
            "g" -> if (parameter(params, 0) == 0) tabStops.remove(column) else tabStops.clear()
            "m" -> selectGraphicRendition(params)
            "h", "l" -> setAnsiModes(params, key == "h")
            "?h", "?l" -> setDecModes(params, key == "?h")
            " q" -> cursorShape = amount(params)
            "r" -> setScrollRegion(params)
            "s" -> saveCursor()
            "u" -> restoreCursor()
            "!p" -> softReset()
            "n" -> deviceStatusReport(parameter(params, 0))
            "?n" -> reply("^[[?${reportedRow()};$column;1R")
            "c" -> reply("^[[?1;2c")
            ">c" -> reply("^[[>0;95;0c")
            "t" -> reply("^[[8;$height;${width}t")
            "\$p" -> requestAnsiMode(parameter(params, 0))
            "?\$p" -> requestDecMode(parameter(params, 0))
            else -> throw SequenceIgnored(Reason.UNSUPPORTED)
        }
    }

    private fun moveUp(count: Int) {
        val limit = if (row >= top) top else 1
        row = maxOf(row - count, limit)
    }

    private fun moveDown(count: Int) {
        val limit = if (row <= bottom) bottom else height
        row = minOf(row + count, limit)
    }

    private fun eraseInDisplay(mode: Int) {
        when (mode) {
            0 -> {
                screen.erase(row, column, width)
                screen.eraseRows(row + 1, height)
            }
            1 -> {
                screen.eraseRows(1, row - 1)
                screen.erase(row, 1, column)
            }
            2 -> screen.clear()
            else -> scrollback.clear()
        }
    }

    private fun eraseInLine(mode: Int) {
        val first = if (mode == 0) column else 1
        val last = if (mode == 1) column else width
        screen.erase(row, first, last)
    }

    private fun insertLines(count: Int) {
        if (row in top..bottom) {
            repeat(minOf(count, bottom - row + 1)) { screen.scrollDown(row, bottom) }
            column = 1
        }
    }

    private fun deleteLines(count: Int) {
        if (row in top..bottom) {
            repeat(minOf(count, bottom - row + 1)) { screen.scrollUp(row, bottom) }
            column = 1
        }
    }

    private fun selectGraphicRendition(params: List<Int>) {
        val values = params.ifEmpty { listOf(0) }
        var (flags, foreground, background) = attributes
        var index = 0
        while (index < values.size) {
            val value = values[index]
            when (value) {
                0 -> {
                    flags = 0
                    foreground = null
                    background = null
                }
                in SGR_FLAGS_ON -> flags = flags or (1 shl SGR_FLAGS_ON.getValue(value))
                in SGR_FLAGS_OFF -> {
                    for (flag in SGR_FLAGS_OFF.getValue(value)) {
                        flags = flags and (1 shl flag).inv()
                    }
                }
                in 30..37 -> foreground = paletteColor(value - 30)
                in 90..97 -> foreground = paletteColor(value - 82)
                in 40..47 -> background = paletteColor(value - 40)
                in 100..107 -> background = paletteColor(value - 92)
                39 -> foreground = null
                49 -> background = null
                38, 48 -> {
                    val (color, used) = extendedColor(values, index + 1)
                    if (value == 38) foreground = color else background = color
                    index += used
                }
                else -> throw SequenceIgnored(Reason.UNSUPPORTED)
            }
            index++
        }
        attributes = Attributes(flags, foreground, background)
    }

    private fun setAnsiModes(params: List<Int>, enabled: Boolean) {
        val values = params.ifEmpty { listOf(0) }
        ensure(values.all { it in ANSI_MODES })
        for (value in values) {
            setMode(ANSI_MODES.getValue(value), enabled)
        }
    }

    private fun setDecModes(params: List<Int>, enabled: Boolean) {
        val values = params.ifEmpty { listOf(0) }
        ensure(values.all { it in DEC_MODE_NUMBERS })
        for (value in values) {
            when {
                value in DEC_MODES -> setDecFlag(value, enabled)
                value == 1048 -> if (enabled) saveCursor() else restoreCursor()
                else -> switchScreen(value, enabled)
            }
        }
    }

    private fun setDecFlag(value: Int, enabled: Boolean) {
        if (value == 6 || (value == 7 && !enabled)) {
            pendingWrap = false
        }
        setMode(DEC_MODES.getValue(value), enabled)
        if (value == 6) {
            home()
        }
    }

    private fun switchScreen(value: Int, enabled: Boolean) {
        pendingWrap = false
        if (enabled && display == Display.MAIN) {
            if (value == 1049) saveCursor()
            display = Display.ALTERNATE
            if (value == 1049) screen.clear()
        } else if (!enabled && display == Display.ALTERNATE) {
            if (value == 1047) screen.clear()
            display = Display.MAIN
            if (value == 1049) restoreCursor()
        }
    }

    private fun setScrollRegion(params: List<Int>) {
        val newTop = amount(params)
        val requested = parameter(params, 1)
        val newBottom = minOf(if (requested == 0) height else requested, height)
        ensure(newTop < newBottom, Reason.INVALID)
        pendingWrap = false
        top = newTop
        bottom = newBottom
        home()
    }

    private fun softReset() {
        pendingWrap = false
        for (mode in SOFT_RESET_MODES) {
            setMode(mode, mode.initial)
        }
        top = 1
        bottom = height
        attributes = Attributes.DEFAULT
        g0 = Charset.ASCII
        g1 = Charset.ASCII
        gl = 0
        saved[display.ordinal] = null
    }

    private fun reply(text: String) {
        replies++
        emit("REPLY $text")
    }

    private fun reportedRow() = if (Mode.DECOM in modes) maxOf(row - top + 1, 1) else row

    private fun deviceStatusReport(mode: Int) {
        reply(if (mode == 5) "^[[0n" else "^[[${reportedRow()};${column}R")
    }

    private fun requestAnsiMode(mode: Int) {
        val status = ANSI_MODES[mode]?.let { modeState(it in modes) } ?: 0
        reply("^[[$mode;$status\$y")
    }

    private fun requestDecMode(mode: Int) {
        val decMode = DEC_MODES[mode]
        val status = when {
            decMode != null -> modeState(decMode in modes)
            mode in SCREEN_MODES -> modeState(display == Display.ALTERNATE)
            else -> 0
        }
        reply("^[[?$mode;$status\$y")
    }

    private fun keyString(name: String): String {
        CURSOR_KEYS[name]?.let { suffix ->
            return (if (Mode.DECCKM in modes) "^[O" else "^[[") + suffix
        }
        FIXED_KEYS[name]?.let { return it }
        val enter = if (Mode.LNM in modes) "^M^J" else "^M"
        if (name == "ENTER") {
            return enter
        }
        if (name == "KPENTER") {
            return if (Mode.DECKPAM in modes) "^[OM" else enter
        }
        val digit = name.substring(2).toInt()
        return if (Mode.DECKPAM in modes) "^[O${Char(0x70 + digit)}" else digit.toString()
    }

    fun pressKey(name: String) {
        emit("KEY $name ${keyString(name)}")
    }

    fun paste(text: String) {
        val sent = text.replace("^", "^^")
        emit("PASTE " + if (Mode.BRACKETED in modes) "^[[200~$sent^[[201~" else sent)
    }

    private fun screenOutput(label: String) {
        val name = if (display == Display.ALTERNATE) "alt" else "main"
        val header = "$label $name cursor $row,$column scrollback ${scrollback.size}"
        emit(if (pendingWrap) "$header pending" else header)
        for (number in 1..height) {
            emit("|" + screen.text(number))
        }
    }

    fun dump() {
        dumps++
        screenOutput("DUMP $dumps")
    }

    private fun changedModes(): List<String> = buildList {
        for (mode in Mode.entries) {
            val enabled = mode in modes
            if (enabled != mode.initial) {
                add("$mode=${if (enabled) "on" else "off"}")
            }
        }
        if (g0 == Charset.LINE_DRAWING) add("G0=graphics")
        if (g1 == Charset.LINE_DRAWING) add("G1=graphics")
        if (gl == 1) add("GL=G1")
        if (cursorShape != 1) add("CURSOR=$cursorShape")
    }

    private fun attributeRuns(): List<String> {
        val runs = mutableListOf<String>()
        for ((index, cells) in screen.rows.withIndex()) {
            var start = 0
            for (next in 1..width) {
                if (next < width && cells[next].attributes == cells[start].attributes) {
                    continue
                }
                val run = cells[start].attributes
                if (!run.isDefault()) {
                    runs.add("row ${index + 1} col ${start + 1}-$next ${run.describe()}")
                }
                start = next
            }
        }
        return runs
    }

    fun finish() {
        if (state != ParserState.GROUND) {
            ignore(Reason.CANCELED)
            state = ParserState.GROUND
        }
        screenOutput("FINAL")
        emit("TITLE " + (title?.let { "\"$it\"" } ?: "none"))
        emit("MODES " + changedModes().ifEmpty { listOf("default") }.joinToString(" "))
        emit("REGION $top-$bottom")
        emit("TABS " + if (tabStops.isEmpty()) "none" else tabStops.joinToString(","))
        emit("SCROLLBACK ${scrollback.size}")
        scrollback.takeLast(SCROLLBACK_SHOWN).forEach { emit("|$it") }
        val runs = attributeRuns()
        emit("ATTRS ${runs.size}")
        runs.forEach(this::emit)
        emit("BELL $bells")
        emit("REPLIES $replies")
        emit("STATS bytes=$streamBytes printed=$printed sequences=$sequences")
        val counts = Reason.entries.joinToString(" ") {
            "${it.name.lowercase()}=${ignored[it.ordinal]}"
        }
        emit("IGNORED ${ignored.sum()} $counts")
    }
}

fun main() {
    val (width, height) = readln().split(" ").map(String::toInt)
    val terminal = Terminal(width, height)
    for (line in generateSequence(::readlnOrNull).takeWhile { it != "%%END" }) {
        when {
            line == "%%DUMP" -> terminal.dump()
            line.startsWith(KEY_PREFIX) -> terminal.pressKey(line.removePrefix(KEY_PREFIX))
            line.startsWith(PASTE_PREFIX) -> terminal.paste(line.removePrefix(PASTE_PREFIX))
            else -> decodeStream(line).forEach(terminal::receive)
        }
    }
    terminal.finish()
    print(terminal.output)
}
