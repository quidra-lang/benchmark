import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

public class Main {
    private static final Set<String> DATA_COMMANDS = Set.of("FILE", "PATCH", "EDIT");
    private static final Set<String> FORMATS_WITH_ARGUMENT =
            Set.of("IFDEF", "UNIFIED", "CONTEXT", "SIDE");
    private static final int[] OFFSETS = {0, 1, -1, 2, -2, 3, -3};
    private static final int GRAPH_WIDTH = 20;
    private static final Pattern NUMBER_PAIR = Pattern.compile("([0-9]{1,4})(?:,([0-9]{1,4}))?");
    private static final Pattern SPACE_RUN = Pattern.compile(" {2,}");
    private static final Map<String, Marker> MARKER_PREFIXES =
            Map.of("<<<<<<<", Marker.START, "|||||||", Marker.BASE, ">>>>>>>", Marker.END);
    private static final String SEPARATOR = "=======";

    static class CommandError extends RuntimeException {
        CommandError(String message) {
            super(message);
        }
    }

    static String rangeR(int start, int count) {
        if (count >= 2) {
            return (start + 1) + "," + (start + count);
        }
        if (count == 1) {
            return String.valueOf(start + 1);
        }
        return String.valueOf(start);
    }

    static String rangeU(int start, int count) {
        if (count >= 2) {
            return (start + 1) + "," + count;
        }
        if (count == 1) {
            return String.valueOf(start + 1);
        }
        return start + ",0";
    }

    static String rangeM(int start, int count) {
        return (start + 1) + "," + count;
    }

    static String comparisonKey(String line, List<String> options) {
        if (options.contains("ICASE")) {
            line = line.toLowerCase(Locale.ROOT);
        }
        if (options.contains("IWHITE")) {
            line = line.replace(" ", "");
        }
        if (options.contains("ISPACE")) {
            line = SPACE_RUN.matcher(line).replaceAll(" ");
        }
        return line;
    }

    static List<String> prefixed(String prefix, List<String> lines) {
        return lines.stream().map(line -> prefix + line).toList();
    }

    record LinePair(int i, int j) {}

    static List<LinePair> matchedPairs(List<String> first, List<String> second) {
        int rows = first.size();
        int columns = second.size();
        int[][] table = new int[rows + 1][columns + 1];
        for (int i = 1; i <= rows; i++) {
            for (int j = 1; j <= columns; j++) {
                if (first.get(i - 1).equals(second.get(j - 1))) {
                    table[i][j] = table[i - 1][j - 1] + 1;
                } else {
                    table[i][j] = Math.max(table[i - 1][j], table[i][j - 1]);
                }
            }
        }
        List<LinePair> pairs = new ArrayList<>();
        pairs.add(new LinePair(rows + 1, columns + 1));
        int i = rows;
        int j = columns;
        while (i >= 1 && j >= 1) {
            if (first.get(i - 1).equals(second.get(j - 1))) {
                pairs.add(new LinePair(i, j));
                i--;
                j--;
            } else if (table[i - 1][j] >= table[i][j - 1]) {
                i--;
            } else {
                j--;
            }
        }
        pairs.add(new LinePair(0, 0));
        return pairs.reversed();
    }

    record ChangeBlock(int p, int q, int x, int y) {
        char letter() {
            if (x >= 1 && y >= 1) {
                return 'c';
            }
            return y == 0 ? 'd' : 'a';
        }
    }

    static List<ChangeBlock> changeBlocks(List<String> first, List<String> second) {
        List<LinePair> pairs = matchedPairs(first, second);
        List<ChangeBlock> blocks = new ArrayList<>();
        for (int k = 0; k + 1 < pairs.size(); k++) {
            LinePair current = pairs.get(k);
            LinePair next = pairs.get(k + 1);
            if (next.i() - current.i() > 1 || next.j() - current.j() > 1) {
                blocks.add(new ChangeBlock(current.i(), current.j(),
                        next.i() - current.i() - 1, next.j() - current.j() - 1));
            }
        }
        return blocks;
    }

    record Step(int oldIndex, int newIndex, ChangeBlock block) {}

    static List<Step> walk(List<ChangeBlock> blocks, int oldStart, int newStart, int oldEnd) {
        List<Step> steps = new ArrayList<>();
        int oldIndex = oldStart;
        int newIndex = newStart;
        for (ChangeBlock block : blocks) {
            while (oldIndex < block.p()) {
                steps.add(new Step(oldIndex++, newIndex++, null));
            }
            steps.add(new Step(oldIndex, newIndex, block));
            oldIndex = block.p() + block.x();
            newIndex = block.q() + block.y();
        }
        while (oldIndex < oldEnd) {
            steps.add(new Step(oldIndex++, newIndex++, null));
        }
        return steps;
    }

    static String sideRow(String left, char symbol, String right, int width) {
        String leftPart = left.substring(0, Math.min(width, left.length()));
        String rightPart = right.substring(0, Math.min(width, right.length()));
        String row = String.format("%-" + width + "s", leftPart) + " " + symbol + " " + rightPart;
        return row.stripTrailing();
    }

    static String statGraph(int inserted, int deleted) {
        int total = inserted + deleted;
        int plus = inserted;
        int minus = deleted;
        if (total > GRAPH_WIDTH) {
            plus = GRAPH_WIDTH * inserted / total;
            minus = GRAPH_WIDTH * deleted / total;
            if (inserted >= 1 && plus == 0) {
                plus = 1;
            }
            if (deleted >= 1 && minus == 0) {
                minus = 1;
            }
        }
        return "+".repeat(plus) + "-".repeat(minus);
    }

