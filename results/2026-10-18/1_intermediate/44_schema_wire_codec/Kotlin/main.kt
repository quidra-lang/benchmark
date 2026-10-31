import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.util.Base64

private const val VARINT_LIMIT = 9_007_199_254_740_992L
private const val HEX_DIGITS = "0123456789abcdef"
private val INTEGER_RANGES = mapOf(
    "uint32" to (0L..4_294_967_295L),
    "uint64" to (0L..9_007_199_254_740_991L),
    "sint32" to (-2_147_483_648L..2_147_483_647L),
    "sint64" to (-4_503_599_627_370_496L..4_503_599_627_370_495L),
    "fixed32" to (0L..4_294_967_295L),
    "sfixed32" to (-2_147_483_648L..2_147_483_647L),
    "fixed64" to (0L..9_007_199_254_740_991L)
)
private val SCALAR_WIRES = mapOf(
    "uint32" to 0, "uint64" to 0, "sint32" to 0, "sint64" to 0,
    "bool" to 0, "fixed32" to 5, "sfixed32" to 5, "fixed64" to 1,
    "string" to 2, "bytes" to 2
)
private val WIRE_NAMES = mapOf(0 to "varint", 1 to "i64", 2 to "len", 5 to "i32")

private class CommandError(message: String) : RuntimeException(message)
private fun byteError(reason: String, offset: Int): Nothing =
    throw CommandError("$reason at byte $offset")

private fun columnError(reason: String, column: Int): Nothing =
    throw CommandError("$reason at column $column")

private fun zigzag(number: Long) = if (number >= 0) 2 * number else -2 * number - 1
private fun unzigzag(number: Long) = if (number % 2 == 0L) number / 2 else -(number + 1) / 2
private fun isHex(text: String) = text.all { it in HEX_DIGITS }
private fun isLetter(char: Char) = char in 'a'..'z' || char in 'A'..'Z'

private fun hexDigits(data: ByteArray) = buildString {
    for (byte in data) {
        val value = byte.toInt() and 255
        append(HEX_DIGITS[value / 16])
        append(HEX_DIGITS[value % 16])
    }
}

private fun hexText(data: ByteArray) = if (data.isEmpty()) "-" else hexDigits(data)
private fun bytesNotation(data: ByteArray) = "<${hexDigits(data)}>"

private fun hexBytes(text: String) = ByteArray(text.length / 2) { index ->
    (HEX_DIGITS.indexOf(text[2 * index]) * 16 + HEX_DIGITS.indexOf(text[2 * index + 1])).toByte()
}

private fun parseHex(text: String): ByteArray {
    if (text == "-") return byteArrayOf()
    if (text.isEmpty() || text.length % 2 != 0 || !isHex(text)) throw CommandError("invalid hex")
    return hexBytes(text)
}

private fun writeVarint(output: ByteArrayOutputStream, value: Long) {
    var remaining = value
    while (remaining >= 128) {
        output.write((remaining % 128 + 128).toInt())
        remaining /= 128
    }
    output.write(remaining.toInt())
}

private fun varintBytes(value: Long): ByteArray {
    val output = ByteArrayOutputStream()
    writeVarint(output, value)
    return output.toByteArray()
}

private fun quote(data: ByteArray, json: Boolean = false) = buildString {
    append('"')
    for (byte in data) {
        val value = byte.toInt() and 255
        when (value) {
            0x22 -> append("\\\"")
            0x5c -> append("\\\\")
            0x0a -> append("\\n")
            0x09 -> append("\\t")
            in 0x20..0x7e -> append(value.toChar())
            else -> {
                append(if (json) "\\u00" else "\\x")
                append(HEX_DIGITS[value / 16])
                append(HEX_DIGITS[value % 16])
            }
        }
    }
    append('"')
}

private class EnumType(val name: String) {
    val byName = mutableMapOf<String, Long>()
    val byNumber = mutableMapOf<Long, String>()
}

private class Field(
    val number: Long,
    val typeName: String,
    val name: String,
    val required: Boolean,
    val repeated: Boolean,
    val packed: Boolean,
    val group: String?
) {
    var wire = 2
    var enumType: EnumType? = null
    var messageType: MessageType? = null
    val packable get() = wire != 2

    fun kindWord() = when {
        required -> "required "
        packed -> "repeated packed "
        repeated -> "repeated "
        group != null -> "oneof $group "
        else -> ""
    }
}

