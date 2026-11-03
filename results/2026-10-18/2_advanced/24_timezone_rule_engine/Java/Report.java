import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

final class Report {
    static String local(long time) {
        int[] parts = DayRules.splitTime(time);
        return String.format(Locale.ROOT, "%04d-%02d-%02dT%02d:%02d:%02d", parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    }
    static String ut(long time) { return local(time) + "Z"; }
    static String offset(long value) {
        long absolute = Math.abs(value);
        String text = String.format(Locale.ROOT, "%s%02d:%02d", value < 0 ? "-" : "+", absolute / 3600, absolute / 60 % 60);
        return absolute % 60 == 0 ? text : text + String.format(Locale.ROOT, ":%02d", absolute % 60);
    }
    static String duration(long value) {
        long absolute = Math.abs(value);
        return String.format(Locale.ROOT, "%s%d:%02d:%02d", value < 0 ? "-" : "", absolute / 3600, absolute / 60 % 60, absolute % 60);
    }
    static String clock(long value) {
        String text = String.format(Locale.ROOT, "%d:%02d", value / 3600, value / 60 % 60);
        return value % 60 == 0 ? text : text + String.format(Locale.ROOT, ":%02d", value % 60);
    }
    static String state(Resolver.Period period) { return offset(period.offset()) + " " + (period.dst() ? "DST" : "STD") + " " + period.abbreviation(); }
    static String change(long time, Resolver.Period before, Resolver.Period after) { return ut(time) + " " + state(before) + " -> " + state(after); }

    static void writeLines(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n", StandardCharsets.US_ASCII);
    }

    static void writeBlocks(String name, List<List<String>> blocks) throws IOException {
        List<String> lines = new ArrayList<>();
        for (List<String> block : blocks) { if (!lines.isEmpty()) lines.add(""); lines.addAll(block); }
        writeLines(name, lines);
    }
}