    static class Hunk {
        final List<ChangeBlock> blocks;
        final int oldStart;
        final int oldCount;
        final int newStart;
        final int newCount;

        Hunk(List<ChangeBlock> blocks, int context, int oldTotal) {
            ChangeBlock first = blocks.getFirst();
            ChangeBlock last = blocks.getLast();
            int before = Math.min(context, first.p());
            int after = Math.min(context, oldTotal - last.p() - last.x());
            this.blocks = blocks;
            oldStart = first.p() - before;
            oldCount = last.p() + last.x() + after - oldStart;
            newStart = first.q() - before;
            newCount = last.q() + last.y() + after - newStart;
        }

        List<Step> steps() {
            return walk(blocks, oldStart, newStart, oldStart + oldCount);
        }
    }

    static class LineDiff {
        final List<String> oldLines;
        final List<String> newLines;
        final List<ChangeBlock> blocks;

        LineDiff(List<String> oldLines, List<String> newLines, List<String> options) {
            this.oldLines = oldLines;
            this.newLines = newLines;
            blocks = changeBlocks(
                    oldLines.stream().map(line -> comparisonKey(line, options)).toList(),
                    newLines.stream().map(line -> comparisonKey(line, options)).toList());
        }

        LineDiff(List<String> oldLines, List<String> newLines) {
            this(oldLines, newLines, List.of());
        }

        List<String> deleted(ChangeBlock block) {
            return oldLines.subList(block.p(), block.p() + block.x());
        }

        List<String> inserted(ChangeBlock block) {
            return newLines.subList(block.q(), block.q() + block.y());
        }

        List<Hunk> hunks(int context) {
            List<List<ChangeBlock>> groups = new ArrayList<>();
            for (ChangeBlock block : blocks) {
                if (!groups.isEmpty()) {
                    ChangeBlock previous = groups.getLast().getLast();
                    if (block.p() - (previous.p() + previous.x()) <= 2 * context) {
                        groups.getLast().add(block);
                        continue;
                    }
                }
                groups.add(new ArrayList<>(List.of(block)));
            }
            return groups.stream().map(group -> new Hunk(group, context, oldLines.size())).toList();
        }

        List<String> normal() {
            List<String> lines = new ArrayList<>();
            for (ChangeBlock block : blocks) {
                char letter = block.letter();
                lines.add(rangeR(block.p(), block.x()) + letter + rangeR(block.q(), block.y()));
                lines.addAll(prefixed("< ", deleted(block)));
                if (letter == 'c') {
                    lines.add("---");
                }
                lines.addAll(prefixed("> ", inserted(block)));
            }
            return lines;
        }

        List<String> ed() {
            List<String> lines = new ArrayList<>();
            for (ChangeBlock block : blocks.reversed()) {
                char letter = block.letter();
                lines.add(rangeR(block.p(), block.x()) + letter);
                if (letter != 'd') {
                    lines.addAll(inserted(block));
                    lines.add(".");
                }
            }
            return lines;
        }

        List<String> rcs() {
            List<String> lines = new ArrayList<>();
            for (ChangeBlock block : blocks) {
                if (block.x() >= 1) {
                    lines.add("d" + (block.p() + 1) + " " + block.x());
                }
                if (block.y() >= 1) {
                    lines.add("a" + (block.p() + block.x()) + " " + block.y());
                    lines.addAll(inserted(block));
                }
            }
            return lines;
        }

        List<String> ifdef(String macro) {
            List<String> lines = new ArrayList<>();
            for (Step step : walk(blocks, 0, 0, oldLines.size())) {
                ChangeBlock block = step.block();
                if (block == null) {
                    lines.add(oldLines.get(step.oldIndex()));
                } else if (block.x() >= 1 && block.y() >= 1) {
                    lines.add("#ifndef " + macro);
                    lines.addAll(deleted(block));
                    lines.add("#else /* " + macro + " */");
                    lines.addAll(inserted(block));
                    lines.add("#endif /* " + macro + " */");
                } else if (block.y() == 0) {
                    lines.add("#ifndef " + macro);
                    lines.addAll(deleted(block));
                    lines.add("#endif /* ! " + macro + " */");
                } else {
                    lines.add("#ifdef " + macro);
                    lines.addAll(inserted(block));
                    lines.add("#endif /* " + macro + " */");
                }
            }
            return lines;
        }

        List<String> unified(int context, String oldName, String newName) {
            List<String> lines = new ArrayList<>(List.of("--- " + oldName, "+++ " + newName));
            for (Hunk hunk : hunks(context)) {
                String oldRange = rangeU(hunk.oldStart, hunk.oldCount);
                String newRange = rangeU(hunk.newStart, hunk.newCount);
                lines.add("@@ -" + oldRange + " +" + newRange + " @@");
                for (Step step : hunk.steps()) {
                    if (step.block() == null) {
                        lines.add(" " + oldLines.get(step.oldIndex()));
                    } else {
                        lines.addAll(prefixed("-", deleted(step.block())));
                        lines.addAll(prefixed("+", inserted(step.block())));
                    }
                }
            }
            return lines;
        }

