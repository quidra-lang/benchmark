using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public sealed class Hexdump {
    public static List<Program.Packet> Read() {
        List<string> lines = File.ReadAllLines(Path.Combine("input/capture.txt"), Encoding.ASCII).ToList();
        List<Program.Packet> packets = new();
        Program.Packet packet = null;
        List<int> bytes = new();
        for (int line = 0; line <= lines.Count; line++) {
            string text = line < lines.Count ? lines[line] : "PACKET ";
            if (text.StartsWith("PACKET ")) {
                if (packet != null) {
                    if (packet.reason == null && bytes.Count != packet.length)
                        packet.reason =
                            "dump: length mismatch (header " + packet.length + ", data " + bytes.Count + ")";
                    packet.bytes = bytes.ToArray();
                    packets.Add(packet);
                }
                if (line == lines.Count)
                    break;
                string[] parts = text.Split(" ");
                packet = new Program.Packet(int.Parse(parts[1]), long.Parse(parts[2]), int.Parse(parts[3]));
                bytes = new();
            } else if (text.Length != 0 && packet.reason == null) {
                if (!Regex.IsMatch(text, "\\A[0-9a-f]{4}  [0-9a-f]{2}( [0-9a-f]{2}){0,15}\\z"))
                    packet.reason = "dump: bad line " + (line + 1);
                else if (System.Convert.ToInt32(text.Substring(0, 4), 16) != bytes.Count)
                    packet.reason = "dump: offset mismatch at line " + (line + 1);
                else
                    foreach (string value in text.Substring(6).Split(" "))
                        bytes.Add(System.Convert.ToInt32(value, 16));
            }
        }
        return packets;
    }
    public static List<string> Lines(int[] bytes) {
        List<string> output = new();
        for (int start = 0; start < bytes.Length; start += 16) {
            List<string> hex = new();
            StringBuilder text = new StringBuilder();
            for (int i = start; i < Math.Min(start + 16, bytes.Length); i++) {
                hex.Add(string.Format(CultureInfo.InvariantCulture, "{0:x2}", bytes[i]));
                text.Append(bytes[i] >= 32 && bytes[i] <= 126 ? (char)bytes[i] : '.');
            }
            output.Add(string.Format(CultureInfo.InvariantCulture, "{0:x4}  {1,-47}  |{2}|", start,
                                     string.Join(" ", hex), text));
        }
        return output;
    }
}
