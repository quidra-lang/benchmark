using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Program {
    public static List<SequenceIo.Reference> references;
    public static Dictionary<string, int[]> parameters;
    public static string text, reverseText;
    public static int[] offsets;
    public static FmIndex forward, reverse;
    public static int[] searchCounts = new int[4], seedCounts = new int[7];
    public static readonly int NEG = -1000000;
    public record Position(int reference, int offset) {}
    public record Pair(int readOffset, int offset) {}
    public record Run(char operation, int count) {}
    public record Hit(int mismatches, int reference, int position, int strand) {}
    public record Candidate(int strand, int reference, int center) {}
    public record Key(int reference, int position, int strand) {}
    public record Banded(int score, int position, string operations) {}
    public record Scored(int score, Alignment alignment) {}
    public sealed class Alignment {
        public int reference, position, strand, nm;
        public string operations, oriented, cigar, md;
        public List<Pair> pairs = new();
    }
    public sealed class Result {
        public SequenceIo.Read read;
        public int[] qualities;
        public int length, trimmed, mapq, score, x0, x1;
        public string core, reason = "SHORT", method;
        public bool mapped;
        public Alignment primary;
        public List<Alignment> others = new();
        public List<int> targets = new();
    }
    public static int Value(string key) { return parameters[key][0]; }
    public static string Ratio(long a, long b) { return SamWriter.Ratio(a, b); }
    public static string Yes(bool value) { return value ? "yes" : "no"; }
    public static int Sum(int[] values) {
        int sum = 0;
        foreach (int value in values)
            sum += value;
        return sum;
    }
    public static void Text() {
        offsets = new int[references.Count];
        List<string> parts = new();
        int offset = 0;
        for (int r = 0; r < references.Count; r++) {
            offsets[r] = offset;
            string bases = references[r].bases;
            offset += bases.Length + 1;
            parts.Add(bases);
        }
        text = string.Join("#", parts) + "$";
        reverseText = new string(text[..^ 1].Reverse().ToArray()) + "$";
    }
    public static Position LocateTextPosition(int p) {
        for (int r = references.Count - 1; r >= 0; r--)
            if (p >= offsets[r])
                return p < offsets[r] + references[r].bases.Length ? new Position(r, p - offsets[r])
                                                                   : null;
        return null;
    }
    public static string Label(int p) {
        Position located = LocateTextPosition(p);
        return located == null ? "*"
                               : references[located.reference].name + ":" + (located.offset + 1);
    }
    public static Position Locate(int row) {
        return LocateTextPosition(forward.Locate(row).position);
    }
    public static List<Run> Runs(string operations) {
        List<Run> runs = new();
        for (int i = 0; i < operations.Length;) {
            int j = i + 1;
            while (j < operations.Length && operations[j] == operations[i])
                j++;
            runs.Add(new Run(operations[i], j - i));
            i = j;
        }
        return runs;
    }
    public static Alignment Describe(int reference, int position, int strand, string operations,
                                     Result result) {
        Alignment a = new Alignment();
        a.reference = reference;
        a.position = position;
        a.strand = strand;
        a.operations = operations;
        a.oriented = strand == 0 ? result.core : SequenceIo.ReverseComplement(result.core);
        string sequence = references[reference].bases;
        StringBuilder cigar = new StringBuilder(), md = new StringBuilder();
        int i = 0, j = position, matches = 0;
        foreach (Run run in Runs(operations)) {
            char operation = run.operation;
            int count = run.count;
            cigar.Append(count).Append(operation);
            if (operation == 'I') {
                i += count;
                a.nm += count;
            } else if (operation == 'D') {
                md.Append(matches).Append('^').Append(sequence.Substring(j, j + count - (j)));
                matches = 0;
                j += count;
                a.nm += count;
            } else
                for (int n = 0; n < count; n++) {
                    a.pairs.Add(new Pair(i, j));
                    if (a.oriented[i] == sequence[j])
                        matches++;
                    else {
                        md.Append(matches).Append(sequence[j]);
                        matches = 0;
                        a.nm++;
                    }
                    i++;
                    j++;
                }
        }
        md.Append(matches);
        if (result.trimmed > 0) {
            string soft = result.trimmed + "S";
            if (strand == 0)
                cigar.Append(soft);
            else
                cigar.Insert(0, soft);
        }
        a.cigar = cigar.ToString();
        a.md = md.ToString();
        return a;
    }
    public static int Cell(int[][] values, int[] first, int i, int j) {
        if (i < 0 || i >= values.Length)
            return NEG;
        int k = j - first[i];
        return k < 0 || k >= values[i].Length ? NEG : values[i][k];
    }
    public static int Subtract(int value, int penalty) {
        return value == NEG ? NEG : value - penalty;
    }
    public static Banded AlignBanded(string oriented, string sequence, int center) {
        int l = oriented.Length, m = sequence.Length, width = Value("BAND_WIDTH");
        int[] scores = parameters["SCORES"], first = new int[l + 1];
        int[][] h = new int [l + 1][], e = new int [l + 1][], f = new int [l + 1][];
        for (int i = 0; i <= l; i++) {
            first[i] = Math.Max(0, i + center - width);
            int last = Math.Min(m, i + center + width), size = Math.Max(0, last - first[i] + 1);
            h[i] = new int[size];
            e[i] = new int[size];
            f[i] = new int[size];
            Array.Fill(h[i], i == 0 ? 0 : NEG);
            Array.Fill(e[i], NEG);
            Array.Fill(f[i], NEG);
        }
        for (int i = 1; i <= l; i++)
            for (int k = 0; k < h[i].Length; k++) {
                int j = first[i] + k;
                f[i][k] = Math.Max(Subtract(Cell(h, first, i - 1, j), scores[2] + scores[3]),
                                   Subtract(Cell(f, first, i - 1, j), scores[3]));
                if (j >= 1)
                    e[i][k] = Math.Max(Subtract(Cell(h, first, i, j - 1), scores[2] + scores[3]),
                                       Subtract(Cell(e, first, i, j - 1), scores[3]));
                int diagonal = NEG;
                if (j >= 1) {
                    int previous = Cell(h, first, i - 1, j - 1);
                    if (previous != NEG)
                        diagonal = previous +
                                   (oriented[i - 1] == sequence[j - 1] ? scores[0] : -scores[1]);
                }
                h[i][k] = Math.Max(diagonal, Math.Max(e[i][k], f[i][k]));
            }
        int best = NEG, end = -1;
        for (int k = 0; k < h[l].Length; k++)
            if (h[l][k] > best) {
                best = h[l][k];
                end = first[l] + k;
            }
        if (end < 0)
            return null;
        int traceRow = l, traceColumn = end;
        char state = 'H';
        StringBuilder backward = new StringBuilder();
        while (true) {
            if (state == 'H') {
                if (traceRow == 0)
                    break;
                int previous =
                    traceColumn >= 1 ? Cell(h, first, traceRow - 1, traceColumn - 1) : NEG;
                if (previous != NEG &&
                    Cell(h, first, traceRow, traceColumn) ==
                        previous + (oriented[traceRow - 1] == sequence[traceColumn - 1]
                                        ? scores[0]
                                        : -scores[1])) {
                    backward.Append('M');
                    traceRow--;
                    traceColumn--;
                    continue;
                }
                state = Cell(f, first, traceRow, traceColumn) != NEG &&
                                Cell(h, first, traceRow, traceColumn) ==
                                    Cell(f, first, traceRow, traceColumn)
                            ? 'I'
                            : 'D';
            } else if (state == 'I') {
                backward.Append('I');
                int previous = Cell(f, first, traceRow - 1, traceColumn);
                state =
                    previous != NEG && Cell(f, first, traceRow, traceColumn) == previous - scores[3]
                        ? 'I'
                        : 'H';
                traceRow--;
            } else {
                backward.Append('D');
                int previous = Cell(e, first, traceRow, traceColumn - 1);
                state =
                    previous != NEG && Cell(e, first, traceRow, traceColumn) == previous - scores[3]
                        ? 'D'
                        : 'H';
                traceColumn--;
            }
        }
        return new Banded(best, traceColumn, new string(backward.ToString().Reverse().ToArray()));
    }
    public static int ComparePosition(Alignment a, Alignment b) {
        int c = (a.reference).CompareTo(b.reference);
        if (c == 0)
            c = (a.position).CompareTo(b.position);
        return c != 0 ? c : (a.strand).CompareTo(b.strand);
    }
    public static Result Map(SequenceIo.Read read) {
        Result result = new Result();
        result.read = read;
        result.qualities = new int[read.quality.Length];
        for (int i = 0; i < result.qualities.Length; i++)
            result.qualities[i] = read.quality[i] - 33;
        int length = read.bases.Length;
        while (length > 0 && result.qualities[length - 1] < Value("TRIM_QUALITY"))
            length--;
        result.length = length;
        result.trimmed = read.bases.Length - length;
        result.core = read.bases.Substring(0, length - (0));
        if (length < Value("MIN_READ_LENGTH"))
            return result;
        string[] oriented = { result.core, SequenceIo.ReverseComplement(result.core) };
        FmIndex.Interval exactForward = forward.Backward(oriented[0]),
                         exactReverse = forward.Backward(oriented[1]);
        int maximum = exactForward.Empty() && exactReverse.Empty() ? Value("MAX_MISMATCHES") : 1;
        List<Hit> hits = new();
        for (int strand = 0; strand < 2; strand++) {
            Search.Result search = Search.Backtrack(oriented[strand], maximum, forward, reverse);
            searchCounts[0]++;
            searchCounts[1] += search.nodes;
            searchCounts[2] += search.leaves.Count;
            searchCounts[3] += search.positions;
            foreach (Search.Leaf leaf in search.leaves)
                for (int row = leaf.lower; row < leaf.upper; row++) {
                    Position position = Locate(row);
                    hits.Add(new Hit(leaf.mismatches, position.reference, position.offset, strand));
                }
        }
        if (hits.Count == 0)
            Seed(result, oriented);
        else
            Finish(result, hits);
        return result;
    }
    public static void Finish(Result result, List<Hit> hits) {
        hits.Sort((a, b) => {
            int c = a.mismatches.CompareTo(b.mismatches);
            if (c == 0)
                c = a.reference.CompareTo(b.reference);
            if (c == 0)
                c = a.position.CompareTo(b.position);
            return c != 0 ? c : a.strand.CompareTo(b.strand);
        });
        int best = hits[0].mismatches, n1 = 0, n2 = 0;
        List<Alignment> alignments = new();
        SortedSet<int> targets = new();
        foreach (Hit hit in hits) {
            if (hit.mismatches == best) {
                n1++;
                targets.Add(hit.reference);
            }
            if (hit.mismatches == best + 1)
                n2++;
            if (hit.mismatches <= best + 1)
                alignments.Add(Describe(hit.reference, hit.position, hit.strand,
                                        new string('M', result.length), result));
        }
        result.mapped = true;
        result.primary = alignments[0];
        result.others = new(alignments.GetRange(1, alignments.Count - 1));
        result.targets = new(targets);
        result.method = best == 0 ? "EXACT" : "MISMATCH";
        int[] scores = parameters["SCORES"];
        result.score = (result.length - best) * scores[0] - best * scores[1];
        result.x0 = n1;
        result.x1 = n2;
        result.mapq = n1 >= 2 ? 0 : n2 == 0 ? 60 - 12 * best : Math.Max(30 - 12 * best - 3 * n2, 1);
    }
    public static List<Candidate> Candidates(string[] oriented) {
        HashSet<Candidate> candidates = new();
        int seedLength = Value("SEED_LENGTH");
        for (int strand = 0; strand < 2; strand++)
            for (int offset = 0; offset + seedLength <= oriented[strand].Length;
                 offset += Value("SEED_STEP")) {
                seedCounts[1]++;
                string seed = oriented[strand].Substring(offset, offset + seedLength - (offset));
                if (seed.IndexOf('N') >= 0) {
                    seedCounts[2]++;
                    continue;
                }
                FmIndex.Interval interval = forward.Backward(seed);
                if (interval.upper - interval.lower > Value("MAX_SEED_HITS"))
                    seedCounts[3]++;
                else if (interval.Empty())
                    seedCounts[4]++;
                else
                    for (int row = interval.lower; row < interval.upper; row++) {
                        Position position = Locate(row);
                        candidates.Add(
                            new Candidate(strand, position.reference, position.offset - offset));
                    }
            }
        seedCounts[5] += candidates.Count;
        List<Candidate> ordered = new(candidates);
        ordered.Sort((a, b) => {
            int c = a.strand.CompareTo(b.strand);
            if (c == 0)
                c = a.reference.CompareTo(b.reference);
            return c != 0 ? c : a.center.CompareTo(b.center);
        });
        return ordered;
    }
    public static void Seed(Result result, string[] oriented) {
        result.reason = "NOHIT";
        if (result.length < Value("SEED_LENGTH"))
            return;
        seedCounts[0]++;
        Dictionary<Key, Scored> accepted = new();
        int threshold = Value("MIN_SCORE_PERCENT") * parameters["SCORES"][0] * result.length;
        foreach (Candidate candidate in Candidates(oriented)) {
            Banded alignment = AlignBanded(oriented[candidate.strand],
                                           references[candidate.reference].bases, candidate.center);
            if (alignment == null || 100 * alignment.score < threshold)
                continue;
            Key key = new Key(candidate.reference, alignment.position, candidate.strand);
            Scored old = accepted.GetValueOrDefault(key);
            if (old == null || alignment.score > old.score)
                accepted[key] = new Scored(
                    alignment.score, Describe(candidate.reference, alignment.position,
                                              candidate.strand, alignment.operations, result));
        }
        seedCounts[6] += accepted.Count;
        if (accepted.Count == 0)
            return;
        List<Scored> ordered = new(accepted.Values);
        ordered.Sort((a, b) => {
            int c = (b.score).CompareTo(a.score);
            return c != 0 ? c : ComparePosition(a.alignment, b.alignment);
        });
        int best = ordered[0].score, n1 = 0, second = 0;
        SortedSet<int> targets = new();
        List<Alignment> alignments = new();
        foreach (Scored alignment in ordered) {
            alignments.Add(alignment.alignment);
            if (alignment.score == best) {
                n1++;
                targets.Add(alignment.alignment.reference);
            } else
                second = Math.Max(second, alignment.score);
        }
        result.mapped = true;
        result.primary = alignments[0];
        result.others = new(alignments.GetRange(1, alignments.Count - 1));
        result.targets = new(targets);
        result.method = "SEED";
        result.score = best;
        result.x0 = n1;
        result.x1 = ordered.Count - n1;
        result.mapq = n1 >= 2 ? 0 : 60 * (best - second) / best;
    }
    public static List<string> IndexStatistics(SuffixArray.Built built,
                                               SuffixArray.Built reversed) {
        int size = text.Length;
        List<string> lines = new();
        lines.Add("text length " + size + " sequences " + references.Count);
        for (int r = 0; r < references.Count; r++) {
            SequenceIo.Reference reference = references[r];
            int gc = 0;
            foreach (char baseChar in reference.bases.ToCharArray())
                if (baseChar == 'G' || baseChar == 'C')
                    gc++;
            lines.Add("sequence " + reference.name + " length " + reference.bases.Length +
                      " offset " + offsets[r] + " gc " + Ratio(gc, reference.bases.Length) +
                      " masked " + reference.masked);
        }
        int[] frequencies = new int[6];
        foreach (char symbol in text.ToCharArray())
            frequencies[SuffixArray.SYMBOLS.IndexOf(symbol)]++;
        string symbols = "symbols";
        for (int i = 0; i < 6; i++)
            symbols += " " + SuffixArray.SYMBOLS[i] + " " + frequencies[i];
        lines.Add(symbols);
        lines.Add("");
        lines.Add("forward_index");
        lines.Add("suffix_array rounds " + (built.classes.Count - 1));
        for (int t = 0; t < built.classes.Count; t++)
            lines.Add("round " + t + " prefix_length " + (1 << t) + " classes " + built.classes[t]);
        SuffixArray.CheckResult check = SuffixArray.Check(text, built.suffixes);
        lines.Add("sa_check pairs " + (size - 1) + " ordered " + check.ordered + " lcp_sum " +
                  check.lcpSum + " mean_lcp " + Ratio(check.lcpSum, size - 1) + " max_lcp " +
                  check.maximum);
        lines.Add("longest_repeat " + check.maximum + " " + Label(built.suffixes[check.row - 1]) +
                  " " + Label(built.suffixes[check.row]));
        int length = Value("SEED_LENGTH");
        Dictionary<string, int> kmers = new();
        foreach (SequenceIo.Reference reference in references)
            for (int i = 0; i + length <= reference.bases.Length; i++)
                kmers.AddCount(reference.bases.Substring(i, i + length - (i)), 1);
        int occurrences = 0, unique = 0, maximum = 0;
        foreach (int count in kmers.Values) {
            occurrences += count;
            if (count == 1)
                unique++;
            maximum = Math.Max(maximum, count);
        }
        lines.Add("kmers length " + length + " occurrences " + occurrences + " distinct " +
                  kmers.Count + " unique " + unique + " max_occurrence " + maximum +
                  " unique_fraction " + Ratio(unique, occurrences));
        lines.Add("bwt runs " + Runs(forward.bwt).Count + " head " +
                  forward.bwt.Substring(0, Math.Min(60, size) - (0)));
        string c = "c_array";
        for (int i = 0; i < 6; i++)
            c += " " + SuffixArray.SYMBOLS[i] + " " + forward.c[i];
        lines.Add(c);
        lines.Add("occ interval " + forward.interval + " checkpoints " +
                  forward.checkpoints.Length);
        lines.Add("sa_sample interval " + Value("SA_SAMPLE_INTERVAL") + " samples " +
                  forward.sampleCount);
        int correct = 0, totalSteps = 0, maxSteps = 0;
        for (int row = 0; row < size; row++) {
            FmIndex.Location location = forward.Locate(row);
            if (location.position == built.suffixes[row])
                correct++;
            totalSteps += location.steps;
            maxSteps = Math.Max(maxSteps, location.steps);
        }
        lines.Add("locate rows " + size + " correct " + correct + " total_steps " + totalSteps +
                  " max_steps " + maxSteps + " mean_steps " + Ratio(totalSteps, size));
        lines.Add("inverse_bwt identical " + Yes(forward.Inverse().Equals(text)));
        lines.Add("");
        lines.Add("reverse_index");
        lines.Add("suffix_array rounds " + (reversed.classes.Count - 1));
        lines.Add("sa_check pairs " + (size - 1) + " ordered " +
                  SuffixArray.Check(reverseText, reversed.suffixes).ordered);
        lines.Add("bwt runs " + Runs(reverse.bwt).Count + " head " +
                  reverse.bwt.Substring(0, Math.Min(60, size) - (0)));
        lines.Add("inverse_bwt identical " + Yes(reverse.Inverse().Equals(reverseText)));
        lines.Add("");
        lines.Add("direct_sort");
        int cross = 0;
        foreach (SequenceIo.Reference reference in references)
            if (reference.bases.Length <= Value("DIRECT_SORT_LIMIT")) {
                string sequence = reference.bases + "$";
                SuffixArray.Built doubled = SuffixArray.Build(sequence);
                lines.Add(reference.name + " length " + sequence.Length + " rounds " +
                          (doubled.classes.Count - 1) + " identical " +
                          Yes(doubled.suffixes.SequenceEqual(SuffixArray.Direct(sequence))));
                cross++;
            }
        if (cross == 0)
            lines.Add("none");
        int occurrenceBytes = 24 * forward.checkpoints.Length,
            sampleBytes = 4 * forward.sampleCount, bitmapBytes = (size + 7) / 8,
            totalBytes = size + occurrenceBytes + sampleBytes + bitmapBytes;
        lines.Add("");
        lines.Add("index_size bwt_bytes " + size + " occ_bytes " + occurrenceBytes +
                  " sample_bytes " + sampleBytes + " bitmap_bytes " + bitmapBytes +
                  " total_bytes " + totalBytes + " full_bytes " + (5 * size) + " ratio " +
                  Ratio(totalBytes, 5 * size));
        return lines;
    }
    public record Coverage(List<string> coverage, List<string> variants) {}
    public static Coverage BuildCoverage(List<Result> results) {
        int[][] depths = new int [references.Count][], starts = new int [references.Count][];
        int[][][][] pileups = new int [references.Count][][][];
        for (int r = 0; r < references.Count; r++) {
            int length = references[r].bases.Length;
            depths[r] = new int[length];
            starts[r] = new int[length];
            pileups[r] = Enumerable.Range(0, length)
                             .Select(
                                 _ => Enumerable.Range(0, 4)
                                          .Select(
                                              _ => new int[2])
                                          .ToArray())
                             .ToArray();
        }
        int[] variant = parameters["VARIANTS"];
        int minMapq = Value("COVERAGE_MIN_MAPQ");
        foreach (Result result in results) {
            if (!result.mapped)
                continue;
            Alignment a = result.primary;
            int r = a.reference;
            if (result.mapq == 0)
                starts[r][a.position]++;
            if (result.mapq < minMapq)
                continue;
            foreach (Pair pair in a.pairs) {
                depths[r][pair.offset]++;
                char baseChar = a.oriented[pair.readOffset];
                int cycle = a.strand == 0 ? pair.readOffset + 1 : result.length - pair.readOffset;
                if (baseChar != 'N' && result.qualities[cycle - 1] >= variant[1])
                    pileups[r][pair.offset][SuffixArray.BASES.IndexOf(baseChar)][a.strand]++;
            }
        }
        int window = Value("COVERAGE_WINDOW");
        List<string> coverage = new(), variants = new();
        coverage.Add("window " + window + " min_mapq " + minMapq);
        variants.Add("min_depth " + variant[0] + " min_base_quality " + variant[1] +
                     " min_alt_percent " + variant[2] + " hom_percent " + variant[3]);
        int callable = 0, variantCount = 0, heterozygous = 0, homozygous = 0;
        for (int r = 0; r < references.Count; r++) {
            SequenceIo.Reference reference = references[r];
            int length = reference.bases.Length, covered = 0, total = 0, maximum = 0;
            foreach (int d in depths[r]) {
                if (d > 0)
                    covered++;
                total += d;
                maximum = Math.Max(maximum, d);
            }
            int[] histogram = new int[maximum + 1];
            foreach (int d in depths[r])
                histogram[d]++;
            coverage.Add("reference " + reference.name + " length " + length + " covered " +
                         covered + " breadth " + Ratio(covered, length) + " mean_depth " +
                         Ratio(total, length) + " max_depth " + maximum);
            string line = "depth_histogram";
            for (int d = 0; d <= maximum; d++)
                line += " " + d + ":" + histogram[d];
            coverage.Add(line);
            for (int first = 0; first < length; first += window) {
                int last = Math.Min(first + window, length), size = last - first, gc = 0, sum = 0,
                    max = 0, zero = 0, mapq0 = 0;
                for (int j = first; j < last; j++) {
                    char baseChar = reference.bases[j];
                    if (baseChar == 'G' || baseChar == 'C')
                        gc++;
                    sum += depths[r][j];
                    max = Math.Max(max, depths[r][j]);
                    if (depths[r][j] == 0)
                        zero++;
                    mapq0 += starts[r][j];
                }
                coverage.Add(reference.name + " " + (first + 1) + " " + last + " gc " +
                             Ratio(gc, size) + " sum " + sum + " mean " + Ratio(sum, size) +
                             " max " + max + " zero " + zero + " mapq0 " + mapq0 + " |" +
                             new string('#', 10 * sum / size));
            }
            for (int j = 0; j < length; j++) {
                int[] counts = new int[4];
                for (int b = 0; b < 4; b++)
                    counts[b] = Sum(pileups[r][j][b]);
                int depth = Sum(counts);
                if (depth < variant[0])
                    continue;
                callable++;
                char referenceBase = reference.bases[j];
                int alternative = -1;
                for (int b = 0; b < 4; b++)
                    if (SuffixArray.BASES[b] != referenceBase &&
                        (alternative < 0 || counts[b] > counts[alternative]))
                        alternative = b;
                int count = counts[alternative];
                if (count < 2 || 100 * count < variant[2] * depth)
                    continue;
                bool hom = 100 * count >= variant[3] * depth;
                if (hom)
                    homozygous++;
                else
                    heterozygous++;
                variantCount++;
                string countsText = "";
                for (int b = 0; b < 4; b++)
                    countsText += (b == 0 ? "" : " ") + counts[b];
                variants.Add(reference.name + " " + (j + 1) + " " + referenceBase + ">" +
                             SuffixArray.BASES[alternative] + " depth " + depth + " alt " + count +
                             " fraction " + Ratio(count, depth) + " genotype " +
                             (hom ? "1/1" : "0/1") + " strands " + pileups[r][j][alternative][0] +
                             " " + pileups[r][j][alternative][1] + " counts " + countsText);
            }
        }
        variants.Add("callable " + callable + " variants " + variantCount + " heterozygous " +
                     heterozygous + " homozygous " + homozygous);
        return new Coverage(coverage, variants);
    }
    public static List<string> ErrorStatistics(List<Result> results) {
        int maxCycle = 0;
        foreach (Result result in results)
            maxCycle = Math.Max(maxCycle, result.read.bases.Length);
        int[][] cycles = Enumerable.Range(0, maxCycle + 1)
                             .Select(
                                 _ => new int[2])
                             .ToArray(),
                substitutions = Enumerable.Range(0, 4)
                                    .Select(
                                        _ => new int[5])
                                    .ToArray(),
                bins = Enumerable.Range(0, 5)
                           .Select(
                               _ => new int[2])
                           .ToArray();
        int[] qualityCounts = new int[2], qualitySums = new int[2], operationCounts = new int[4],
              events = new int[2], indelBases = new int[2];
        foreach (Result result in results) {
            if (!result.mapped)
                continue;
            Alignment a = result.primary;
            foreach (char operation in a.operations.ToCharArray())
                operationCounts["MIDS".IndexOf(operation)]++;
            operationCounts[3] += result.trimmed;
            if (result.x0 != 1)
                continue;
            string sequence = references[a.reference].bases;
            foreach (Pair pair in a.pairs) {
                char observed = a.oriented[pair.readOffset], reference = sequence[pair.offset];
                int mismatch = observed == reference ? 0 : 1,
                    cycle = a.strand == 0 ? pair.readOffset + 1 : result.length - pair.readOffset,
                    quality = result.qualities[cycle - 1];
                cycles[cycle][0]++;
                cycles[cycle][1] += mismatch;
                substitutions[SuffixArray.BASES.IndexOf(reference)]["ACGTN".IndexOf(observed)]++;
                qualityCounts[mismatch]++;
                qualitySums[mismatch] += quality;
                int bin = Math.Min(quality / 10, 4);
                bins[bin][0]++;
                bins[bin][1] += mismatch;
            }
            foreach (Run run in Runs(a.operations))
                if (run.operation == 'I' || run.operation == 'D') {
                    int kind = run.operation == 'I' ? 0 : 1;
                    events[kind]++;
                    indelBases[kind] += run.count;
                }
        }
        int aligned = Sum(qualityCounts), mismatches = qualityCounts[1];
        List<string> lines = new();
        lines.Add("error_profile aligned_bases " + aligned + " mismatches " + mismatches +
                  " rate " + Ratio(mismatches, aligned));
        lines.Add("substitutions");
        lines.Add("ref A C G T N");
        for (int r = 0; r < 4; r++) {
            string line = "" + SuffixArray.BASES[r];
            foreach (int value in substitutions[r])
                line += " " + value;
            lines.Add(line);
        }
        lines.Add("mismatch_by_cycle");
        for (int cycle = 1; cycle <= maxCycle; cycle++)
            lines.Add("cycle " + cycle + " aligned " + cycles[cycle][0] + " mismatches " +
                      cycles[cycle][1] + " rate " + Ratio(cycles[cycle][1], cycles[cycle][0]));
        lines.Add("quality matched " + qualityCounts[0] + " mean " +
                  Ratio(qualitySums[0], qualityCounts[0]) + " mismatched " + qualityCounts[1] +
                  " mean " + Ratio(qualitySums[1], qualityCounts[1]));
        lines.Add("quality_bins");
        string[] ranges = { "0-9", "10-19", "20-29", "30-39", "40-" };
        for (int b = 0; b < 5; b++)
            lines.Add(ranges[b] + " aligned " + bins[b][0] + " mismatches " + bins[b][1] +
                      " rate " + Ratio(bins[b][1], bins[b][0]));
        lines.Add("cigar M " + operationCounts[0] + " I " + operationCounts[1] + " D " +
                  operationCounts[2] + " S " + operationCounts[3]);
        lines.Add("indels insertions " + events[0] + " " + indelBases[0] + " deletions " +
                  events[1] + " " + indelBases[1]);
        return lines;
    }
    public static List<string> Statistics(List<Result> results) {
        int total = results.Count, trimmed = 0, trimmedBases = 0, shortCount = 0, nohit = 0,
            unique = 0, forwardCount = 0, nReads = 0, nBases = 0, nMapped = 0,
            minLength = int.MaxValue, maxLength = 0;
        List<Result> mapped = new();
        int[] methods = new int[3];
        SortedDictionary<string, int> targets = new(StringComparer.Ordinal);
        SortedDictionary<int, int> mapqs = new(), nms = new();
        foreach (Result result in results) {
            if (result.trimmed > 0)
                trimmed++;
            trimmedBases += result.trimmed;
            minLength = Math.Min(minLength, result.length);
            maxLength = Math.Max(maxLength, result.length);
            int ns = 0;
            foreach (char baseChar in result.read.bases.ToCharArray())
                if (baseChar == 'N')
                    ns++;
            if (ns > 0) {
                nReads++;
                nBases += ns;
                if (result.mapped)
                    nMapped++;
            }
            if (!result.mapped) {
                if (result.reason.Equals("SHORT"))
                    shortCount++;
                else
                    nohit++;
                continue;
            }
            mapped.Add(result);
            if (result.x0 == 1)
                unique++;
            if (result.primary.strand == 0)
                forwardCount++;
            methods[result.method.Equals("EXACT") ? 0 : result.method.Equals("MISMATCH") ? 1 : 2]++;
            mapqs.AddCount(result.mapq, 1);
            nms.AddCount(result.primary.nm, 1);
            if (result.x0 >= 2) {
                List<string> names = new();
                foreach (int reference in result.targets)
                    names.Add(references[reference].name);
                targets.AddCount(string.Join("+", names), 1);
            }
        }
        List<string> lines = new();
        lines.Add("reads total " + total + " trimmed " + trimmed + " trimmed_bases " +
                  trimmedBases + " short " + shortCount);
        lines.Add("mapped " + mapped.Count + " rate " + Ratio(mapped.Count, total) + " unique " +
                  unique + " multi " + (mapped.Count - unique) + " unmapped " +
                  (total - mapped.Count));
        lines.Add("unmapped short " + shortCount + " nohit " + nohit);
        lines.Add("method exact " + methods[0] + " mismatch " + methods[1] + " seed " + methods[2]);
        lines.Add("strand forward " + forwardCount + " reverse " + (mapped.Count - forwardCount));
        for (int r = 0; r < references.Count; r++) {
            int count = 0, one = 0, plus = 0;
            foreach (Result result in mapped)
                if (result.primary.reference == r) {
                    count++;
                    if (result.x0 == 1)
                        one++;
                    if (result.primary.strand == 0)
                        plus++;
                }
            lines.Add("reference " + references[r].name + " mapped " + count + " unique " + one +
                      " forward " + plus + " reverse " + (count - plus));
        }
        lines.Add("length_bins");
        for (int lower = minLength / 10 * 10; lower <= maxLength / 10 * 10; lower += 10) {
            int reads = 0, placed = 0, one = 0;
            foreach (Result result in results)
                if (result.length >= lower && result.length <= lower + 9) {
                    reads++;
                    if (result.mapped) {
                        placed++;
                        if (result.x0 == 1)
                            one++;
                    }
                }
            lines.Add(lower + "-" + (lower + 9) + " reads " + reads + " mapped " + placed +
                      " unique " + one);
        }
        lines.Add("n_reads " + nReads + " n_bases " + nBases + " mapped " + nMapped);
        lines.Add("multi_targets");
        if (targets.Count == 0)
            lines.Add("none");
        else
            foreach (var entry in targets)
                lines.Add(entry.Key + " " + entry.Value);
        lines.Add("mapq_histogram");
        foreach (int value in mapqs.Keys.Reverse())
            lines.Add(value + " " + mapqs[value]);
        lines.Add("nm_histogram");
        foreach (var entry in nms)
            lines.Add(entry.Key + " " + entry.Value);
        lines.AddRange(ErrorStatistics(results));
        lines.Add("search dfs_calls " + searchCounts[0] + " dfs_nodes " + searchCounts[1] +
                  " dfs_leaves " + searchCounts[2] + " dfs_positions " + searchCounts[3]);
        string[] keys = { "reads",       "seeds",      "with_n", "repetitive",
                          "without_hit", "candidates", "passing" };
        string line = "seeds";
        for (int i = 0; i < keys.Length; i++)
            line += " " + keys[i] + " " + seedCounts[i];
        lines.Add(line);
        return lines;
    }
    public static void Main(string[] args) {
        SequenceIo.Input input = SequenceIo.ReadInputs();
        references = input.references;
        parameters = input.parameters;
        Text();
        SuffixArray.Built built = SuffixArray.Build(text),
                          reversed = SuffixArray.Build(reverseText);
        forward =
            new FmIndex(text, built.suffixes, Value("OCC_INTERVAL"), Value("SA_SAMPLE_INTERVAL"));
        reverse = new FmIndex(reverseText, reversed.suffixes, Value("OCC_INTERVAL"), 0);
        List<string> index = IndexStatistics(built, reversed);
        List<Result> results = new();
        foreach (SequenceIo.Read read in input.reads)
            results.Add(Map(read));
        List<string> sam = SamWriter.Header(references);
        foreach (Result result in results)
            sam.Add(SamWriter.Record(result, references, Value("MAX_ALT_HITS")));
        Coverage coverage = BuildCoverage(results);
        SamWriter.Write("alignments.sam", sam);
        SamWriter.Write("coverage.txt", coverage.coverage);
        SamWriter.Write("variants.txt", coverage.variants);
        SamWriter.Write("index_stats.txt", index);
        SamWriter.Write("summary.txt", Statistics(results));
    }
}