        List<String> context(int context, String oldName, String newName) {
            List<String> lines = new ArrayList<>(List.of("*** " + oldName, "--- " + newName));
            for (Hunk hunk : hunks(context)) {
                lines.add("*".repeat(15));
                lines.add("*** " + rangeR(hunk.oldStart, hunk.oldCount) + " ****");
                if (hunk.blocks.stream().anyMatch(block -> block.x() >= 1)) {
                    for (Step step : hunk.steps()) {
                        if (step.block() == null) {
                            lines.add("  " + oldLines.get(step.oldIndex()));
                        } else {
                            String marker = step.block().y() >= 1 ? "! " : "- ";
                            lines.addAll(prefixed(marker, deleted(step.block())));
                        }
                    }
                }
                lines.add("--- " + rangeR(hunk.newStart, hunk.newCount) + " ----");
                if (hunk.blocks.stream().anyMatch(block -> block.y() >= 1)) {
                    for (Step step : hunk.steps()) {
                        if (step.block() == null) {
                            lines.add("  " + newLines.get(step.newIndex()));
                        } else {
                            String marker = step.block().x() >= 1 ? "! " : "+ ";
                            lines.addAll(prefixed(marker, inserted(step.block())));
                        }
                    }
                }
            }
            return lines;
        }

        List<String> sideBySide(int width) {
            List<String> lines = new ArrayList<>();
            for (Step step : walk(blocks, 0, 0, oldLines.size())) {
                ChangeBlock block = step.block();
                if (block == null) {
                    String left = oldLines.get(step.oldIndex());
                    lines.add(sideRow(left, ' ', newLines.get(step.newIndex()), width));
                    continue;
                }
                for (int row = 0; row < Math.max(block.x(), block.y()); row++) {
                    if (row < block.x() && row < block.y()) {
                        String left = oldLines.get(block.p() + row);
                        lines.add(sideRow(left, '|', newLines.get(block.q() + row), width));
                    } else if (row < block.x()) {
                        lines.add(sideRow(oldLines.get(block.p() + row), '<', "", width));
                    } else {
                        lines.add(sideRow("", '>', newLines.get(block.q() + row), width));
                    }
                }
            }
            return lines;
        }
    }

    static class TokenTotals {
        int deleted;
        int inserted;
        int common;
    }

    static List<String> splitTokens(String line, boolean byWord) {
        if (byWord) {
            return List.of(line.split(" +"));
        }
        return line.chars().mapToObj(Character::toString).toList();
    }

    static String deletion(List<String> tokens, String separator) {
        return "[-" + String.join(separator, tokens) + "-]";
    }

    static String insertion(List<String> tokens, String separator) {
        return "{+" + String.join(separator, tokens) + "+}";
    }

    static String compareTokens(List<String> oldTokens, List<String> newTokens, String separator,
            TokenTotals totals) {
        List<String> parts = new ArrayList<>();
        for (Step step : walk(changeBlocks(oldTokens, newTokens), 0, 0, oldTokens.size())) {
            ChangeBlock block = step.block();
            if (block == null) {
                parts.add(oldTokens.get(step.oldIndex()));
                totals.common++;
                continue;
            }
            if (block.x() >= 1) {
                List<String> tokens = oldTokens.subList(block.p(), block.p() + block.x());
                parts.add(deletion(tokens, separator));
            }
            if (block.y() >= 1) {
                List<String> tokens = newTokens.subList(block.q(), block.q() + block.y());
                parts.add(insertion(tokens, separator));
            }
            totals.deleted += block.x();
            totals.inserted += block.y();
        }
        return String.join(separator, parts);
    }

    record Range(int start, int count) {}

    record BodyLine(char kind, String text) {}

    record Sequences(List<String> oldLines, List<String> newLines) {}

    record PatchHunk(int lineNumber, Range oldRange, Range newRange, List<BodyLine> body) {
        Sequences sequences(boolean reverse) {
            char oldKind = reverse ? '+' : '-';
            char newKind = reverse ? '-' : '+';
            List<String> oldLines = new ArrayList<>();
            List<String> newLines = new ArrayList<>();
            for (BodyLine line : body) {
                if (line.kind() == ' ' || line.kind() == oldKind) {
                    oldLines.add(line.text());
                }
                if (line.kind() == ' ' || line.kind() == newKind) {
                    newLines.add(line.text());
                }
            }
            return new Sequences(oldLines, newLines);
        }

        int start(boolean reverse) {
            return reverse ? newRange.start() : oldRange.start();
        }

        int leadingContext() {
            int count = 0;
            while (count < body.size() && body.get(count).kind() == ' ') {
                count++;
            }
            return count;
        }

        int trailingContext() {
            int count = 0;
            while (count < body.size() && body.get(body.size() - 1 - count).kind() == ' ') {
                count++;
            }
            return count;
        }
    }

    record HunkMatch(int fuzz, int delta, int position, List<String> lines) {
        String report(int number) {
            String text = "Hunk #" + number + " succeeded at " + (position + 1);
            if (fuzz >= 1) {
                text += " with fuzz " + fuzz;
            }
            if (delta == 1 || delta == -1) {
                text += " (offset " + delta + " line)";
            } else if (delta != 0) {
                text += " (offset " + delta + " lines)";
            }
            return text;
        }
    }

    static Optional<Range> parseRange(String text, char sign) {
        if (text.isEmpty() || text.charAt(0) != sign) {
            return Optional.empty();
        }
        Matcher match = NUMBER_PAIR.matcher(text.substring(1));
        if (!match.matches()) {
            return Optional.empty();
        }
        int start = Integer.parseInt(match.group(1));
        int count = match.group(2) == null ? 1 : Integer.parseInt(match.group(2));
        if (start == 0 && count != 0) {
            return Optional.empty();
        }
        return Optional.of(new Range(start, count));
    }

