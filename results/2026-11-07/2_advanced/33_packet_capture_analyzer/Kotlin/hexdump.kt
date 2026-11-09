import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import java.util.Locale
object Hexdump {
    fun read(): List<Packet> {
        val lines = Files.readAllLines(Path.of("input/capture.txt"), StandardCharsets.US_ASCII)
        val packets = mutableListOf<Packet>();
        var packet: Packet? = null;
        var bytes = mutableListOf<Int>()
        for (line in 0..lines.size) {
            val text = if (line < lines.size) lines[line] else "PACKET "
            if (text.startsWith("PACKET ")) {
                packet?.let {
                    current ->
                    if (current.reason.isEmpty() && bytes.size != current.length) current.reason = "dump: length mismatch (header ${current.length}, data ${bytes.size})"
                    current.bytes = bytes.toIntArray();
                    packets.add(current)
                }
                if (line == lines.size) break
                val parts = text.split(' ');
                packet = Packet(parts[1].toInt(), parts[2].toLong(), parts[3].toInt());
                bytes = mutableListOf()
            } else if (text.isNotEmpty() && packet!!.reason.isEmpty()) {
                if (!Regex("[0-9a-f]{4}  [0-9a-f]{2}( [0-9a-f]{2}){0,15}").matches(text)) packet.reason = "dump: bad line ${line + 1}"
                else if (text.substring(0,4).toInt(16) != bytes.size) packet.reason = "dump: offset mismatch at line ${line + 1}"
                else text.substring(6).split(' ').forEach {
                    bytes.add(it.toInt(16))
                }
            }
        }
        return packets
    }
    fun lines(bytes: IntArray): List<String> {
        val result = mutableListOf<String>()
        for (start in bytes.indices step 16) {
            val hex = mutableListOf<String>();
            val text = StringBuilder()
            for (i in start until minOf(start + 16, bytes.size)) {
                hex.add(String.format(Locale.ROOT, "%02x", bytes[i]));
                text.append(if (bytes[i] in 32..126) bytes[i].toChar() else '.')
            }
            result.add(String.format(Locale.ROOT, "%04x  %-47s  |%s|", start, hex.joinToString(" "), text))
        }
        return result
    }
}