private class MessageType(val name: String) {
    val fields = mutableListOf<Field>()
    val byNumber = mutableMapOf<Long, Field>()
    val byName = mutableMapOf<String, Field>()

    fun add(field: Field) {
        fields.add(field)
        byNumber[field.number] = field
        byName[field.name] = field
    }
}

private class Schema {
    val enums = mutableMapOf<String, EnumType>()
    val messages = mutableMapOf<String, MessageType>()
}

private fun readSchema(input: BufferedReader): Schema {
    val schema = Schema()
    var currentEnum: EnumType? = null
    var currentMessage: MessageType? = null
    while (true) {
        val line = input.readLine()
        if (line == "END SCHEMA") break
        val words = line.split(' ')
        when (words[0]) {
            "ENUM" -> {
                currentEnum = EnumType(words[1])
                schema.enums[words[1]] = currentEnum
                currentMessage = null
            }
            "MESSAGE" -> {
                currentMessage = MessageType(words[1])
                schema.messages[words[1]] = currentMessage
                currentEnum = null
            }
            "VALUE" -> {
                val number = words[2].toLong()
                val enumType = currentEnum!!
                enumType.byName[words[1]] = number
                enumType.byNumber[number] = words[1]
            }
            "FIELD" -> {
                val options = words.drop(4)
                currentMessage!!.add(Field(
                    words[1].toLong(), words[2], words[3],
                    options.firstOrNull() == "REQUIRED", options.firstOrNull() == "REPEATED",
                    options == listOf("REPEATED", "PACKED"),
                    if (options.firstOrNull() == "ONEOF") options[1] else null
                ))
            }
            "END" -> {
                currentEnum = null
                currentMessage = null
            }
        }
    }
    for (type in schema.messages.values) {
        type.fields.sortBy { it.number }
        for (field in type.fields) {
            field.enumType = schema.enums[field.typeName]
            field.messageType = schema.messages[field.typeName]
            field.wire = SCALAR_WIRES[field.typeName] ?: if (field.enumType != null) 0 else 2
        }
    }
    return schema
}

private sealed interface Value
private data class IntegerValue(val number: Long) : Value
private data class BooleanValue(val boolean: Boolean) : Value
private data class EnumValue(val name: String, val number: Long) : Value
private data class DataValue(val data: ByteArray) : Value
private data class NestedValue(val message: Message) : Value

private data class UnknownField(
    val number: Long,
    val wire: Int,
    val rawNumber: Long = 0,
    val rawBytes: ByteArray = byteArrayOf()
) {
    fun notation() = if (wire == 0) rawNumber.toString() else bytesNotation(rawBytes)
}

private class Message(val type: MessageType) {
    val values = mutableMapOf<Long, MutableList<Value>>()
    val unknown = mutableListOf<UnknownField>()

    fun elements(field: Field): List<Value> = values[field.number] ?: emptyList()
    fun has(field: Field) = !values[field.number].isNullOrEmpty()

    fun setElements(field: Field, elements: List<Value>) {
        if (elements.isEmpty()) values.remove(field.number)
        else values[field.number] = elements.toMutableList()
    }

    fun clearGroup(field: Field) {
        if (field.group == null) return
        for (other in type.fields) {
            if (other.number != field.number && other.group == field.group) values.remove(other.number)
        }
    }

    fun apply(field: Field, incoming: List<Value>) {
        clearGroup(field)
        when {
            field.repeated -> {
                if (incoming.isNotEmpty()) values.getOrPut(field.number) { mutableListOf() }.addAll(incoming)
            }
            field.messageType != null && has(field) -> {
                val target = (elements(field).single() as NestedValue).message
                merge(target, (incoming.single() as NestedValue).message)
            }
            else -> setElements(field, incoming)
        }
    }
}

private fun merge(target: Message, source: Message) {
    for (field in source.type.fields) {
        if (source.has(field)) target.apply(field, source.elements(field))
    }
    target.unknown.addAll(source.unknown)
}