    static PatchHunk parseHunkHeader(String line, int lineNumber) {
        String[] parts = line.split(" ", -1);
        if (parts.length == 4 && parts[0].equals("@@") && parts[3].equals("@@")) {
            Optional<Range> oldRange = parseRange(parts[1], '-');
            Optional<Range> newRange = parseRange(parts[2], '+');
            if (oldRange.isPresent() && newRange.isPresent()) {
                return new PatchHunk(lineNumber, oldRange.get(), newRange.get(), new ArrayList<>());
            }
        }
        throw new CommandError("PATCH ERROR line " + lineNumber + ": bad hunk header");
    }

    static List<PatchHunk> parsePatch(List<String> patchLines) {
        int index = 0;
        while (index < patchLines.size() && !patchLines.get(index).startsWith("@@")) {
            index++;
        }
        if (index == patchLines.size()) {
            throw new CommandError("PATCH ERROR no hunks");
        }
        List<PatchHunk> hunks = new ArrayList<>();
        while (index < patchLines.size()) {
            PatchHunk hunk = parseHunkHeader(patchLines.get(index), index + 1);
            index++;
            int oldCount = hunk.oldRange().count();
            int newCount = hunk.newRange().count();
            int oldSeen = 0;
            int newSeen = 0;
            while (oldSeen < oldCount || newSeen < newCount) {
                if (index == patchLines.size()) {
                    throw new CommandError(
                            "PATCH ERROR line " + hunk.lineNumber() + ": truncated hunk");
                }
                String line = patchLines.get(index);
                char kind = line.charAt(0);
                boolean inOld = kind == ' ' || kind == '-';
                boolean inNew = kind == ' ' || kind == '+';
                if (line.length() < 2
                        || !(inOld || inNew)
                        || (inOld && oldSeen == oldCount)
                        || (inNew && newSeen == newCount)) {
                    throw new CommandError("PATCH ERROR line " + (index + 1) + ": bad hunk line");
                }
                hunk.body().add(new BodyLine(kind, line.substring(1)));
                if (inOld) {
                    oldSeen++;
                }
                if (inNew) {
                    newSeen++;
                }
                index++;
            }
            if (hunk.body().stream().allMatch(line -> line.kind() == ' ')) {
                throw new CommandError("PATCH ERROR line " + hunk.lineNumber() + ": no changes");
            }
            hunks.add(hunk);
        }
        return hunks;
    }

    static Optional<HunkMatch> searchHunk(PatchHunk hunk, List<String> lines, int adjustment,
            boolean reverse, int maxFuzz) {
        Sequences sequences = hunk.sequences(reverse);
        List<String> oldLines = sequences.oldLines();
        List<String> newLines = sequences.newLines();
        int start = hunk.start(reverse);
        int expected = oldLines.isEmpty() ? start + adjustment : start - 1 + adjustment;
        int leading = hunk.leadingContext();
        int trailing = hunk.trailingContext();
        for (int fuzz = 0; fuzz <= maxFuzz; fuzz++) {
            int head = Math.min(fuzz, leading);
            int tail = Math.min(fuzz, trailing);
            List<String> oldPart = oldLines.subList(head, oldLines.size() - tail);
            List<String> newPart = newLines.subList(head, newLines.size() - tail);
            for (int delta : OFFSETS) {
                int position = expected + head + delta;
                int end = position + oldPart.size();
                if (position < 0 || end > lines.size()) {
                    continue;
                }
                if (lines.subList(position, end).equals(oldPart)) {
                    List<String> result = new ArrayList<>(lines.subList(0, position));
                    result.addAll(newPart);
                    result.addAll(lines.subList(end, lines.size()));
                    return Optional.of(new HunkMatch(fuzz, delta, position, result));
                }
            }
        }
        return Optional.empty();
    }

    record EditCommand(char instruction, int first, int last) {}

    record EditResult(List<String> lines, int executed) {}

    static Optional<EditCommand> parseEditCommand(String line) {
        char instruction = line.charAt(line.length() - 1);
        Matcher match = NUMBER_PAIR.matcher(line.substring(0, line.length() - 1));
        if ("acd".indexOf(instruction) < 0 || !match.matches()) {
            return Optional.empty();
        }
        if (instruction == 'a' && match.group(2) != null) {
            return Optional.empty();
        }
        int first = Integer.parseInt(match.group(1));
        int last = match.group(2) == null ? first : Integer.parseInt(match.group(2));
        return Optional.of(new EditCommand(instruction, first, last));
    }

    static EditResult runEditScript(List<String> original, List<String> script) {
        List<String> lines = new ArrayList<>(original);
        int executed = 0;
        int index = 0;
        while (index < script.size()) {
            int lineNumber = index + 1;
            EditCommand command = parseEditCommand(script.get(index)).orElseThrow(
                    () -> new CommandError("EDIT ERROR line " + lineNumber + ": bad command"));
            char instruction = command.instruction();
            int first = command.first();
            int last = command.last();
            boolean valid = instruction == 'a'
                    ? first <= lines.size()
                    : 1 <= first && first <= last && last <= lines.size();
            if (!valid) {
                throw new CommandError("EDIT ERROR line " + lineNumber + ": bad range");
            }
            index++;
            List<String> text = List.of();
            if (instruction == 'a' || instruction == 'c') {
                int end = index;
                while (end < script.size() && !script.get(end).equals(".")) {
                    end++;
                }
                if (end == script.size()) {
                    throw new CommandError(
                            "EDIT ERROR line " + lineNumber + ": missing terminator");
                }
                text = script.subList(index, end);
                index = end + 1;
            }
            if (instruction == 'a') {
                lines.addAll(first, text);
            } else {
                lines.subList(first - 1, last).clear();
                lines.addAll(first - 1, text);
            }
            executed++;
        }
        return new EditResult(lines, executed);
    }

