class RuntimeError(val position: Position, val reason: String) : Exception(reason)
object Builtins {
    fun format(values: List<Value>, position: Position): String {
        val format = values[0].text;
        val output = StringBuilder();
        var i = 0;
        var argument = 1
        fun error(message: String): RuntimeError = RuntimeError(position, message)
        while (i < format.length) {
            if (format[i] != '%') {
                output.append(format[i++]);
                continue
            };
            i++
            if (format.getOrNull(i) == '%') {
                output.append('%');
                i++;
                continue
            }
            var left = false;
            var zero = false
            while (format.getOrNull(i) in listOf('-', '0')) {
                left = left || format[i] == '-';
                zero = zero || format[i] == '0';
                i++
            }
            val start = i;
            while (i < format.length && Lexer.digit(format[i])) i++;
            val width = format.substring(start, i).toIntOrNull() ?: 0
            var precision: Int? = null
            if (format.getOrNull(i) == '.') {
                i++;
                val begin = i;
                while (i < format.length && Lexer.digit(format[i])) i++;
                precision = format.substring(begin, i).toIntOrNull() ?: 0
            }
            if (i == format.length || format[i] !in "discxo") throw error("invalid format")
            val conversion = format[i++];
            if (argument == values.size) throw error("not enough arguments");
            val value = values[argument++];
            val numeric = conversion in "dixo"
            var body: String
            if (numeric) {
                val n = value.number;
                var digits = kotlin.math.abs(n).toString(if (conversion == 'x') 16 else if (conversion == 'o') 8 else 10);
                if (precision != null) digits = if (precision == 0 && n == 0) "" else digits.padStart(precision, '0');
                body = (if (n < 0) "-" else "") + digits
            }
            else if (conversion == 's') body = if (precision == null) value.text else value.text.take(precision)
            else if (value.numericKind) {
                val code = value.number;
                if (code != 10 && code !in 32..126) throw error("invalid character code");
                body = code.toChar().toString()
            }
            else body = value.text.take(1)
            if (body.length < width) {
                val padding = width - body.length;
                body = if (left) body + " ".repeat(padding) else if (numeric && zero && precision == null) {
                    if (body.startsWith("-")) "-" + "0".repeat(padding) + body.drop(1) else "0".repeat(padding) + body
                } else " ".repeat(padding) + body
            }
            output.append(body)
        }
        return output.toString()
    }
    fun scalar(name: String, values: List<Value>, position: Position): Value = when (name) {
        "substr" -> {
            val text = values[0].text;
            val original = values[1].number;
            val start = maxOf(1, original);
            val end = minOf(text.length + 1, if (values.size == 3) original + values[2].number else text.length + 1);
            Value.Text(if (end > start) text.substring(start - 1, end - 1) else "")
        }
        "index" -> {
            val text = values[0].text;
            val target = values[1].text;
            Value.Number(if (target.isEmpty()) 0 else text.indexOf(target) + 1)
        }
        "toupper" -> Value.Text(values[0].text.map {
            if (it in 'a'..'z') (it.code - 32).toChar() else it
        }.joinToString(""))
        "tolower" -> Value.Text(values[0].text.map {
            if (it in 'A'..'Z') (it.code + 32).toChar() else it
        }.joinToString(""))
        "int" -> Value.Number(values[0].number)
        else -> Value.Text(format(values, position))
    }
}