private fun checkRequired(message: Message, prefix: String = "") {
    for (field in message.type.fields) {
        val path = prefix + field.name
        if (field.required && !message.has(field)) throw CommandError("missing required field $path")
        if (field.messageType != null) {
            for ((index, value) in message.elements(field).withIndex()) {
                val segment = path + if (field.repeated) "[$index]" else ""
                checkRequired((value as NestedValue).message, "$segment.")
            }
        }
    }
}

private fun valueBytes(field: Field, value: Value): ByteArray {
    return when (value) {
        is DataValue -> value.data
        is NestedValue -> encode(value.message)
        is BooleanValue -> varintBytes(if (value.boolean) 1 else 0)
        is EnumValue -> varintBytes(value.number)
        is IntegerValue -> {
            if (field.wire == 0) {
                varintBytes(if (field.typeName in setOf("sint32", "sint64")) zigzag(value.number) else value.number)
            } else {
                val number = if (field.typeName == "sfixed32" && value.number < 0)
                    value.number + 4_294_967_296L else value.number
                ByteArray(if (field.wire == 5) 4 else 8) { index ->
                    (number ushr (8 * index)).toByte()
                }
            }
        }
    }
}

private fun encodeField(field: Field, elements: List<Value>): ByteArray {
    val output = ByteArrayOutputStream()
    if (elements.isEmpty()) return output.toByteArray()
    if (field.packed) {
        val payload = ByteArrayOutputStream()
        for (value in elements) payload.write(valueBytes(field, value))
        writeVarint(output, field.number * 8 + 2)
        writeVarint(output, payload.size().toLong())
        output.write(payload.toByteArray())
    } else {
        for (value in elements) {
            writeVarint(output, field.number * 8 + field.wire)
            val raw = valueBytes(field, value)
            if (field.wire == 2) writeVarint(output, raw.size.toLong())
            output.write(raw)
        }
    }
    return output.toByteArray()
}

private fun encode(message: Message): ByteArray {
    val output = ByteArrayOutputStream()
    for (field in message.type.fields) output.write(encodeField(field, message.elements(field)))
    for (unknown in message.unknown) {
        writeVarint(output, unknown.number * 8 + unknown.wire)
        when (unknown.wire) {
            0 -> writeVarint(output, unknown.rawNumber)
            2 -> {
                writeVarint(output, unknown.rawBytes.size.toLong())
                output.write(unknown.rawBytes)
            }
            else -> output.write(unknown.rawBytes)
        }
    }
    return output.toByteArray()
}

private fun valueNotation(field: Field, value: Value): String = when (value) {
    is IntegerValue -> value.number.toString()
    is BooleanValue -> value.boolean.toString()
    is EnumValue -> value.name
    is DataValue -> if (field.typeName == "string") quote(value.data) else bytesNotation(value.data)
    is NestedValue -> messageNotation(value.message)
}

private fun sequenceNotation(field: Field, elements: List<Value>) =
    elements.joinToString(", ", "[", "]") { valueNotation(field, it) }

private fun messageNotation(message: Message) = message.type.fields.filter { message.has(it) }
    .joinToString(", ", "{", "}") { field ->
        val value = if (field.repeated) sequenceNotation(field, message.elements(field))
            else valueNotation(field, message.elements(field).single())
        "${field.name}: $value"
    }

private fun jsonKey(name: String): String {
    var uppercase = false
    return buildString {
        for (char in name) {
            if (char == '_') uppercase = true else {
                append(if (uppercase && char in 'a'..'z') char.uppercaseChar() else char)
                uppercase = false
            }
        }
    }
}

private fun jsonValue(field: Field, value: Value): String = when (value) {
    is IntegerValue -> if (field.typeName in setOf("uint64", "sint64", "fixed64"))
        "\"${value.number}\"" else value.number.toString()
    is BooleanValue -> value.boolean.toString()
    is EnumValue -> "\"${value.name}\""
    is DataValue -> if (field.typeName == "string") quote(value.data, true)
        else "\"${Base64.getEncoder().encodeToString(value.data)}\""
    is NestedValue -> jsonMessage(value.message)
}

private fun jsonMessage(message: Message) = message.type.fields.filter { message.has(it) }
    .joinToString(",", "{", "}") { field ->
        val value = if (field.repeated) message.elements(field).joinToString(",", "[", "]") {
            jsonValue(field, it)
        } else jsonValue(field, message.elements(field).single())
        "\"${jsonKey(field.name)}\":$value"
    }