    enum ChunkKind {
        STABLE, A, B, BOTH, CONFLICT;

        String label() {
            return name().toLowerCase(Locale.ROOT);
        }
    }

    record Chunk(ChunkKind kind, int baseStart, int oursStart, int theirsStart,
            List<String> base, List<String> ours, List<String> theirs) {
        String location() {
            return "base " + rangeM(baseStart, base.size())
                    + " a " + rangeM(oursStart, ours.size())
                    + " b " + rangeM(theirsStart, theirs.size());
        }
    }

    static ChunkKind chunkKind(List<String> base, List<String> ours, List<String> theirs) {
        if (ours.equals(base)) {
            return ChunkKind.B;
        }
        if (theirs.equals(base)) {
            return ChunkKind.A;
        }
        if (ours.equals(theirs)) {
            return ChunkKind.BOTH;
        }
        return ChunkKind.CONFLICT;
    }

    static int[] matchTable(List<String> first, List<String> second) {
        int[] matches = new int[first.size() + 2];
        List<LinePair> pairs = matchedPairs(first, second);
        for (LinePair pair : pairs.subList(1, pairs.size() - 1)) {
            matches[pair.i()] = pair.j();
        }
        return matches;
    }

    static List<Chunk> threeWayChunks(List<String> base, List<String> ours, List<String> theirs) {
        int[] oursMatch = matchTable(base, ours);
        int[] theirsMatch = matchTable(base, theirs);
        List<Chunk> chunks = new ArrayList<>();
        int x = 0;
        int y = 0;
        int z = 0;
        while (x < base.size() || y < ours.size() || z < theirs.size()) {
            if (x < base.size() && oursMatch[x + 1] == y + 1 && theirsMatch[x + 1] == z + 1) {
                List<String> line = base.subList(x, x + 1);
                chunks.add(new Chunk(ChunkKind.STABLE, x, y, z, line, line, line));
                x++;
                y++;
                z++;
                continue;
            }
            int anchor = x + 1;
            while (anchor <= base.size() && (oursMatch[anchor] == 0 || theirsMatch[anchor] == 0)) {
                anchor++;
            }
            int nextX = base.size();
            int nextY = ours.size();
            int nextZ = theirs.size();
            if (anchor <= base.size()) {
                nextX = anchor - 1;
                nextY = oursMatch[anchor] - 1;
                nextZ = theirsMatch[anchor] - 1;
            }
            List<String> basePart = base.subList(x, nextX);
            List<String> oursPart = ours.subList(y, nextY);
            List<String> theirsPart = theirs.subList(z, nextZ);
            ChunkKind kind = chunkKind(basePart, oursPart, theirsPart);
            chunks.add(new Chunk(kind, x, y, z, basePart, oursPart, theirsPart));
            x = nextX;
            y = nextY;
            z = nextZ;
        }
        return chunks;
    }

    static long countKind(List<Chunk> chunks, ChunkKind kind) {
        return chunks.stream().filter(chunk -> chunk.kind() == kind).count();
    }

    static String kindCounts(List<Chunk> chunks) {
        return "a=" + countKind(chunks, ChunkKind.A)
                + " b=" + countKind(chunks, ChunkKind.B)
                + " both=" + countKind(chunks, ChunkKind.BOTH)
                + " conflicts=" + countKind(chunks, ChunkKind.CONFLICT);
    }

    static int commonPrefixLength(List<String> first, List<String> second) {
        int length = 0;
        while (length < first.size() && length < second.size()
                && first.get(length).equals(second.get(length))) {
            length++;
        }
        return length;
    }

    static int commonSuffixLength(List<String> first, List<String> second, int limit) {
        int length = 0;
        while (length < limit && first.get(first.size() - 1 - length)
                .equals(second.get(second.size() - 1 - length))) {
            length++;
        }
        return length;
    }

    static List<String> conflictLines(Chunk chunk, String mode, String baseName, String oursName,
            String theirsName) {
        if (mode.equals("OURS")) {
            return chunk.ours();
        }
        if (mode.equals("THEIRS")) {
            return chunk.theirs();
        }
        List<String> lines = new ArrayList<>();
        if (mode.equals("DIFF3")) {
            lines.add("<<<<<<< " + oursName);
            lines.addAll(chunk.ours());
            lines.add("||||||| " + baseName);
            lines.addAll(chunk.base());
            lines.add(SEPARATOR);
            lines.addAll(chunk.theirs());
            lines.add(">>>>>>> " + theirsName);
            return lines;
        }
        List<String> ours = chunk.ours();
        List<String> theirs = chunk.theirs();
        int head = commonPrefixLength(ours, theirs);
        int tail = commonSuffixLength(ours, theirs, Math.min(ours.size(), theirs.size()) - head);
        List<String> oursMiddle = ours.subList(head, ours.size() - tail);
        List<String> theirsMiddle = theirs.subList(head, theirs.size() - tail);
        lines.addAll(ours.subList(0, head));
        if (mode.equals("UNION")) {
            lines.addAll(oursMiddle);
            lines.addAll(theirsMiddle);
        } else {
            lines.add("<<<<<<< " + oursName);
            lines.addAll(oursMiddle);
            lines.add(SEPARATOR);
            lines.addAll(theirsMiddle);
            lines.add(">>>>>>> " + theirsName);
        }
        lines.addAll(ours.subList(ours.size() - tail, ours.size()));
        return lines;
    }

    enum Marker { NONE, START, BASE, SEPARATOR, END }

