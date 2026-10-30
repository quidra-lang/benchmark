import java.util.*;
public class Main {
    static List<SequenceIo.Reference> references;
    static Map<String, int[]> parameters;
    static String text, reverseText;
    static int[] offsets;
    static FmIndex forward, reverse;
    static int[] searchCounts = new int[4], seedCounts = new int[7];
    static final int NEG = -1000000;
    record Position(int reference, int offset) {}
    record Pair(int readOffset, int offset) {}
    record Run(char operation, int count) {}
    record Hit(int mismatches, int reference, int position, int strand) {}
    record Candidate(int strand, int reference, int center) {}
    record Key(int reference, int position, int strand) {}
    record Banded(int score, int position, String operations) {}
    record Scored(int score, Alignment alignment) {}
    static final class Alignment {
        int reference, position, strand, nm;
        String operations, oriented, cigar, md;
        List<Pair> pairs = new ArrayList<>();
    }
    static final class Result {
        SequenceIo.Read read;
        int[] qualities;
        int length, trimmed, mapq, score, x0, x1;
        String core, reason = "SHORT", method;
        boolean mapped;
        Alignment primary;
        List<Alignment> others = new ArrayList<>();
        List<Integer> targets = new ArrayList<>();
    }
    static int value(String key) { return parameters.get(key)[0]; }
    static String ratio(long a, long b) { return SamWriter.ratio(a, b); }
    static String yes(boolean value) { return value ? "yes" : "no"; }
    static int sum(int[] values) {
        int sum = 0;
        for (int value : values)
            sum += value;
        return sum;
    }
    static void text() {
        offsets = new int[references.size()];
        List<String> parts = new ArrayList<>();
        int offset = 0;
        for (int r = 0; r < references.size(); r++) {
            offsets[r] = offset;
            String bases = references.get(r).bases();
            offset += bases.length() + 1;
            parts.add(bases);
        }
        text = String.join("#", parts) + "$";
        reverseText = new StringBuilder(text.substring(0, text.length() - 1)).reverse() + "$";
    }
    static Position position(int p) {
        for (int r = references.size() - 1; r >= 0; r--)
            if (p >= offsets[r])
                return p < offsets[r] + references.get(r).bases().length()
                    ? new Position(r, p - offsets[r])
                    : null;
        return null;
    }
    static String label(int p) {
        Position located = position(p);
        return located == null
            ? "*"
            : references.get(located.reference()).name() + ":" + (located.offset() + 1);
    }
    static Position locate(int row) { return position(forward.locate(row).position()); }
    static List<Run> runs(String operations) {
        List<Run> runs = new ArrayList<>();
        for (int i = 0; i < operations.length();) {
            int j = i + 1;
            while (j < operations.length() && operations.charAt(j) == operations.charAt(i))
                j++;
            runs.add(new Run(operations.charAt(i), j - i));
            i = j;
        }
        return runs;
    }
    static Alignment describe(int reference, int position, int strand, String operations,
                              Result result) {
        Alignment a = new Alignment();
        a.reference = reference;
        a.position = position;
        a.strand = strand;
        a.operations = operations;
        a.oriented = strand == 0 ? result.core : SequenceIo.reverseComplement(result.core);
        String sequence = references.get(reference).bases();
        StringBuilder cigar = new StringBuilder(), md = new StringBuilder();
        int i = 0, j = position, matches = 0;
        for (Run run : runs(operations)) {
            char operation = run.operation();
            int count = run.count();
            cigar.append(count).append(operation);
            if (operation == 'I') {
                i += count;
                a.nm += count;
            } else if (operation == 'D') {
                md.append(matches).append('^').append(sequence.substring(j, j + count));
                matches = 0;
                j += count;
                a.nm += count;
            } else
                for (int n = 0; n < count; n++) {
                    a.pairs.add(new Pair(i, j));
                    if (a.oriented.charAt(i) == sequence.charAt(j))
                        matches++;
                    else {
                        md.append(matches).append(sequence.charAt(j));
                        matches = 0;
                        a.nm++;
                    }
                    i++;
                    j++;
                }
        }
        md.append(matches);
        if (result.trimmed > 0) {
            String soft = result.trimmed + "S";
            if (strand == 0)
                cigar.append(soft);
            else
                cigar.insert(0, soft);
        }
        a.cigar = cigar.toString();
        a.md = md.toString();
        return a;
    }
    static int cell(int[][] values, int[] first, int i, int j) {
        if (i < 0 || i >= values.length)
            return NEG;
        int k = j - first[i];
        return k < 0 || k >= values[i].length ? NEG : values[i][k];
    }
    static int subtract(int value, int penalty) { return value == NEG ? NEG : value - penalty; }
    static Banded banded(String oriented, String sequence, int center) {
        int l = oriented.length(), m = sequence.length(), width = value("BAND_WIDTH");
        int[] scores = parameters.get("SCORES"), first = new int[l + 1];
        int[][] h = new int[l + 1][], e = new int[l + 1][], f = new int[l + 1][];
        for (int i = 0; i <= l; i++) {
            first[i] = Math.max(0, i + center - width);
            int last = Math.min(m, i + center + width), size = Math.max(0, last - first[i] + 1);
            h[i] = new int[size];
            e[i] = new int[size];
            f[i] = new int[size];
            Arrays.fill(h[i], i == 0 ? 0 : NEG);
            Arrays.fill(e[i], NEG);
            Arrays.fill(f[i], NEG);
        }
        for (int i = 1; i <= l; i++)
            for (int k = 0; k < h[i].length; k++) {
                int j = first[i] + k;
                f[i][k] = Math.max(subtract(cell(h, first, i - 1, j), scores[2] + scores[3]),
                                   subtract(cell(f, first, i - 1, j), scores[3]));
                if (j >= 1)
                    e[i][k] = Math.max(subtract(cell(h, first, i, j - 1), scores[2] + scores[3]),
                                       subtract(cell(e, first, i, j - 1), scores[3]));
                int diagonal = NEG;
                if (j >= 1) {
                    int previous = cell(h, first, i - 1, j - 1);
                    if (previous != NEG)
                        diagonal = previous + (oriented.charAt(i - 1) == sequence.charAt(j - 1)
                                                   ? scores[0]
                                                   : -scores[1]);
                }
                h[i][k] = Math.max(diagonal, Math.max(e[i][k], f[i][k]));
            }
        int best = NEG, end = -1;
        for (int k = 0; k < h[l].length; k++)
            if (h[l][k] > best) {
                best = h[l][k];
                end = first[l] + k;
            }
        if (end < 0)
            return null;
        int i = l, j = end;
        char state = 'H';
        StringBuilder backward = new StringBuilder();
        while (true) {
            if (state == 'H') {
                if (i == 0)
                    break;
                int previous = j >= 1 ? cell(h, first, i - 1, j - 1) : NEG;
                if (previous != NEG &&
                    cell(h, first, i, j) ==
                        previous + (oriented.charAt(i - 1) == sequence.charAt(j - 1)
                                        ? scores[0]
                                        : -scores[1])) {
                    backward.append('M');
                    i--;
                    j--;
                    continue;
                }
                state = cell(f, first, i, j) != NEG && cell(h, first, i, j) == cell(f, first, i, j)
                            ? 'I'
                            : 'D';
            } else if (state == 'I') {
                backward.append('I');
                int previous = cell(f, first, i - 1, j);
                state = previous != NEG && cell(f, first, i, j) == previous - scores[3] ? 'I' : 'H';
                i--;
            } else {
                backward.append('D');
                int previous = cell(e, first, i, j - 1);
                state = previous != NEG && cell(e, first, i, j) == previous - scores[3] ? 'D' : 'H';
                j--;
            }
        }
        return new Banded(best, j, backward.reverse().toString());
    }
    static int comparePosition(Alignment a, Alignment b) {
        int c = Integer.compare(a.reference, b.reference);
        if (c == 0)
            c = Integer.compare(a.position, b.position);
        return c != 0 ? c : Integer.compare(a.strand, b.strand);
    }
    static Result map(SequenceIo.Read read) {
        Result result = new Result();
        result.read = read;
        result.qualities = new int[read.quality().length()];
        for (int i = 0; i < result.qualities.length; i++)
            result.qualities[i] = read.quality().charAt(i) - 33;
        int length = read.bases().length();
        while (length > 0 && result.qualities[length - 1] < value("TRIM_QUALITY"))
            length--;
        result.length = length;
        result.trimmed = read.bases().length() - length;
        result.core = read.bases().substring(0, length);
        if (length < value("MIN_READ_LENGTH"))
            return result;
        String[] oriented = {result.core, SequenceIo.reverseComplement(result.core)};
        FmIndex.Interval exactForward = forward.backward(oriented[0]),
                         exactReverse = forward.backward(oriented[1]);
        int maximum = exactForward.empty() && exactReverse.empty() ? value("MAX_MISMATCHES") : 1;
        List<Hit> hits = new ArrayList<>();
        for (int strand = 0; strand < 2; strand++) {
            Search.Result search = Search.backtrack(oriented[strand], maximum, forward, reverse);
            searchCounts[0]++;
            searchCounts[1] += search.nodes();
            searchCounts[2] += search.leaves().size();
            searchCounts[3] += search.positions();
            for (Search.Leaf leaf : search.leaves())
                for (int row = leaf.lower(); row < leaf.upper(); row++) {
                    Position position = locate(row);
                    hits.add(new Hit(leaf.mismatches(), position.reference(), position.offset(),
                                     strand));
                }
        }
        if (hits.isEmpty())
            seed(result, oriented);
        else
            finish(result, hits);
        return result;
    }
    static void finish(Result result, List<Hit> hits) {
        hits.sort(Comparator.comparingInt(Hit::mismatches)
                      .thenComparingInt(Hit::reference)
                      .thenComparingInt(Hit::position)
                      .thenComparingInt(Hit::strand));
        int best = hits.getFirst().mismatches(), n1 = 0, n2 = 0;
        List<Alignment> alignments = new ArrayList<>();
        TreeSet<Integer> targets = new TreeSet<>();
        for (Hit hit : hits) {
            if (hit.mismatches() == best) {
                n1++;
                targets.add(hit.reference());
            }
            if (hit.mismatches() == best + 1)
                n2++;
            if (hit.mismatches() <= best + 1)
                alignments.add(describe(hit.reference(), hit.position(), hit.strand(),
                                        "M".repeat(result.length), result));
        }
        result.mapped = true;
        result.primary = alignments.getFirst();
        result.others = new ArrayList<>(alignments.subList(1, alignments.size()));
        result.targets = new ArrayList<>(targets);
        result.method = best == 0 ? "EXACT" : "MISMATCH";
        int[] scores = parameters.get("SCORES");
        result.score = (result.length - best) * scores[0] - best * scores[1];
        result.x0 = n1;
        result.x1 = n2;
        result.mapq = n1 >= 2 ? 0 : n2 == 0 ? 60 - 12 * best : Math.max(30 - 12 * best - 3 * n2, 1);
    }
    static List<Candidate> candidates(String[] oriented) {
        Set<Candidate> candidates = new HashSet<>();
        int seedLength = value("SEED_LENGTH");
        for (int strand = 0; strand < 2; strand++)
            for (int offset = 0; offset + seedLength <= oriented[strand].length();
                 offset += value("SEED_STEP")) {
                seedCounts[1]++;
                String seed = oriented[strand].substring(offset, offset + seedLength);
                if (seed.indexOf('N') >= 0) {
                    seedCounts[2]++;
                    continue;
                }
                FmIndex.Interval interval = forward.backward(seed);
                if (interval.upper() - interval.lower() > value("MAX_SEED_HITS"))
                    seedCounts[3]++;
                else if (interval.empty())
                    seedCounts[4]++;
                else
                    for (int row = interval.lower(); row < interval.upper(); row++) {
                        Position position = locate(row);
                        candidates.add(new Candidate(strand, position.reference(),
                                                     position.offset() - offset));
                    }
            }
        seedCounts[5] += candidates.size();
        List<Candidate> ordered = new ArrayList<>(candidates);
        ordered.sort(Comparator.comparingInt(Candidate::strand)
                         .thenComparingInt(Candidate::reference)
                         .thenComparingInt(Candidate::center));
        return ordered;
    }
    static void seed(Result result, String[] oriented) {
        result.reason = "NOHIT";
        if (result.length < value("SEED_LENGTH"))
            return;
        seedCounts[0]++;
        Map<Key, Scored> accepted = new HashMap<>();
        int threshold = value("MIN_SCORE_PERCENT") * parameters.get("SCORES")[0] * result.length;
        for (Candidate candidate : candidates(oriented)) {
            Banded alignment =
                banded(oriented[candidate.strand()], references.get(candidate.reference()).bases(),
                       candidate.center());
            if (alignment == null || 100 * alignment.score() < threshold)
                continue;
            Key key = new Key(candidate.reference(), alignment.position(), candidate.strand());
            Scored old = accepted.get(key);
            if (old == null || alignment.score() > old.score())
                accepted.put(
                    key, new Scored(alignment.score(),
                                    describe(candidate.reference(), alignment.position(),
                                             candidate.strand(), alignment.operations(), result)));
        }
        seedCounts[6] += accepted.size();
        if (accepted.isEmpty())
            return;
        List<Scored> ordered = new ArrayList<>(accepted.values());
        ordered.sort((a, b) -> {
            int c = Integer.compare(b.score(), a.score());
            return c != 0 ? c : comparePosition(a.alignment(), b.alignment());
        });
        int best = ordered.getFirst().score(), n1 = 0, second = 0;
        TreeSet<Integer> targets = new TreeSet<>();
        List<Alignment> alignments = new ArrayList<>();
        for (Scored alignment : ordered) {
            alignments.add(alignment.alignment());
            if (alignment.score() == best) {
                n1++;
                targets.add(alignment.alignment().reference);
            } else
                second = Math.max(second, alignment.score());
        }
        result.mapped = true;
        result.primary = alignments.getFirst();
        result.others = new ArrayList<>(alignments.subList(1, alignments.size()));
        result.targets = new ArrayList<>(targets);
        result.method = "SEED";
        result.score = best;
        result.x0 = n1;
        result.x1 = ordered.size() - n1;
        result.mapq = n1 >= 2 ? 0 : 60 * (best - second) / best;
    }
    static List<String> indexStatistics(SuffixArray.Built built, SuffixArray.Built reversed) {
        int size = text.length();
        List<String> lines = new ArrayList<>();
        lines.add("text length " + size + " sequences " + references.size());
        for (int r = 0; r < references.size(); r++) {
            SequenceIo.Reference reference = references.get(r);
            int gc = 0;
            for (char base : reference.bases().toCharArray())
                if (base == 'G' || base == 'C')
                    gc++;
            lines.add("sequence " + reference.name() + " length " + reference.bases().length() +
                      " offset " + offsets[r] + " gc " + ratio(gc, reference.bases().length()) +
                      " masked " + reference.masked());
        }
        int[] frequencies = new int[6];
        for (char symbol : text.toCharArray())
            frequencies[SuffixArray.SYMBOLS.indexOf(symbol)]++;
        String symbols = "symbols";
        for (int i = 0; i < 6; i++)
            symbols += " " + SuffixArray.SYMBOLS.charAt(i) + " " + frequencies[i];
        lines.add(symbols);
        lines.add("");
        lines.add("forward_index");
        lines.add("suffix_array rounds " + (built.classes().size() - 1));
        for (int t = 0; t < built.classes().size(); t++)
            lines.add("round " + t + " prefix_length " + (1 << t) + " classes " +
                      built.classes().get(t));
        SuffixArray.Check check = SuffixArray.check(text, built.suffixes());
        lines.add("sa_check pairs " + (size - 1) + " ordered " + check.ordered() + " lcp_sum " +
                  check.lcpSum() + " mean_lcp " + ratio(check.lcpSum(), size - 1) + " max_lcp " +
                  check.maximum());
        lines.add("longest_repeat " + check.maximum() + " " +
                  label(built.suffixes()[check.row() - 1]) + " " +
                  label(built.suffixes()[check.row()]));
        int length = value("SEED_LENGTH");
        Map<String, Integer> kmers = new HashMap<>();
        for (SequenceIo.Reference reference : references)
            for (int i = 0; i + length <= reference.bases().length(); i++)
                kmers.merge(reference.bases().substring(i, i + length), 1, Integer::sum);
        int occurrences = 0, unique = 0, maximum = 0;
        for (int count : kmers.values()) {
            occurrences += count;
            if (count == 1)
                unique++;
            maximum = Math.max(maximum, count);
        }
        lines.add("kmers length " + length + " occurrences " + occurrences + " distinct " +
                  kmers.size() + " unique " + unique + " max_occurrence " + maximum +
                  " unique_fraction " + ratio(unique, occurrences));
        lines.add("bwt runs " + runs(forward.bwt).size() + " head " +
                  forward.bwt.substring(0, Math.min(60, size)));
        String c = "c_array";
        for (int i = 0; i < 6; i++)
            c += " " + SuffixArray.SYMBOLS.charAt(i) + " " + forward.c[i];
        lines.add(c);
        lines.add("occ interval " + forward.interval + " checkpoints " +
                  forward.checkpoints.length);
        lines.add("sa_sample interval " + value("SA_SAMPLE_INTERVAL") + " samples " +
                  forward.sampleCount);
        int correct = 0, totalSteps = 0, maxSteps = 0;
        for (int row = 0; row < size; row++) {
            FmIndex.Location location = forward.locate(row);
            if (location.position() == built.suffixes()[row])
                correct++;
            totalSteps += location.steps();
            maxSteps = Math.max(maxSteps, location.steps());
        }
        lines.add("locate rows " + size + " correct " + correct + " total_steps " + totalSteps +
                  " max_steps " + maxSteps + " mean_steps " + ratio(totalSteps, size));
        lines.add("inverse_bwt identical " + yes(forward.inverse().equals(text)));
        lines.add("");
        lines.add("reverse_index");
        lines.add("suffix_array rounds " + (reversed.classes().size() - 1));
        lines.add("sa_check pairs " + (size - 1) + " ordered " +
                  SuffixArray.check(reverseText, reversed.suffixes()).ordered());
        lines.add("bwt runs " + runs(reverse.bwt).size() + " head " +
                  reverse.bwt.substring(0, Math.min(60, size)));
        lines.add("inverse_bwt identical " + yes(reverse.inverse().equals(reverseText)));
        lines.add("");
        lines.add("direct_sort");
        int cross = 0;
        for (SequenceIo.Reference reference : references)
            if (reference.bases().length() <= value("DIRECT_SORT_LIMIT")) {
                String sequence = reference.bases() + "$";
                SuffixArray.Built doubled = SuffixArray.build(sequence);
                lines.add(reference.name() + " length " + sequence.length() + " rounds " +
                          (doubled.classes().size() - 1) + " identical " +
                          yes(Arrays.equals(doubled.suffixes(), SuffixArray.direct(sequence))));
                cross++;
            }
        if (cross == 0)
            lines.add("none");
        int occurrenceBytes = 24 * forward.checkpoints.length,
            sampleBytes = 4 * forward.sampleCount, bitmapBytes = (size + 7) / 8,
            totalBytes = size + occurrenceBytes + sampleBytes + bitmapBytes;
        lines.add("");
        lines.add("index_size bwt_bytes " + size + " occ_bytes " + occurrenceBytes +
                  " sample_bytes " + sampleBytes + " bitmap_bytes " + bitmapBytes +
                  " total_bytes " + totalBytes + " full_bytes " + (5 * size) + " ratio " +
                  ratio(totalBytes, 5 * size));
        return lines;
    }
    record Coverage(List<String> coverage, List<String> variants) {}
    static Coverage coverage(List<Result> results) {
        int[][] depths = new int[references.size()][], starts = new int[references.size()][];
        int[][][][] pileups = new int[references.size()][][][];
        for (int r = 0; r < references.size(); r++) {
            int length = references.get(r).bases().length();
            depths[r] = new int[length];
            starts[r] = new int[length];
            pileups[r] = new int[length][4][2];
        }
        int[] variant = parameters.get("VARIANTS");
        int minMapq = value("COVERAGE_MIN_MAPQ");
        for (Result result : results) {
            if (!result.mapped)
                continue;
            Alignment a = result.primary;
            int r = a.reference;
            if (result.mapq == 0)
                starts[r][a.position]++;
            if (result.mapq < minMapq)
                continue;
            for (Pair pair : a.pairs) {
                depths[r][pair.offset()]++;
                char base = a.oriented.charAt(pair.readOffset());
                int cycle =
                    a.strand == 0 ? pair.readOffset() + 1 : result.length - pair.readOffset();
                if (base != 'N' && result.qualities[cycle - 1] >= variant[1])
                    pileups[r][pair.offset()][SuffixArray.BASES.indexOf(base)][a.strand]++;
            }
        }
        int window = value("COVERAGE_WINDOW");
        List<String> coverage = new ArrayList<>(), variants = new ArrayList<>();
        coverage.add("window " + window + " min_mapq " + minMapq);
        variants.add("min_depth " + variant[0] + " min_base_quality " + variant[1] +
                     " min_alt_percent " + variant[2] + " hom_percent " + variant[3]);
        int callable = 0, variantCount = 0, heterozygous = 0, homozygous = 0;
        for (int r = 0; r < references.size(); r++) {
            SequenceIo.Reference reference = references.get(r);
            int length = reference.bases().length(), covered = 0, total = 0, maximum = 0;
            for (int d : depths[r]) {
                if (d > 0)
                    covered++;
                total += d;
                maximum = Math.max(maximum, d);
            }
            int[] histogram = new int[maximum + 1];
            for (int d : depths[r])
                histogram[d]++;
            coverage.add("reference " + reference.name() + " length " + length + " covered " +
                         covered + " breadth " + ratio(covered, length) + " mean_depth " +
                         ratio(total, length) + " max_depth " + maximum);
            String line = "depth_histogram";
            for (int d = 0; d <= maximum; d++)
                line += " " + d + ":" + histogram[d];
            coverage.add(line);
            for (int first = 0; first < length; first += window) {
                int last = Math.min(first + window, length), size = last - first, gc = 0, sum = 0,
                    max = 0, zero = 0, mapq0 = 0;
                for (int j = first; j < last; j++) {
                    char base = reference.bases().charAt(j);
                    if (base == 'G' || base == 'C')
                        gc++;
                    sum += depths[r][j];
                    max = Math.max(max, depths[r][j]);
                    if (depths[r][j] == 0)
                        zero++;
                    mapq0 += starts[r][j];
                }
                coverage.add(reference.name() + " " + (first + 1) + " " + last + " gc " +
                             ratio(gc, size) + " sum " + sum + " mean " + ratio(sum, size) +
                             " max " + max + " zero " + zero + " mapq0 " + mapq0 + " |"
                             + "#".repeat(10 * sum / size));
            }
            for (int j = 0; j < length; j++) {
                int[] counts = new int[4];
                for (int b = 0; b < 4; b++)
                    counts[b] = sum(pileups[r][j][b]);
                int depth = sum(counts);
                if (depth < variant[0])
                    continue;
                callable++;
                char referenceBase = reference.bases().charAt(j);
                int alternative = -1;
                for (int b = 0; b < 4; b++)
                    if (SuffixArray.BASES.charAt(b) != referenceBase &&
                        (alternative < 0 || counts[b] > counts[alternative]))
                        alternative = b;
                int count = counts[alternative];
                if (count < 2 || 100 * count < variant[2] * depth)
                    continue;
                boolean hom = 100 * count >= variant[3] * depth;
                if (hom)
                    homozygous++;
                else
                    heterozygous++;
                variantCount++;
                String countsText = "";
                for (int b = 0; b < 4; b++)
                    countsText += (b == 0 ? "" : " ") + counts[b];
                variants.add(reference.name() + " " + (j + 1) + " " + referenceBase + ">" +
                             SuffixArray.BASES.charAt(alternative) + " depth " + depth + " alt " +
                             count + " fraction " + ratio(count, depth) + " genotype " +
                             (hom ? "1/1" : "0/1") + " strands " + pileups[r][j][alternative][0] +
                             " " + pileups[r][j][alternative][1] + " counts " + countsText);
            }
        }
        variants.add("callable " + callable + " variants " + variantCount + " heterozygous " +
                     heterozygous + " homozygous " + homozygous);
        return new Coverage(coverage, variants);
    }
    static List<String> errorStatistics(List<Result> results) {
        int maxCycle = 0;
        for (Result result : results)
            maxCycle = Math.max(maxCycle, result.read.bases().length());
        int[][] cycles = new int[maxCycle + 1][2], substitutions = new int[4][5],
                bins = new int[5][2];
        int[] qualityCounts = new int[2], qualitySums = new int[2], operationCounts = new int[4],
              events = new int[2], indelBases = new int[2];
        for (Result result : results) {
            if (!result.mapped)
                continue;
            Alignment a = result.primary;
            for (char operation : a.operations.toCharArray())
                operationCounts["MIDS".indexOf(operation)]++;
            operationCounts[3] += result.trimmed;
            if (result.x0 != 1)
                continue;
            String sequence = references.get(a.reference).bases();
            for (Pair pair : a.pairs) {
                char observed = a.oriented.charAt(pair.readOffset()),
                     reference = sequence.charAt(pair.offset());
                int mismatch = observed == reference ? 0 : 1,
                    cycle =
                        a.strand == 0 ? pair.readOffset() + 1 : result.length - pair.readOffset(),
                    quality = result.qualities[cycle - 1];
                cycles[cycle][0]++;
                cycles[cycle][1] += mismatch;
                substitutions[SuffixArray.BASES.indexOf(reference)]["ACGTN".indexOf(observed)]++;
                qualityCounts[mismatch]++;
                qualitySums[mismatch] += quality;
                int bin = Math.min(quality / 10, 4);
                bins[bin][0]++;
                bins[bin][1] += mismatch;
            }
            for (Run run : runs(a.operations))
                if (run.operation() == 'I' || run.operation() == 'D') {
                    int kind = run.operation() == 'I' ? 0 : 1;
                    events[kind]++;
                    indelBases[kind] += run.count();
                }
        }
        int aligned = sum(qualityCounts), mismatches = qualityCounts[1];
        List<String> lines = new ArrayList<>();
        lines.add("error_profile aligned_bases " + aligned + " mismatches " + mismatches +
                  " rate " + ratio(mismatches, aligned));
        lines.add("substitutions");
        lines.add("ref A C G T N");
        for (int r = 0; r < 4; r++) {
            String line = "" + SuffixArray.BASES.charAt(r);
            for (int value : substitutions[r])
                line += " " + value;
            lines.add(line);
        }
        lines.add("mismatch_by_cycle");
        for (int cycle = 1; cycle <= maxCycle; cycle++)
            lines.add("cycle " + cycle + " aligned " + cycles[cycle][0] + " mismatches " +
                      cycles[cycle][1] + " rate " + ratio(cycles[cycle][1], cycles[cycle][0]));
        lines.add("quality matched " + qualityCounts[0] + " mean " +
                  ratio(qualitySums[0], qualityCounts[0]) + " mismatched " + qualityCounts[1] +
                  " mean " + ratio(qualitySums[1], qualityCounts[1]));
        lines.add("quality_bins");
        String[] ranges = {"0-9", "10-19", "20-29", "30-39", "40-"};
        for (int b = 0; b < 5; b++)
            lines.add(ranges[b] + " aligned " + bins[b][0] + " mismatches " + bins[b][1] +
                      " rate " + ratio(bins[b][1], bins[b][0]));
        lines.add("cigar M " + operationCounts[0] + " I " + operationCounts[1] + " D " +
                  operationCounts[2] + " S " + operationCounts[3]);
        lines.add("indels insertions " + events[0] + " " + indelBases[0] + " deletions " +
                  events[1] + " " + indelBases[1]);
        return lines;
    }
    static List<String> statistics(List<Result> results) {
        int total = results.size(), trimmed = 0, trimmedBases = 0, shortCount = 0, nohit = 0,
            unique = 0, forwardCount = 0, nReads = 0, nBases = 0, nMapped = 0,
            minLength = Integer.MAX_VALUE, maxLength = 0;
        List<Result> mapped = new ArrayList<>();
        int[] methods = new int[3];
        TreeMap<String, Integer> targets = new TreeMap<>();
        TreeMap<Integer, Integer> mapqs = new TreeMap<>(), nms = new TreeMap<>();
        for (Result result : results) {
            if (result.trimmed > 0)
                trimmed++;
            trimmedBases += result.trimmed;
            minLength = Math.min(minLength, result.length);
            maxLength = Math.max(maxLength, result.length);
            int ns = 0;
            for (char base : result.read.bases().toCharArray())
                if (base == 'N')
                    ns++;
            if (ns > 0) {
                nReads++;
                nBases += ns;
                if (result.mapped)
                    nMapped++;
            }
            if (!result.mapped) {
                if (result.reason.equals("SHORT"))
                    shortCount++;
                else
                    nohit++;
                continue;
            }
            mapped.add(result);
            if (result.x0 == 1)
                unique++;
            if (result.primary.strand == 0)
                forwardCount++;
            methods[result.method.equals("EXACT") ? 0 : result.method.equals("MISMATCH") ? 1 : 2]++;
            mapqs.merge(result.mapq, 1, Integer::sum);
            nms.merge(result.primary.nm, 1, Integer::sum);
            if (result.x0 >= 2) {
                List<String> names = new ArrayList<>();
                for (int reference : result.targets)
                    names.add(references.get(reference).name());
                targets.merge(String.join("+", names), 1, Integer::sum);
            }
        }
        List<String> lines = new ArrayList<>();
        lines.add("reads total " + total + " trimmed " + trimmed + " trimmed_bases " +
                  trimmedBases + " short " + shortCount);
        lines.add("mapped " + mapped.size() + " rate " + ratio(mapped.size(), total) + " unique " +
                  unique + " multi " + (mapped.size() - unique) + " unmapped " +
                  (total - mapped.size()));
        lines.add("unmapped short " + shortCount + " nohit " + nohit);
        lines.add("method exact " + methods[0] + " mismatch " + methods[1] + " seed " + methods[2]);
        lines.add("strand forward " + forwardCount + " reverse " + (mapped.size() - forwardCount));
        for (int r = 0; r < references.size(); r++) {
            int count = 0, one = 0, plus = 0;
            for (Result result : mapped)
                if (result.primary.reference == r) {
                    count++;
                    if (result.x0 == 1)
                        one++;
                    if (result.primary.strand == 0)
                        plus++;
                }
            lines.add("reference " + references.get(r).name() + " mapped " + count + " unique " +
                      one + " forward " + plus + " reverse " + (count - plus));
        }
        lines.add("length_bins");
        for (int lower = minLength / 10 * 10; lower <= maxLength / 10 * 10; lower += 10) {
            int reads = 0, placed = 0, one = 0;
            for (Result result : results)
                if (result.length >= lower && result.length <= lower + 9) {
                    reads++;
                    if (result.mapped) {
                        placed++;
                        if (result.x0 == 1)
                            one++;
                    }
                }
            lines.add(lower + "-" + (lower + 9) + " reads " + reads + " mapped " + placed +
                      " unique " + one);
        }
        lines.add("n_reads " + nReads + " n_bases " + nBases + " mapped " + nMapped);
        lines.add("multi_targets");
        if (targets.isEmpty())
            lines.add("none");
        else
            for (var entry : targets.entrySet())
                lines.add(entry.getKey() + " " + entry.getValue());
        lines.add("mapq_histogram");
        for (int value : mapqs.descendingKeySet())
            lines.add(value + " " + mapqs.get(value));
        lines.add("nm_histogram");
        for (var entry : nms.entrySet())
            lines.add(entry.getKey() + " " + entry.getValue());
        lines.addAll(errorStatistics(results));
        lines.add("search dfs_calls " + searchCounts[0] + " dfs_nodes " + searchCounts[1] +
                  " dfs_leaves " + searchCounts[2] + " dfs_positions " + searchCounts[3]);
        String[] keys = {"reads",       "seeds",      "with_n", "repetitive",
                         "without_hit", "candidates", "passing"};
        String line = "seeds";
        for (int i = 0; i < keys.length; i++)
            line += " " + keys[i] + " " + seedCounts[i];
        lines.add(line);
        return lines;
    }
    public static void main(String[] args) throws Exception {
        SequenceIo.Input input = SequenceIo.read();
        references = input.references();
        parameters = input.parameters();
        text();
        SuffixArray.Built built = SuffixArray.build(text), reversed =
                                                               SuffixArray.build(reverseText);
        forward =
            new FmIndex(text, built.suffixes(), value("OCC_INTERVAL"), value("SA_SAMPLE_INTERVAL"));
        reverse = new FmIndex(reverseText, reversed.suffixes(), value("OCC_INTERVAL"), 0);
        List<String> index = indexStatistics(built, reversed);
        List<Result> results = new ArrayList<>();
        for (SequenceIo.Read read : input.reads())
            results.add(map(read));
        List<String> sam = SamWriter.header(references);
        for (Result result : results)
            sam.add(SamWriter.record(result, references, value("MAX_ALT_HITS")));
        Coverage coverage = coverage(results);
        SamWriter.write("alignments.sam", sam);
        SamWriter.write("coverage.txt", coverage.coverage());
        SamWriter.write("variants.txt", coverage.variants());
        SamWriter.write("index_stats.txt", index);
        SamWriter.write("summary.txt", statistics(results));
    }
}