private fun textMessage(message: Message): List<String> {
    val lines = mutableListOf("${message.type.name} {")
    fun contents(current: Message, depth: Int) {
        val indent = "  ".repeat(depth)
        for (field in current.type.fields) {
            for (value in current.elements(field)) {
                if (value is NestedValue) {
                    lines.add("$indent${field.name} {")
                    contents(value.message, depth + 1)
                    lines.add("$indent}")
                } else lines.add("$indent${field.name}: ${valueNotation(field, value)}")
            }
        }
        for (unknown in current.unknown) {
            lines.add("$indent${unknown.number}: ${WIRE_NAMES.getValue(unknown.wire)} ${unknown.notation()}")
        }
    }
    contents(message, 1)
    lines.add("}")
    return lines
}

private enum class TokenKind { SYMBOL, INTEGER, NAME, STRING, BYTES, END }

private data class Token(
    val kind: TokenKind,
    val text: String,
    val column: Int,
    val number: Long = 0,
    val data: ByteArray = byteArrayOf()
) {
    fun shape(): String? = when (kind) {
        TokenKind.INTEGER -> "integer"
        TokenKind.NAME -> if (text == "true" || text == "false") "boolean" else "name"
        TokenKind.STRING -> "string"
        TokenKind.BYTES -> "bytes"
        TokenKind.SYMBOL -> when (text) { "{" -> "message"; "[" -> "list"; else -> null }
        TokenKind.END -> null
    }
}

private fun tokenize(text: String): List<Token> {
    val tokens = mutableListOf<Token>()
    var position = 0
    while (position < text.length) {
        val start = position
        val char = text[position]
        when {
            char == ' ' -> position++
            char in "{}[]:," -> {
                tokens.add(Token(TokenKind.SYMBOL, char.toString(), start + 1))
                position++
            }
            char == '"' -> {
                position++
                val bytes = ByteArrayOutputStream()
                var closed = false
                while (position < text.length) {
                    val next = text[position++]
                    if (next == '"') {
                        closed = true
                        break
                    }
                    if (next != '\\') bytes.write(next.code) else {
                        if (position == text.length) columnError("syntax error", start + 1)
                        when (val escape = text[position++]) {
                            '"', '\\' -> bytes.write(escape.code)
                            'n' -> bytes.write(10)
                            't' -> bytes.write(9)
                            'x' -> {
                                if (position + 2 > text.length) columnError("syntax error", start + 1)
                                val digits = text.substring(position, position + 2)
                                if (!isHex(digits) || digits.toInt(16) > 127) columnError("syntax error", start + 1)
                                bytes.write(digits.toInt(16))
                                position += 2
                            }
                            else -> columnError("syntax error", start + 1)
                        }
                    }
                }
                if (!closed) columnError("syntax error", start + 1)
                tokens.add(Token(TokenKind.STRING, "", start + 1, data = bytes.toByteArray()))
            }
            char == '<' -> {
                val end = text.indexOf('>', position + 1)
                if (end < 0) columnError("syntax error", start + 1)
                val digits = text.substring(position + 1, end)
                if (digits.length % 2 != 0 || !isHex(digits)) columnError("syntax error", start + 1)
                tokens.add(Token(TokenKind.BYTES, "", start + 1, data = hexBytes(digits)))
                position = end + 1
            }
            char == '-' || char in '0'..'9' -> {
                if (char == '-') position++
                val digitStart = position
                while (position < text.length && text[position] in '0'..'9') position++
                if (position == digitStart) columnError("syntax error", start + 1)
                val digits = text.substring(start, position)
                tokens.add(Token(TokenKind.INTEGER, digits, start + 1, digits.toLong()))
            }
            isLetter(char) || char == '_' -> {
                position++
                while (position < text.length && (isLetter(text[position]) ||
                        text[position] in '0'..'9' || text[position] == '_')) position++
                tokens.add(Token(TokenKind.NAME, text.substring(start, position), start + 1))
            }
            else -> columnError("syntax error", start + 1)
        }
    }
    tokens.add(Token(TokenKind.END, "", text.length + 1))
    return tokens
}

private class LiteralParser(text: String) {
    private val tokens = tokenize(text)
    private var position = 0
    private val next get() = tokens[position]
    private fun at(symbol: String) = next.kind == TokenKind.SYMBOL && next.text == symbol