    static Marker markerKind(String line) {
        if (line.equals(SEPARATOR)) {
            return Marker.SEPARATOR;
        }
        String prefix = line.substring(0, Math.min(7, line.length()));
        Marker marker = MARKER_PREFIXES.getOrDefault(prefix, Marker.NONE);
        if (marker != Marker.NONE && (line.length() == 7 || line.charAt(7) == ' ')) {
            return marker;
        }
        return Marker.NONE;
    }

    static int nextMarker(List<String> lines, int index) {
        index++;
        while (index < lines.size() && markerKind(lines.get(index)) == Marker.NONE) {
            index++;
        }
        return index;
    }

    record ConflictRegion(int start, int end, List<String> ours, List<String> base,
            List<String> theirs) {
        List<String> part(String side) {
            return switch (side) {
                case "OURS" -> ours;
                case "THEIRS" -> theirs;
                case "BASE" -> base;
                default -> Stream.concat(ours.stream(), theirs.stream()).toList();
            };
        }
    }

    static Optional<ConflictRegion> regionAt(List<String> lines, int start) {
        if (markerKind(lines.get(start)) != Marker.START) {
            return Optional.empty();
        }
        int middle = nextMarker(lines, start);
        int baseMarker = -1;
        if (middle < lines.size() && markerKind(lines.get(middle)) == Marker.BASE) {
            baseMarker = middle;
            middle = nextMarker(lines, middle);
        }
        if (middle == lines.size() || markerKind(lines.get(middle)) != Marker.SEPARATOR) {
            return Optional.empty();
        }
        int end = nextMarker(lines, middle);
        if (end == lines.size() || markerKind(lines.get(end)) != Marker.END) {
            return Optional.empty();
        }
        List<String> theirs = lines.subList(middle + 1, end);
        if (baseMarker < 0) {
            List<String> ours = lines.subList(start + 1, middle);
            return Optional.of(new ConflictRegion(start + 1, end + 1, ours, null, theirs));
        }
        List<String> ours = lines.subList(start + 1, baseMarker);
        List<String> base = lines.subList(baseMarker + 1, middle);
        return Optional.of(new ConflictRegion(start + 1, end + 1, ours, base, theirs));
    }

    static List<ConflictRegion> conflictRegions(List<String> lines) {
        List<ConflictRegion> regions = new ArrayList<>();
        int index = 0;
        while (index < lines.size()) {
            Optional<ConflictRegion> region = regionAt(lines, index);
            if (region.isPresent()) {
                regions.add(region.get());
                index = region.get().end();
            } else {
                index++;
            }
        }
        return regions;
    }

    static class Workspace {
        private final Map<String, List<String>> files = new TreeMap<>();
        private final Map<String, List<List<String>>> history = new HashMap<>();
        private final StringBuilder output = new StringBuilder();

        String output() {
            return output.toString();
        }

        void execute(List<String> words, List<String> data) {
            List<String> arguments = words.subList(1, words.size());
            try {
                switch (words.getFirst()) {
                    case "FILE" -> loadFile(arguments, data);
                    case "COPY" -> copy(arguments);
                    case "PRINT" -> printFile(arguments);
                    case "FILES" -> listFiles();
                    case "DIFF" -> diff(arguments);
                    case "WORDDIFF" -> tokenDiff(arguments, true);
                    case "CHARDIFF" -> tokenDiff(arguments, false);
                    case "STAT" -> stat(arguments);
                    case "PATCH" -> patch(arguments, data);
                    case "EDIT" -> edit(arguments, data);
                    case "DIFF3" -> diff3(arguments);
                    case "MERGE" -> merge(arguments);
                    case "CONFLICTS" -> conflicts(arguments);
                    case "RESOLVE" -> resolve(arguments);
                    case "UNDO" -> undo(arguments);
                }
            } catch (CommandError error) {
                emit(error.getMessage());
            }
        }

        private void emit(String line) {
            output.append(line).append('\n');
        }

        private void emitAll(List<String> lines) {
            lines.forEach(this::emit);
        }

        private void require(String... names) {
            for (String name : names) {
                if (!files.containsKey(name)) {
                    throw new CommandError("ERROR no such file " + name);
                }
            }
        }

        private void save(String name, List<String> lines) {
            history.computeIfAbsent(name, key -> new ArrayList<>()).add(files.get(name));
            files.put(name, List.copyOf(lines));
        }

        private void loadFile(List<String> arguments, List<String> data) {
            String name = arguments.getFirst();
            save(name, data);
            emit("FILE " + name + " lines=" + data.size());
        }

        private void copy(List<String> arguments) {
            String source = arguments.get(0);
            String target = arguments.get(1);
            require(source);
            List<String> lines = files.get(source);
            save(target, lines);
            emit("COPY " + source + " " + target + " lines=" + lines.size());
        }

        private void printFile(List<String> arguments) {
            String name = arguments.getFirst();
            require(name);
            List<String> lines = files.get(name);
            emit("PRINT " + name + " lines=" + lines.size());
            for (int number = 1; number <= lines.size(); number++) {
                emit(String.format("%3d| %s", number, lines.get(number - 1)));
            }
        }

        private void listFiles() {
            emit("FILES count=" + files.size());
            files.forEach((name, lines) ->
                    emit(name + " lines=" + lines.size() + " undo=" + history.get(name).size()));
        }

