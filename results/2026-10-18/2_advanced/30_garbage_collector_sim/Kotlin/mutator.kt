import java.nio.file.Files
import java.nio.file.Path

data class CollectorEntry(val name: String, val type: String, val young: Int, val age: Int)
class Config {
    var heap = 0;
    var width = 0;
    val collectors = mutableListOf<CollectorEntry>();
    var maps = emptyList<String>();
    val windows = mutableListOf<Int>()
}
class Command(val line: Int, val name: String) {
    var pointers = 0;
    var data = 0;
    var slot = 0;
    var field = 0;
    var count = 0;
    var source = -1;
    var label = ""
}
data class Parsed(val command: Command?, val error: String)
object Mutator {
    val names = listOf("ALLOC", "PUSH", "LOAD", "POP", "SET", "OVERWRITE", "CHECKPOINT")
    fun lines(name: String): List<String> = Files.readAllLines(Path.of("input", name))
    fun config(): Config {
        val config = Config()
        for (line in lines("config.txt")) {
            val fields = line.split(' ')
            when (fields[0]) {
                "HEAP" -> config.heap = fields[1].toInt()
                "COLLECTOR" -> config.collectors.add(CollectorEntry(fields[1], fields[2], if (fields.size > 3) fields[3].toInt() else 0,
                     if (fields.size > 4) fields[4].toInt() else 0))
                "MAPS" -> config.maps = fields.drop(1)
                "MMU" -> config.windows.addAll(fields.drop(1).map(String::toInt))
                else -> config.width = fields[1].toInt()
            }
        }
        return config
    }
    fun parse(line: Int, text: String): Parsed {
        val tokens = text.split(' ')
        val form = when (tokens[0]) {
            "ALLOC", "LOAD" -> "nn";
            "OVERWRITE" -> "nr";
            "PUSH" -> "r";
            "POP" -> "n";
            "SET" -> "nnr";
            "CHECKPOINT" -> "l";
            else -> ""
        }
        if (form.isEmpty() || tokens.size != form.length + 1) return Parsed(null, "syntax")
        for (i in form.indices) {
            val token = tokens[i + 1];
            val kind = form[i]
            if (kind == 'l') {
                if (!token.matches(Regex("[a-z0-9_]{1,16}"))) return Parsed(null, "syntax")
            }
            else if (!(kind == 'r' && token == "-") && !token.matches(Regex("0|[1-9][0-9]{0,3}"))) return Parsed(null, "syntax")
        }
        val command = Command(line, tokens[0])
        when (command.name) {
            "ALLOC" -> {
                command.pointers = tokens[1].toInt();
                command.data = tokens[2].toInt()
            }
            "PUSH" -> command.source = if (tokens[1] == "-") -1 else tokens[1].toInt()
            "POP" -> command.count = tokens[1].toInt()
            "LOAD", "SET" -> {
                command.slot = tokens[1].toInt();
                command.field = tokens[2].toInt();
                if (command.name == "SET") command.source = if (tokens[3] == "-") -1 else tokens[3].toInt()
            }
            "OVERWRITE" -> {
                command.slot = tokens[1].toInt();
                command.source = if (tokens[2] == "-") -1 else tokens[2].toInt()
            }
            else -> command.label = tokens[1]
        }
        if (command.name == "ALLOC" && (command.pointers > 6 || command.data > 24) || command.name == "POP" && command.count == 0) return Parsed(command,
             "range")
        return Parsed(command, "")
    }
}