    private fun expect(symbol: String) {
        if (!at(symbol)) columnError("syntax error", next.column)
        position++
    }

    fun finish() {
        if (next.kind != TokenKind.END) columnError("syntax error", next.column)
    }

    fun readMessage(type: MessageType): Message {
        expect("{")
        val message = Message(type)
        val seen = mutableSetOf<Long>()
        val groups = mutableSetOf<String>()
        if (!at("}")) {
            while (true) {
                val token = next
                if (token.kind != TokenKind.NAME) columnError("syntax error", token.column)
                val field = type.byName[token.text] ?: columnError("unknown field", token.column)
                if (!seen.add(field.number)) columnError("duplicate field", token.column)
                if (field.group != null && !groups.add(field.group)) columnError("oneof conflict", token.column)
                position++
                expect(":")
                message.setElements(field, readField(field))
                if (at(",")) {
                    position++
                    continue
                }
                if (!at("}")) columnError("syntax error", next.column)
                break
            }
        }
        val closing = next
        expect("}")
        for (field in type.fields) {
            if (field.required && field.number !in seen) {
                columnError("missing required field ${field.name}", closing.column)
            }
        }
        return message
    }

    fun readField(field: Field): List<Value> {
        if (!field.repeated) return listOf(readElement(field))
        val shape = next.shape() ?: columnError("syntax error", next.column)
        if (shape != "list") columnError("type mismatch", next.column)
        expect("[")
        val values = mutableListOf<Value>()
        if (!at("]")) {
            while (true) {
                values.add(readElement(field))
                if (!at(",")) break
                position++
            }
        }
        expect("]")
        return values
    }

    fun readElement(field: Field): Value {
        val token = next
        val shape = token.shape() ?: columnError("syntax error", token.column)
        val expected = when {
            field.typeName in INTEGER_RANGES -> "integer"
            field.typeName == "bool" -> "boolean"
            field.enumType != null -> "name"
            field.messageType != null -> "message"
            else -> field.typeName
        }
        if (shape != expected) columnError("type mismatch", token.column)
        if (field.messageType != null) return NestedValue(readMessage(field.messageType!!))
        position++
        return when (expected) {
            "integer" -> {
                if (token.number !in INTEGER_RANGES.getValue(field.typeName)) columnError("out of range", token.column)
                IntegerValue(token.number)
            }
            "boolean" -> BooleanValue(token.text == "true")
            "name" -> {
                val number = field.enumType!!.byName[token.text] ?: columnError("unknown enum value", token.column)
                EnumValue(token.text, number)
            }
            else -> DataValue(token.data)
        }
    }
}

private data class RawValue(
    val number: Long = 0,
    val bytes: ByteArray = byteArrayOf(),
    val payloadStart: Int = 0
)

private class WireReader(private val data: ByteArray, private val explanation: MutableList<String>? = null) {
    private var position = 0

    private fun readVarint(end: Int): Long {
        val start = position
        var value = 0L
        for (index in 0 until 8) {
            if (position >= end) byteError("truncated varint", start)
            val byte = data[position++].toInt() and 255
            value = value or ((byte and 127).toLong() shl (7 * index))
            if (byte < 128) {
                if (value >= VARINT_LIMIT) byteError("varint too large", start)
                return value
            }
            if (index == 7) byteError("varint too long", start)
        }
        error("unreachable varint state")
    }

    private fun readRaw(wire: Int, end: Int): RawValue {
        val start = position
        if (wire == 0) return RawValue(number = readVarint(end))
        if (wire == 2) {
            val length = readVarint(end)
            val payloadStart = position
            if (length > (end - position).toLong()) byteError("length past end", start)
            position += length.toInt()
            return RawValue(bytes = data.copyOfRange(payloadStart, position), payloadStart = payloadStart)
        }
        val size = if (wire == 5) 4 else 8
        if (end - position < size) byteError(if (wire == 5) "truncated i32" else "truncated i64", start)
        position += size
        return RawValue(bytes = data.copyOfRange(start, position))
    }