        private void undo(List<String> arguments) {
            String name = arguments.getFirst();
            List<List<String>> states = history.getOrDefault(name, List.of());
            if (states.isEmpty()) {
                throw new CommandError("ERROR nothing to undo " + name);
            }
            List<String> state = states.removeLast();
            if (state == null) {
                files.remove(name);
                emit("UNDO " + name + " removed");
            } else {
                files.put(name, state);
                emit("UNDO " + name + " lines=" + state.size());
            }
        }

        private void diff(List<String> arguments) {
            String oldName = arguments.get(0);
            String newName = arguments.get(1);
            String form = arguments.get(2);
            require(oldName, newName);
            boolean hasParameter = FORMATS_WITH_ARGUMENT.contains(form);
            String parameter = hasParameter ? arguments.get(3) : "";
            List<String> options = arguments.subList(hasParameter ? 4 : 3, arguments.size());
            LineDiff diff = new LineDiff(files.get(oldName), files.get(newName), options);
            if (diff.blocks.isEmpty()) {
                emit("Files " + oldName + " and " + newName + " are identical");
                return;
            }
            switch (form) {
                case "BRIEF" -> emit("Files " + oldName + " and " + newName + " differ");
                case "NORMAL" -> emitAll(diff.normal());
                case "ED" -> emitAll(diff.ed());
                case "RCS" -> emitAll(diff.rcs());
                case "IFDEF" -> emitAll(diff.ifdef(parameter));
                case "UNIFIED" ->
                        emitAll(diff.unified(Integer.parseInt(parameter), oldName, newName));
                case "CONTEXT" ->
                        emitAll(diff.context(Integer.parseInt(parameter), oldName, newName));
                default -> emitAll(diff.sideBySide(Integer.parseInt(parameter)));
            }
        }

        private void tokenDiff(List<String> arguments, boolean byWord) {
            String oldName = arguments.get(0);
            String newName = arguments.get(1);
            require(oldName, newName);
            List<String> oldLines = files.get(oldName);
            List<String> newLines = files.get(newName);
            LineDiff diff = new LineDiff(oldLines, newLines);
            if (diff.blocks.isEmpty()) {
                emit("Files " + oldName + " and " + newName + " are identical");
                return;
            }
            String separator = byWord ? " " : "";
            TokenTotals totals = new TokenTotals();
            for (ChangeBlock block : diff.blocks) {
                for (int row = 0; row < Math.max(block.x(), block.y()); row++) {
                    int oldNumber = block.p() + row + 1;
                    int newNumber = block.q() + row + 1;
                    if (row < block.x() && row < block.y()) {
                        List<String> oldTokens = splitTokens(oldLines.get(oldNumber - 1), byWord);
                        List<String> newTokens = splitTokens(newLines.get(newNumber - 1), byWord);
                        String text = compareTokens(oldTokens, newTokens, separator, totals);
                        emit("a" + oldNumber + " b" + newNumber + ": " + text);
                    } else if (row < block.x()) {
                        List<String> oldTokens = splitTokens(oldLines.get(oldNumber - 1), byWord);
                        totals.deleted += oldTokens.size();
                        emit("a" + oldNumber + ": " + deletion(oldTokens, separator));
                    } else {
                        List<String> newTokens = splitTokens(newLines.get(newNumber - 1), byWord);
                        totals.inserted += newTokens.size();
                        emit("b" + newNumber + ": " + insertion(newTokens, separator));
                    }
                }
            }
            String label = byWord ? "WORDS" : "CHARS";
            emit(label + " deleted=" + totals.deleted + " inserted=" + totals.inserted
                    + " common=" + totals.common);
        }

        private void stat(List<String> arguments) {
            String oldName = arguments.get(0);
            String newName = arguments.get(1);
            require(oldName, newName);
            List<String> oldLines = files.get(oldName);
            List<String> newLines = files.get(newName);
            LineDiff diff =
                    new LineDiff(oldLines, newLines, arguments.subList(2, arguments.size()));
            int deleted = diff.blocks.stream().mapToInt(ChangeBlock::x).sum();
            int inserted = diff.blocks.stream().mapToInt(ChangeBlock::y).sum();
            int total = deleted + inserted;
            int unchanged = oldLines.size() - deleted;
            String summary = oldName + " -> " + newName + " | " + total;
            if (total > 0) {
                summary += " " + statGraph(inserted, deleted);
            }
            emit(summary);
            int lineTotal = oldLines.size() + newLines.size();
            int similarity = lineTotal > 0 ? 200 * unchanged / lineTotal : 100;
            emit("changes=" + diff.blocks.size() + " insertions=" + inserted
                    + " deletions=" + deleted + " unchanged=" + unchanged
                    + " similarity=" + similarity + "%");
        }

        private void patch(List<String> arguments, List<String> data) {
            String name = arguments.getFirst();
            require(name);
            List<String> options = arguments.subList(2, arguments.size());
            boolean reverse = options.contains("REVERSE");
            boolean dryRun = options.contains("DRYRUN");
            int fuzzIndex = options.indexOf("FUZZ");
            int maxFuzz = fuzzIndex < 0 ? 0 : Integer.parseInt(options.get(fuzzIndex + 1));
            List<PatchHunk> hunks = parsePatch(data);
            emit((dryRun ? "checking file " : "patching file ") + name);
            List<String> lines = files.get(name);
            PatchHunk first = hunks.getFirst();
            if (searchHunk(first, lines, 0, reverse, maxFuzz).isEmpty()
                    && searchHunk(first, lines, 0, !reverse, maxFuzz).isPresent()) {
                emit("Reversed (or previously applied) patch detected! Skipping patch.");
                emit("RESULT applied=0 failed=0 ignored=" + hunks.size()
                        + " lines=" + lines.size());
                return;
            }
            int adjustment = 0;
            int applied = 0;
            int failed = 0;
            for (int number = 1; number <= hunks.size(); number++) {
                PatchHunk hunk = hunks.get(number - 1);
                Optional<HunkMatch> match = searchHunk(hunk, lines, adjustment, reverse, maxFuzz);
                if (match.isEmpty()) {
                    failed++;
                    emit("Hunk #" + number + " FAILED at " + hunk.start(reverse));
                    continue;
                }
                Sequences sequences = hunk.sequences(reverse);
                lines = match.get().lines();
                adjustment += match.get().delta() + sequences.newLines().size()
                        - sequences.oldLines().size();
                applied++;
                emit(match.get().report(number));
            }
            emit("RESULT applied=" + applied + " failed=" + failed
                    + " ignored=0 lines=" + lines.size());
            if (!dryRun && applied >= 1) {
                save(name, lines);
            }
        }

