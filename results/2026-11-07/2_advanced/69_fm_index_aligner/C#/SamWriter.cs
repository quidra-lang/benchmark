using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class SamWriter {
    public static string Ratio(long numerator, long denominator) =>
        denominator == 0
            ? "-"
            : (numerator / (double)denominator).ToString("F4", CultureInfo.InvariantCulture);
    public static List<string> Header(List<SequenceIo.Reference> references) {
        List<string> lines = new() { "@HD\tVN:1.6\tSO:unsorted" };
        foreach (SequenceIo.Reference reference in references)
            lines.Add("@SQ\tSN:" + reference.name + "\tLN:" + reference.bases.Length);
        lines.Add("@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0");
        return lines;
    }
    public static string Record(Program.Result result, List<SequenceIo.Reference> references,
                                int maximum) {
        SequenceIo.Read read = result.read;
        if (!result.mapped)
            return string.Join("\t", read.name, "4", "*", "0", "0", "*", "*", "0", "0", read.bases,
                               read.quality, "YM:Z:" + result.reason);
        Program.Alignment a = result.primary;
        bool reverse = a.strand == 1;
        List<string> fields =
            new() { read.name,
                    reverse ? "16" : "0",
                    references[a.reference].name,
                    (a.position + 1).ToString(CultureInfo.InvariantCulture),
                    result.mapq.ToString(CultureInfo.InvariantCulture),
                    a.cigar,
                    "*",
                    "0",
                    "0",
                    reverse ? SequenceIo.ReverseComplement(read.bases) : read.bases,
                    reverse ? new string(read.quality.Reverse().ToArray()) : read.quality,
                    "NM:i:" + a.nm,
                    "MD:Z:" + a.md,
                    "AS:i:" + result.score,
                    "X0:i:" + result.x0,
                    "X1:i:" + result.x1,
                    "YM:Z:" + result.method };
        if (result.others.Count != 0 && result.others.Count <= maximum) {
            StringBuilder alternatives = new("XA:Z:");
            foreach (Program.Alignment other in result.others)
                alternatives.Append(references[other.reference].name)
                    .Append(",")
                    .Append(other.strand == 0 ? "+" : "-")
                    .Append(other.position + 1)
                    .Append(",")
                    .Append(other.cigar)
                    .Append(",")
                    .Append(other.nm)
                    .Append(";");
            fields.Add(alternatives.ToString());
        }
        return string.Join("\t", fields);
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(Path.Combine("output", name),
                          string.Join("\n", lines) + (lines.Count == 0 ? "" : "\n"));
    }
}