    private fun convert(field: Field, raw: RawValue, valuePosition: Int): Value {
        if (field.typeName == "string") {
            for ((index, byte) in raw.bytes.withIndex()) {
                if ((byte.toInt() and 255) >= 128) byteError("invalid string", raw.payloadStart + index)
            }
            return DataValue(raw.bytes)
        }
        if (field.typeName == "bytes") return DataValue(raw.bytes)
        if (field.enumType != null) {
            val name = field.enumType!!.byNumber[raw.number] ?: byteError("unknown enum number", valuePosition)
            return EnumValue(name, raw.number)
        }
        if (field.typeName == "bool") {
            if (raw.number !in 0L..1L) byteError("value out of range", valuePosition)
            return BooleanValue(raw.number == 1L)
        }
        var number = raw.number
        if (field.wire != 0) {
            if (field.typeName == "fixed64" &&
                (raw.bytes[7].toInt() != 0 || (raw.bytes[6].toInt() and 255) >= 32)) {
                byteError("value out of range", valuePosition)
            }
            number = 0
            for ((index, byte) in raw.bytes.withIndex()) {
                number = number or ((byte.toInt() and 255).toLong() shl (8 * index))
            }
        }
        when (field.typeName) {
            "sint32", "sint64" -> number = unzigzag(number)
            "sfixed32" -> if (number >= 2_147_483_648L) number -= 4_294_967_296L
        }
        if (number !in INTEGER_RANGES.getValue(field.typeName)) byteError("value out of range", valuePosition)
        return IntegerValue(number)
    }

    fun readMessage(type: MessageType, end: Int = data.size, depth: Int = 0): Message {
        val message = Message(type)
        while (position < end) {
            val recordStart = position
            val tag = readVarint(end)
            val number = tag / 8
            val wire = (tag % 8).toInt()
            if (number == 0L) byteError("invalid field number", recordStart)
            if (wire !in WIRE_NAMES) byteError("invalid wire type", recordStart)
            val field = type.byNumber[number]
            val packed = field != null && field.repeated && field.packable && wire == 2
            if (field != null && wire != field.wire && !packed) byteError("wire type mismatch", recordStart)
            val valuePosition = position
            val raw = readRaw(wire, end)
            var heading = "${"  ".repeat(depth)}$recordStart $number ${field?.name ?: "?"} ${WIRE_NAMES.getValue(wire)}"
            if (wire == 2) heading += " ${raw.bytes.size}"
            if (field == null) {
                val unknown = UnknownField(number, wire, raw.number, raw.bytes)
                if (explanation == null) message.unknown.add(unknown)
                else explanation.add("$heading ${unknown.notation()}")
                continue
            }
            val values: List<Value>
            if (field.messageType != null) {
                explanation?.add(heading)
                position = raw.payloadStart
                values = listOf(NestedValue(readMessage(field.messageType!!, raw.payloadStart + raw.bytes.size, depth + 1)))
            } else if (packed) {
                position = raw.payloadStart
                val payloadEnd = raw.payloadStart + raw.bytes.size
                val elements = mutableListOf<Value>()
                while (position < payloadEnd) {
                    val elementPosition = position
                    val element = readRaw(field.wire, payloadEnd)
                    elements.add(convert(field, element, elementPosition))
                }
                values = elements
                explanation?.add(heading + " packed" + elements.joinToString("") { " ${valueNotation(field, it)}" })
            } else {
                val value = convert(field, raw, valuePosition)
                values = listOf(value)
                explanation?.add("$heading ${valueNotation(field, value)}")
            }
            if (explanation == null) message.apply(field, values)
        }
        return message
    }
}

private fun decode(type: MessageType, data: ByteArray): Message {
    val message = WireReader(data).readMessage(type)
    checkRequired(message)
    return message
}

private fun explain(type: MessageType, data: ByteArray): List<String> {
    if (data.isEmpty()) return listOf("(empty)")
    val lines = mutableListOf<String>()
    WireReader(data, lines).readMessage(type)
    return lines
}

private data class PathSegment(val field: Field, val index: Int?)

