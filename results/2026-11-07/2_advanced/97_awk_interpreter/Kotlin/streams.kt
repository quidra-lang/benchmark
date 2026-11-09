import java.io.File
sealed interface Operand {
    data class Assignment(val name: String, val value: String) : Operand
    data class Input(val name: String, val index: Int) : Operand
}
data class FileCount(val name: String, var records: Int = 0)
data class Arguments(val options: MutableList<Pair<String, String>> = mutableListOf(), val operands: MutableList<Operand> = mutableListOf(), val files: MutableList<FileCount> = mutableListOf())
fun validFile(text: String): Boolean = text.isNotEmpty() && !text.startsWith(".") && text.all {
    Lexer.letter(it) || Lexer.digit(it) || it in "._-"
}
fun readFile(name: String): List<String>? = if (validFile(name) && File("input/$name").isFile) File("input/$name").readLines() else null
fun arguments(text: String): Arguments {
    val result = Arguments()
    fun assignment(text: String): Pair<String, String>? {
        val i = text.indexOf('=');
        return if (i < 0) null else text.substring(0, i) to text.substring(i + 1)
    }
    fun variable(text: String): Boolean = text.isNotEmpty() && (Lexer.letter(text[0]) || text[0] == '_') && text.all {
        Lexer.letter(it) || Lexer.digit(it) || it == '_'
    }
    for (line in text.lineSequence().filter {
        it.isNotEmpty()
    }) {
        if (line.startsWith("-F ")) result.options.add("FS" to line.drop(3))
        else if (line.startsWith("-v ")) result.options.add(assignment(line.drop(3))!!)
        else {
            val pair = assignment(line);
            if (pair != null && variable(pair.first)) result.operands.add(Operand.Assignment(pair.first, pair.second)) else {
                result.operands.add(Operand.Input(line, result.files.size));
                result.files.add(FileCount(line))
            }
        }
    }
    return result
}
class OutputStream(val name: String) {
    var text = "";
    var writes = 0;
    var open = false
}
class InputStream(val name: String) {
    var lines: List<String>? = null;
    var position = 0;
    var reads = 0;
    var opened = false;
    var open = false
}
class Streams {
    var stdout = "";
    var writes = 0;
    val outputs = mutableListOf<OutputStream>();
    val inputs = mutableListOf<InputStream>()
    fun output(name: String?, append: Boolean, text: String) {
        if (name == null) {
            stdout += text;
            writes++;
            return
        }
        val output = outputs.firstOrNull {
            it.name == name
        } ?: OutputStream(name).also {
            outputs.add(it)
        }
        if (!output.open) {
            output.open = true;
            if (!append) output.text = ""
        };
        output.text += text;
        output.writes++
    }
    fun getline(name: String): Pair<Int, String?> {
        val input = inputs.firstOrNull {
            it.name == name
        } ?: InputStream(name).also {
            inputs.add(it)
        }
        if (!input.open) {
            input.lines = readFile(name);
            input.position = 0;
            if (input.lines != null) {
                input.open = true;
                input.opened = true
            }
        }
        val lines = input.lines ?: return -1 to null
        if (input.position == lines.size) return 0 to null
        val line = lines[input.position++];
        input.reads++;
        return 1 to line
    }
    fun close(name: String): Int {
        var closed = false;
        outputs.firstOrNull {
            it.name == name
        }?.let {
            closed = closed || it.open;
            it.open = false
        };
        inputs.firstOrNull {
            it.name == name
        }?.let {
            closed = closed || it.open;
            it.open = false
        };
        return if (closed) 0 else -1
    }
    fun save() {
        File("output").mkdirs();
        File("output/stdout.txt").writeText(stdout);
        for (output in outputs) File("output/" + output.name).writeText(output.text)
    }
}
