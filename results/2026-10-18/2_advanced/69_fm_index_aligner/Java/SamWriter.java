import java.nio.file.*;
import java.util.*;
final class SamWriter {
    static String ratio(long numerator, long denominator) {
        return denominator == 0
            ? "-"
            : String.format(Locale.ROOT, "%.4f", numerator / (double)denominator);
    }
    static List<String> header(List<SequenceIo.Reference> references) {
        List<String> lines = new ArrayList<>();
        lines.add("@HD\tVN:1.6\tSO:unsorted");
        for (SequenceIo.Reference reference : references)
            lines.add("@SQ\tSN:" + reference.name() + "\tLN:" + reference.bases().length());
        lines.add("@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0");
        return lines;
    }
    static String record(Main.Result result, List<SequenceIo.Reference> references, int maximum) {
        SequenceIo.Read read = result.read;
        if (!result.mapped)
            return String.join("\t", read.name(), "4", "*", "0", "0", "*", "*", "0", "0",
                               read.bases(), read.quality(), "YM:Z:" + result.reason);
        Main.Alignment a = result.primary;
        boolean reverse = a.strand == 1;
        List<String> fields = new ArrayList<>(List.of(
            read.name(), reverse ? "16" : "0", references.get(a.reference).name(),
            Integer.toString(a.position + 1), Integer.toString(result.mapq), a.cigar, "*", "0", "0",
            reverse ? SequenceIo.reverseComplement(read.bases()) : read.bases(),
            reverse ? new StringBuilder(read.quality()).reverse().toString() : read.quality(),
            "NM:i:" + a.nm, "MD:Z:" + a.md, "AS:i:" + result.score, "X0:i:" + result.x0,
            "X1:i:" + result.x1, "YM:Z:" + result.method));
        if (!result.others.isEmpty() && result.others.size() <= maximum) {
            StringBuilder alternatives = new StringBuilder("XA:Z:");
            for (Main.Alignment other : result.others)
                alternatives.append(references.get(other.reference).name())
                    .append(",")
                    .append(other.strand == 0 ? "+" : "-")
                    .append(other.position + 1)
                    .append(",")
                    .append(other.cigar)
                    .append(",")
                    .append(other.nm)
                    .append(";");
            fields.add(alternatives.toString());
        }
        return String.join("\t", fields);
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name),
                          String.join("\n", lines) + (lines.isEmpty() ? "" : "\n"));
    }
}