private fun parsePath(type: MessageType, text: String): List<PathSegment> {
    val pattern = Regex("([a-z][a-z0-9_]*)(?:\\[([0-9]{1,6})\\])?")
    val parts = text.split('.')
    val result = mutableListOf<PathSegment>()
    var currentType = type
    for ((position, part) in parts.withIndex()) {
        val match = pattern.matchEntire(part) ?: throw CommandError("invalid path")
        val field = currentType.byName[match.groupValues[1]] ?: throw CommandError("invalid path")
        val index = match.groupValues[2].takeIf { it.isNotEmpty() }?.toInt()
        if (index != null && !field.repeated) throw CommandError("invalid path")
        result.add(PathSegment(field, index))
        if (position != parts.lastIndex) {
            currentType = field.messageType ?: throw CommandError("invalid path")
            if (field.repeated && index == null) throw CommandError("invalid path")
        }
    }
    return result
}

private fun getPath(message: Message, path: List<PathSegment>): String {
    var current: Message? = message
    for ((position, segment) in path.withIndex()) {
        val elements = current?.elements(segment.field) ?: emptyList()
        if (position == path.lastIndex) {
            if (segment.field.repeated && segment.index == null) return sequenceNotation(segment.field, elements)
            val value = elements.getOrNull(segment.index ?: 0) ?: return "(none)"
            return valueNotation(segment.field, value)
        }
        current = (elements.getOrNull(segment.index ?: 0) as? NestedValue)?.message
    }
    error("empty validated path")
}

private fun patchPath(message: Message, path: List<PathSegment>, replacement: List<Value>) {
    var current = message
    for (segment in path.dropLast(1)) {
        val field = segment.field
        if (segment.index != null) {
            val value = current.elements(field).getOrNull(segment.index) ?: throw CommandError("index out of range")
            current = (value as NestedValue).message
        } else {
            if (!current.has(field)) {
                current.clearGroup(field)
                current.setElements(field, listOf(NestedValue(Message(field.messageType!!))))
            }
            current = (current.elements(field).single() as NestedValue).message
        }
    }
    val last = path.last()
    if (last.index != null) {
        val elements = current.values[last.field.number] ?: throw CommandError("index out of range")
        if (last.index >= elements.size) throw CommandError("index out of range")
        elements[last.index] = replacement.single()
    } else {
        current.clearGroup(last.field)
        current.setElements(last.field, replacement)
    }
}

private fun clearPath(message: Message, path: List<PathSegment>) {
    var current = message
    for (segment in path.dropLast(1)) {
        val value = current.elements(segment.field).getOrNull(segment.index ?: 0) ?: return
        current = (value as NestedValue).message
    }
    val last = path.last()
    if (last.index == null) current.values.remove(last.field.number) else {
        val elements = current.values[last.field.number] ?: return
        if (last.index < elements.size) elements.removeAt(last.index)
        if (elements.isEmpty()) current.values.remove(last.field.number)
    }
}

private fun sameValue(first: Value, second: Value) =
    if (first is DataValue && second is DataValue) first.data.contentEquals(second.data) else first == second

private fun differences(first: Message, second: Message): List<String> {
    val lines = mutableListOf<String>()
    fun compare(a: Message, b: Message, prefix: String) {
        for (field in a.type.fields) {
            val x = a.elements(field)
            val y = b.elements(field)
            for (index in 0 until maxOf(x.size, y.size)) {
                val path = prefix + field.name + if (field.repeated) "[$index]" else ""
                val left = x.getOrNull(index)
                val right = y.getOrNull(index)
                if (left is NestedValue && right is NestedValue) compare(left.message, right.message, "$path.")
                else if (left == null || right == null || !sameValue(left, right)) {
                    val before = left?.let { valueNotation(field, it) } ?: "(none)"
                    val after = right?.let { valueNotation(field, it) } ?: "(none)"
                    lines.add("$path: $before -> $after")
                }
            }
        }
    }
    compare(first, second, "")
    return lines.ifEmpty { listOf("SAME") }
}

private fun schemaTree(type: MessageType): List<String> {
    val lines = mutableListOf(type.name)
    fun fields(current: MessageType, chain: Set<MessageType>, depth: Int) {
        for (field in current.fields) {
            var line = "${"  ".repeat(depth)}${field.number} ${field.name}: ${field.kindWord()}${field.typeName}"
            field.enumType?.let { enumType ->
                line += enumType.byNumber.toSortedMap().entries.joinToString(", ", " (", ")") {
                    "${it.value}=${it.key}"
                }
            }
            val nested = field.messageType
            if (nested != null && nested in chain) line += " (recursive)"
            lines.add(line)
            if (nested != null && nested !in chain) fields(nested, chain + nested, depth + 1)
        }
    }
    fields(type, setOf(type), 1)
    return lines
}

