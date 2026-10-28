import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
final class Hexdump {
    static List<Main.Packet> read() throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input/capture.txt"), StandardCharsets.US_ASCII);
        List<Main.Packet> packets = new ArrayList<>();
        Main.Packet packet = null;
        List<Integer> bytes = new ArrayList<>();
        for (int line = 0; line <= lines.size(); line++) {
            String text = line < lines.size() ? lines.get(line) : "PACKET ";
            if (text.startsWith("PACKET ")) {
                if (packet != null) {
                    if (packet.reason == null && bytes.size() != packet.length)
                        packet.reason =
                            "dump: length mismatch (header " + packet.length + ", data " + bytes.size() + ")";
                    packet.bytes = bytes.stream().mapToInt(Integer::intValue).toArray();
                    packets.add(packet);
                }
                if (line == lines.size())
                    break;
                String[] parts = text.split(" ");
                packet = new Main.Packet(Integer.parseInt(parts[1]), Long.parseLong(parts[2]),
                                         Integer.parseInt(parts[3]));
                bytes = new ArrayList<>();
            } else if (!text.isEmpty() && packet.reason == null) {
                if (!text.matches("[0-9a-f]{4}  [0-9a-f]{2}( [0-9a-f]{2}){0,15}"))
                    packet.reason = "dump: bad line " + (line + 1);
                else if (Integer.parseInt(text.substring(0, 4), 16) != bytes.size())
                    packet.reason = "dump: offset mismatch at line " + (line + 1);
                else
                    for (String value : text.substring(6).split(" "))
                        bytes.add(Integer.parseInt(value, 16));
            }
        }
        return packets;
    }
    static List<String> lines(int[] bytes) {
        List<String> output = new ArrayList<>();
        for (int start = 0; start < bytes.length; start += 16) {
            List<String> hex = new ArrayList<>();
            StringBuilder text = new StringBuilder();
            for (int i = start; i < Math.min(start + 16, bytes.length); i++) {
                hex.add(String.format(Locale.ROOT, "%02x", bytes[i]));
                text.append(bytes[i] >= 32 && bytes[i] <= 126 ? (char)bytes[i] : '.');
            }
            output.add(String.format(Locale.ROOT, "%04x  %-47s  |%s|", start, String.join(" ", hex), text));
        }
        return output;
    }
}