        private void edit(List<String> arguments, List<String> data) {
            String name = arguments.getFirst();
            require(name);
            EditResult result = runEditScript(files.get(name), data);
            emit("EDIT " + name + " commands=" + result.executed()
                    + " lines=" + result.lines().size());
            save(name, result.lines());
        }

        private List<Chunk> threeWay(String baseName, String oursName, String theirsName) {
            require(baseName, oursName, theirsName);
            return threeWayChunks(files.get(baseName), files.get(oursName), files.get(theirsName));
        }

        private void diff3(List<String> arguments) {
            List<Chunk> chunks = threeWay(arguments.get(0), arguments.get(1), arguments.get(2));
            List<Chunk> changes =
                    chunks.stream().filter(chunk -> chunk.kind() != ChunkKind.STABLE).toList();
            for (Chunk chunk : changes) {
                emit("==== " + chunk.kind().label() + " " + chunk.location());
                emitAll(prefixed("O ", chunk.base()));
                if (chunk.kind() != ChunkKind.B) {
                    emitAll(prefixed("A ", chunk.ours()));
                }
                if (chunk.kind() == ChunkKind.B || chunk.kind() == ChunkKind.CONFLICT) {
                    emitAll(prefixed("B ", chunk.theirs()));
                }
            }
            emit("DIFF3 chunks=" + changes.size() + " " + kindCounts(chunks));
        }

        private void merge(List<String> arguments) {
            String baseName = arguments.get(0);
            String oursName = arguments.get(1);
            String theirsName = arguments.get(2);
            String target = arguments.get(3);
            String mode = arguments.size() == 5 ? arguments.get(4) : "MARKERS";
            List<Chunk> chunks = threeWay(baseName, oursName, theirsName);
            List<String> result = new ArrayList<>();
            List<Chunk> conflicts = new ArrayList<>();
            for (Chunk chunk : chunks) {
                switch (chunk.kind()) {
                    case B -> result.addAll(chunk.theirs());
                    case CONFLICT -> {
                        result.addAll(conflictLines(chunk, mode, baseName, oursName, theirsName));
                        conflicts.add(chunk);
                    }
                    default -> result.addAll(chunk.ours());
                }
            }
            emit("MERGE " + target + " lines=" + result.size() + " " + kindCounts(chunks));
            for (int number = 1; number <= conflicts.size(); number++) {
                emit("CONFLICT " + number + " " + conflicts.get(number - 1).location());
            }
            save(target, result);
        }

        private void conflicts(List<String> arguments) {
            String name = arguments.getFirst();
            require(name);
            List<ConflictRegion> regions = conflictRegions(files.get(name));
            emit("CONFLICTS " + name + " count=" + regions.size());
            for (int number = 1; number <= regions.size(); number++) {
                ConflictRegion region = regions.get(number - 1);
                String base = region.base() == null ? "none" : String.valueOf(region.base().size());
                emit(number + ": lines " + region.start() + "-" + region.end()
                        + " ours=" + region.ours().size() + " base=" + base
                        + " theirs=" + region.theirs().size());
            }
        }

        private void resolve(List<String> arguments) {
            String name = arguments.get(0);
            String side = arguments.get(2);
            require(name);
            int number = Integer.parseInt(arguments.get(1));
            List<String> lines = files.get(name);
            List<ConflictRegion> regions = conflictRegions(lines);
            if (regions.size() < number) {
                throw new CommandError("ERROR no conflict " + number + " in " + name);
            }
            ConflictRegion region = regions.get(number - 1);
            if (side.equals("BASE") && region.base() == null) {
                throw new CommandError("ERROR no base section in conflict " + number);
            }
            List<String> content = new ArrayList<>(lines.subList(0, region.start() - 1));
            content.addAll(region.part(side));
            content.addAll(lines.subList(region.end(), lines.size()));
            int remaining = conflictRegions(content).size();
            emit("RESOLVE " + name + " " + number + " " + side + " lines=" + content.size()
                    + " remaining=" + remaining);
            save(name, content);
        }
    }

    public static void main(String[] args) {
        List<String> lines = new BufferedReader(new InputStreamReader(System.in)).lines().toList();
        Workspace workspace = new Workspace();
        int position = 1;
        int commandCount = Integer.parseInt(lines.getFirst());
        for (int command = 0; command < commandCount; command++) {
            List<String> words = List.of(lines.get(position).split(" "));
            position++;
            List<String> data = List.of();
            if (DATA_COMMANDS.contains(words.getFirst())) {
                int count = Integer.parseInt(words.get(2));
                data = lines.subList(position, position + count);
                position += count;
            }
            workspace.execute(words, data);
        }
        System.out.print(workspace.output());
    }
}