private fun parseNumber(text: String, range: LongRange): Long {
    if (!Regex("-?[0-9]{1,18}").matches(text)) throw CommandError("invalid number")
    val number = text.toLong()
    if (number !in range) throw CommandError("invalid number")
    return number
}

private class Commands(private val schema: Schema) {
    private val counts = mapOf(
        "VARINT" to 2, "ZIGZAG" to 2, "SCHEMA" to 2, "ENCODE" to 3, "SIZE" to 3,
        "DECODE" to 3, "LITERAL" to 3, "JSON" to 3, "CANON" to 3, "EXPLAIN" to 3,
        "GET" to 4, "PATCH" to 5, "CLEAR" to 4, "MERGE" to 4, "DIFF" to 4
    )

    fun execute(line: String): List<String> {
        val words = line.split(' ')
        val command = words[0]
        val count = counts[command] ?: throw CommandError("unknown command")
        val hasText = command in setOf("ENCODE", "SIZE", "PATCH")
        if ((hasText && words.size < count) || (!hasText && words.size != count)) {
            throw CommandError("wrong number of arguments")
        }
        if (command == "VARINT") {
            val number = parseNumber(words[1], 0L until VARINT_LIMIT)
            return listOf(hexText(varintBytes(number)))
        }
        if (command == "ZIGZAG") {
            val number = parseNumber(words[1], INTEGER_RANGES.getValue("sint64"))
            val value = zigzag(number)
            return listOf("$value ${hexText(varintBytes(value))}")
        }
        val type = schema.messages[words[1]] ?: throw CommandError("unknown message type")
        val hasHex = command !in setOf("SCHEMA", "ENCODE", "SIZE")
        val first = if (hasHex) parseHex(words[2]) else byteArrayOf()
        val second = if (command == "MERGE" || command == "DIFF") parseHex(words[3]) else byteArrayOf()
        val path = if (command in setOf("GET", "PATCH", "CLEAR")) parsePath(type, words[3]) else emptyList()
        return when (command) {
            "SCHEMA" -> schemaTree(type)
            "ENCODE", "SIZE" -> {
                val parser = LiteralParser(line.split(' ', limit = 3)[2])
                val message = parser.readMessage(type)
                parser.finish()
                if (command == "ENCODE") listOf(hexText(encode(message))) else {
                    val details = type.fields.filter { message.has(it) }.joinToString("") {
                        " ${it.name}=${encodeField(it, message.elements(it)).size}"
                    }
                    listOf("${encode(message).size}$details")
                }
            }
            "EXPLAIN" -> explain(type, first)
            "MERGE" -> textMessage(decode(type, first + second))
            "DIFF" -> {
                val a = try { decode(type, first) } catch (error: CommandError) {
                    throw CommandError("${error.message} in first")
                }
                val b = try { decode(type, second) } catch (error: CommandError) {
                    throw CommandError("${error.message} in second")
                }
                differences(a, b)
            }
            else -> {
                val message = decode(type, first)
                when (command) {
                    "DECODE" -> textMessage(message)
                    "LITERAL" -> listOf(messageNotation(message))
                    "JSON" -> listOf(jsonMessage(message))
                    "CANON" -> listOf(hexText(encode(message)))
                    "GET" -> listOf(getPath(message, path))
                    "PATCH" -> {
                        val parser = LiteralParser(line.split(' ', limit = 5)[4])
                        val last = path.last()
                        val replacement = if (last.field.repeated && last.index == null) parser.readField(last.field)
                            else listOf(parser.readElement(last.field))
                        parser.finish()
                        patchPath(message, path, replacement)
                        checkRequired(message)
                        listOf(hexText(encode(message)))
                    }
                    "CLEAR" -> {
                        clearPath(message, path)
                        checkRequired(message)
                        listOf(hexText(encode(message)))
                    }
                    else -> error("unreachable command")
                }
            }
        }
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val commands = Commands(readSchema(input))
    repeat(input.readLine().toInt()) {
        val result = try {
            commands.execute(input.readLine())
        } catch (error: CommandError) {
            listOf("ERROR ${error.message}")
        }
        for (line in result) {
            output.write(line)
            output.newLine()
        }
    }
    output.flush()
}
