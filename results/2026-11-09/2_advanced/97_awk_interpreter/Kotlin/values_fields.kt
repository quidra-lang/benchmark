sealed interface Value {
    data class Number(val value: Int) : Value
    data class Text(val value: String) : Value
    data class Numeric(val value: String, override val number: Int) : Value
    data object Uninitialized : Value
    val number: Int get() = when (this) {
        is Number -> value;
        is Numeric -> number;
        Uninitialized -> 0;
        is Text -> {
            var i = 0;
            while (i < value.length && whitespace(value[i])) i++;
            val negative = value.getOrNull(i) == '-';
            if (value.getOrNull(i) in listOf('+', '-')) i++;
            var n = 0;
            while (i < value.length && Lexer.digit(value[i])) {
                n = n * 10 + (value[i++] - '0')
            };
            if (negative) -n else n
        }
    }
    val text: String get() = when (this) {
        is Number -> value.toString();
        is Text -> value;
        is Numeric -> value;
        Uninitialized -> ""
    }
    val truth: Boolean get() = if (this is Text) value.isNotEmpty() else number != 0
    val numberLike: Boolean get() = this !is Text
    val numericKind: Boolean get() = this is Number || this is Numeric
    fun compare(other: Value): Int = if (numberLike && other.numberLike) number.compareTo(other.number) else text.compareTo(other.text)
    val display: String get() = when (this) {
        is Number -> value.toString();
        is Text -> quote(value);
        is Numeric -> quote(value) + " (strnum)";
        Uninitialized -> "(uninitialized)"
    }
    companion object {
        fun whitespace(c: Char): Boolean = c == ' ' || c.code == 9 || c.code == 10
        fun input(text: String): Value {
            val raw = text.trim(::whitespace);
            val digits = if (raw.firstOrNull() in listOf('+', '-')) raw.drop(1) else raw;
            return if (digits.isNotEmpty() && digits.all(Lexer::digit)) Numeric(text, Text(text).number) else Text(text)
        }
    }
}
fun quote(text: String): String = buildString {
    append(34.toChar());
    for (c in text) {
        when (c.code) {
            34, 92 -> {
                append(92.toChar());
                append(c)
            };
            10 -> {
                append(92.toChar());
                append('n')
            };
            9 -> {
                append(92.toChar());
                append('t')
            };
            in 32..126 -> append(c);
            else -> {
                append(92.toChar());
                append(c.code.toString(8).padStart(3, '0'))
            }
        }
    };
    append(34.toChar())
}
fun splitText(text: String, separator: String): List<String> {
    if (separator == " ") {
        val pieces = mutableListOf<String>();
        var i = 0;
        while (i < text.length) {
            while (i < text.length && Value.whitespace(text[i])) i++;
            val start = i;
            while (i < text.length && !Value.whitespace(text[i])) i++;
            if (i > start) pieces.add(text.substring(start, i))
        };
        return pieces
    }
    if (separator.isEmpty()) return text.map(Char::toString)
    return if (text.isEmpty()) emptyList() else text.split(separator)
}
fun integerKey(text: String): Int? {
    if (text == "0") return 0;
    val digits = if (text.startsWith("-")) text.drop(1) else text;
    val first = digits.firstOrNull() ?: return null;
    if (first !in '1'..'9' || !digits.all(Lexer::digit)) return null;
    return text.toInt()
}
val keyOrder = Comparator<String> {
    a, b -> val x = integerKey(a);
    val y = integerKey(b);
    if (x != null && y != null) x.compareTo(y) else if (x != null) -1 else if (y != null) 1 else a.compareTo(b)
}
class Fields {
    var record: Value = Value.Text("");
    val values = mutableListOf<Value>()
    fun set(text: String, separator: String) {
        record = Value.input(text);
        values.clear();
        values.addAll(splitText(text, separator).map {
            Value.input(it)
        })
    }
    fun get(index: Int): Value = if (index == 0) record else values.getOrNull(index - 1) ?: Value.Uninitialized
    fun rebuild(separator: String) {
        record = Value.input(values.joinToString(separator) {
            it.text
        })
    }
    fun assign(index: Int, value: Value, fs: String, ofs: String) {
        if (index == 0) set(value.text, fs) else {
            while (values.size < index) values.add(Value.Text(""));
            values[index - 1] = value;
            rebuild(ofs)
        }
    }
    fun nf(size: Int, ofs: String) {
        while (values.size > size) values.removeAt(values.lastIndex);
        while (values.size < size) values.add(Value.Text(""));
        rebuild(ofs)
    }
}
