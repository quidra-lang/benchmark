import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    static final List<String> LEVELS = List.of("L", "M", "Q", "H"),
                              MODES = List.of("NUMERIC", "ALPHANUMERIC", "BYTE"),
                              ERROR_KINDS = List.of("level", "mode", "version", "mask", "text",
                                                    "charset", "capacity");
    record Segment(String mode, String text) {}
    record Split(List<Segment> segments, int bits) {}
    record Group(int value, int width, String text) {}
    record Assembled(String bits, List<String> lines) {}
    record Padding(String bits, int terminator, int zeroFill, int padBytes) {}
    record Placement(int block, int position) {}
    record BlockResult(String status, int positions) {}
    record Scan(String name, int[][] symbol) {}
    record Damage(String operation, int[] arguments) {}
    record Image(int[][] symbol, String line) {}
    record Damaged(int[][] symbol, List<String> lines) {}
    static int countWidth(String mode, int version) {
        return (version == 10 ? new int[] {12, 11, 16} : new int[] {10, 9, 8})[MODES.indexOf(mode)];
    }
    static int dataWidth(String mode, int count) {
        return switch (mode) {
            case "NUMERIC" -> 10 * (count / 3) + new int[] {0, 4, 7}[count % 3];
            case "ALPHANUMERIC" -> 11 * (count / 2) + 6 * (count % 2);
            default -> 8 * count;
        };
    }
    static int indicator(String mode) { return new int[] {1, 2, 4}[MODES.indexOf(mode)]; }
    static boolean encodable(String mode, char character) {
        return switch (mode) {
            case "NUMERIC" -> character >= '0' && character <= '9';
            case "ALPHANUMERIC" -> Bitstream.ALPHANUMERIC.indexOf(character) >= 0;
            default -> character >= 32 && character <= 126;
        };
    }
    static boolean encodable(String mode, String text) {
        for (int i = 0; i < text.length(); i++)
            if (!encodable(mode, text.charAt(i)))
                return false;
        return true;
    }
    static int segmentWidth(String mode, String text, int version) {
        return 4 + countWidth(mode, version) + dataWidth(mode, text.length());
    }
    static List<Group> groups(String mode, String text) {
        int step = switch (mode) {
            case "NUMERIC" -> 3;
            case "ALPHANUMERIC" -> 2;
            default -> 1;
        };
        List<Group> groups = new ArrayList<>();
        for (int start = 0; start < text.length(); start += step) {
            String characters = text.substring(start, Math.min(start + step, text.length()));
            int value, width;
            if (mode.equals("NUMERIC")) {
                value = Integer.parseInt(characters);
                width = new int[] {0, 4, 7, 10}[characters.length()];
            } else if (mode.equals("ALPHANUMERIC")) {
                value = Bitstream.ALPHANUMERIC.indexOf(characters.charAt(0));
                width = 6;
                if (characters.length() == 2) {
                    value = 45 * value + Bitstream.ALPHANUMERIC.indexOf(characters.charAt(1));
                    width = 11;
                }
            } else {
                value = characters.charAt(0);
                width = 8;
            }
            groups.add(new Group(value, width, characters));
        }
        return groups;
    }
    static Split mixedSegments(String text, int version) {
        int length = text.length();
        int[][] invalid = new int[3][length + 1];
        for (int i = 0; i < length; i++)
            for (int m = 0; m < 3; m++)
                invalid[m][i + 1] =
                    invalid[m][i] + (encodable(MODES.get(m), text.charAt(i)) ? 0 : 1);
        int[] costs = new int[length + 1], starts = new int[length + 1],
              modes = new int[length + 1];
        for (int end = 1; end <= length; end++) {
            costs[end] = Integer.MAX_VALUE;
            for (int start = 0; start < end; start++)
                for (int m = 0; m < 3; m++)
                    if (invalid[m][end] == invalid[m][start]) {
                        String mode = MODES.get(m);
                        int cost = costs[start] + 4 + countWidth(mode, version) +
                                   dataWidth(mode, end - start);
                        if (cost < costs[end]) {
                            costs[end] = cost;
                            starts[end] = start;
                            modes[end] = m;
                        }
                    }
        }
        List<Segment> segments = new ArrayList<>();
        for (int end = length; end > 0; end = starts[end])
            segments.add(new Segment(MODES.get(modes[end]), text.substring(starts[end], end)));
        Collections.reverse(segments);
        return new Split(segments, costs[length]);
    }
    static Assembled assembleBits(List<Segment> segments, int version) {
        Bitstream.Writer writer = new Bitstream.Writer();
        List<String> lines = new ArrayList<>();
        for (Segment segment : segments) {
            String mode = segment.mode(), text = segment.text();
            int width = countWidth(mode, version), indicator = indicator(mode);
            writer.write(indicator, 4);
            writer.write(text.length(), width);
            lines.add("segment " + mode + " indicator " + Bitstream.binary(indicator, 4) +
                      " count " + text.length() + " " + Bitstream.binary(text.length(), width));
            for (Group group : groups(mode, text)) {
                writer.write(group.value(), group.width());
                lines.add("group " + group.value() + " " +
                          Bitstream.binary(group.value(), group.width()) + " \"" + group.text() +
                          "\"");
            }
        }
        return new Assembled(writer.value(), lines);
    }
    static Padding padBits(String bits, int capacity) {
        int terminator = Math.min(4, capacity - bits.length());
        String padded = bits + "0".repeat(terminator);
        int zeroFill = (8 - padded.length() % 8) % 8;
        padded += "0".repeat(zeroFill);
        int padBytes = (capacity - padded.length()) / 8;
        StringBuilder result = new StringBuilder(padded);
        for (int i = 0; i < padBytes; i++)
            result.append(i % 2 == 0 ? "11101100" : "00010001");
        return new Padding(result.toString(), terminator, zeroFill, padBytes);
    }
    static final class BlockLayout {
        int degree, count, data, capacity, total;
        int[] lengths;
        List<Placement> placement = new ArrayList<>();
        BlockLayout(int degree, int firstCount, int firstSize, int secondCount, int secondSize) {
            this.degree = degree;
            count = firstCount + secondCount;
            lengths = new int[count];
            for (int i = 0; i < count; i++) {
                lengths[i] = i < firstCount ? firstSize : secondSize;
                data += lengths[i];
            }
            capacity = 8 * data;
            total = data + degree * count;
            for (int position = 0; position < Math.max(firstSize, secondSize); position++)
                for (int block = 0; block < count; block++)
                    if (position < lengths[block])
                        placement.add(new Placement(block, position));
            for (int offset = 0; offset < degree; offset++)
                for (int block = 0; block < count; block++)
                    placement.add(new Placement(block, lengths[block] + offset));
        }
        int[][] encode(int[] data) {
            int[][] blocks = new int[count][];
            int start = 0;
            for (int b = 0; b < count; b++) {
                int[] words = Arrays.copyOfRange(data, start, start + lengths[b]),
                      parity = ReedSolomon.parity(words, degree);
                blocks[b] = Arrays.copyOf(words, words.length + degree);
                System.arraycopy(parity, 0, blocks[b], words.length, degree);
                start += lengths[b];
            }
            return blocks;
        }
        int[] interleave(int[][] blocks) {
            int[] words = new int[total];
            for (int i = 0; i < total; i++) {
                Placement p = placement.get(i);
                words[i] = blocks[p.block()][p.position()];
            }
            return words;
        }
        int[][] deinterleave(int[] words) {
            int[][] blocks = new int[count][];
            for (int b = 0; b < count; b++)
                blocks[b] = new int[lengths[b] + degree];
            for (int i = 0; i < words.length; i++) {
                Placement p = placement.get(i);
                blocks[p.block()][p.position()] = words[i];
            }
            return blocks;
        }
    }
    static final class Geometry {
        int size, dataModules, functionModules;
        int[][] symbol, areas, indices;
        List<Matrix.Point> order;
        Geometry(int version, int[] alignments) {
            size = 17 + 4 * version;
            Matrix.Built built = Matrix.build(version, alignments);
            symbol = built.symbol();
            areas = built.areas();
            order = built.order();
            dataModules = order.size();
            functionModules = size * size - dataModules;
            indices = new int[size][size];
            for (int i = 0; i < order.size(); i++) {
                Matrix.Point p = order.get(i);
                indices[p.y()][p.x()] = i;
            }
        }
    }
    static final class Request {
        String identifier, levelToken, modeToken, versionToken, maskToken, text, mode, level;
        int version, bitCount;
        boolean boosted;
        List<Segment> segments;
        Map<Integer, Split> splits = new HashMap<>();
        Request(String[] fields, String text) {
            identifier = fields[0];
            levelToken = fields[1];
            modeToken = fields[2];
            versionToken = fields[3];
            maskToken = fields[4];
            this.text = text;
        }
        Split split(int version) {
            int category = version == 10 ? 10 : 1;
            if (!splits.containsKey(category))
                splits.put(category, mode.equals("MIXED")
                                         ? mixedSegments(text, version)
                                         : new Split(List.of(new Segment(mode, text)),
                                                     segmentWidth(mode, text, version)));
            return splits.get(category);
        }
        String prepare(Codec codec) {
            if (!LEVELS.contains(levelToken) &&
                !(levelToken.endsWith("+") &&
                  LEVELS.contains(levelToken.substring(0, levelToken.length() - 1))))
                return "level " + levelToken;
            if (!MODES.contains(modeToken) && !modeToken.equals("AUTO") &&
                !modeToken.equals("MIXED"))
                return "mode " + modeToken;
            if (!versionToken.equals("AUTO") &&
                !List.of("1", "2", "3", "4", "5", "6", "7", "8", "9", "10").contains(versionToken))
                return "version " + versionToken;
            if (!maskToken.equals("AUTO") &&
                !List.of("0", "1", "2", "3", "4", "5", "6", "7").contains(maskToken))
                return "mask " + maskToken;
            if (text.isEmpty())
                return "text";
            if (modeToken.equals("NUMERIC") || modeToken.equals("ALPHANUMERIC"))
                for (int p = 0; p < text.length(); p++)
                    if (!encodable(modeToken, text.charAt(p)))
                        return "charset position " + p;
            mode = modeToken;
            if (mode.equals("AUTO"))
                for (String candidate : MODES)
                    if (encodable(candidate, text)) {
                        mode = candidate;
                        break;
                    }
            String base = levelToken.substring(0, 1);
            int first = versionToken.equals("AUTO") ? 1 : Integer.parseInt(versionToken),
                last = versionToken.equals("AUTO") ? 10 : first, bits = 0, capacity = 0;
            for (int v = first; v <= last; v++) {
                bits = split(v).bits();
                capacity = codec.table(v, base).capacity;
                if (bits <= capacity) {
                    version = v;
                    break;
                }
            }
            if (version == 0)
                return "capacity bits " + bits + " capacity " + capacity;
            Split split = split(version);
            segments = split.segments();
            bitCount = split.bits();
            level = base;
            if (levelToken.endsWith("+"))
                for (int index = LEVELS.indexOf(base); index < 4; index++)
                    if (bitCount <= codec.table(version, LEVELS.get(index)).capacity)
                        level = LEVELS.get(index);
            boosted = !level.equals(base);
            return null;
        }
    }
    static final class Encoding {
        Request request;
        Geometry layout;
        BlockLayout blockLayout;
        String rawBits, paddedBits;
        List<String> trace;
        Padding padding;
        int[][] blocks, symbol;
        int[] codewords;
        Masking.Penalty[] penalties = new Masking.Penalty[8];
        int mask, dark;
        Encoding(Request request, Codec codec) {
            this.request = request;
            layout = codec.geometry(request.version);
            blockLayout = codec.table(request.version, request.level);
            Assembled assembled = assembleBits(request.segments, request.version);
            rawBits = assembled.bits();
            trace = assembled.lines();
            padding = padBits(rawBits, blockLayout.capacity);
            paddedBits = padding.bits();
            blocks = blockLayout.encode(Bitstream.toCodewords(paddedBits));
            codewords = blockLayout.interleave(blocks);
            int[][] unmasked = Matrix.copy(layout.symbol);
            String bits = Bitstream.fromCodewords(codewords);
            for (int i = 0; i < bits.length(); i++) {
                Matrix.Point p = layout.order.get(i);
                unmasked[p.y()][p.x()] = bits.charAt(i) - '0';
            }
            List<int[][]> candidates = new ArrayList<>();
            for (int m = 0; m < 8; m++) {
                int[][] candidate = Masking.apply(unmasked, layout.order, m);
                Matrix.Positions positions = Matrix.formatPositions(layout.size);
                int information = Matrix.formatInformation(request.level, m);
                Matrix.writeValue(candidate, positions.first(), information);
                Matrix.writeValue(candidate, positions.second(), information);
                candidates.add(candidate);
                penalties[m] = Masking.penalties(candidate);
            }
            if (request.maskToken.equals("AUTO")) {
                for (int m = 1; m < 8; m++)
                    if (penalties[m].total() < penalties[mask].total())
                        mask = m;
            } else
                mask = Integer.parseInt(request.maskToken);
            symbol = candidates.get(mask);
            for (int[] row : symbol)
                for (int value : row)
                    dark += value;
        }
    }
    static final class Attempt {
        List<String> lines = new ArrayList<>();
        String text;
        List<BlockResult> blocks = new ArrayList<>();
    }
    static String readSegment(Bitstream.Reader reader, String mode, int count) {
        StringBuilder text = new StringBuilder();
        while (count > 0) {
            int groupSize;
            if (mode.equals("NUMERIC")) {
                groupSize = Math.min(3, count);
                int value = reader.read(new int[] {0, 4, 7, 10}[groupSize]),
                    limit = new int[] {1, 10, 100, 1000}[groupSize];
                if (value >= limit)
                    return null;
                String digits = Integer.toString(value);
                text.append("0".repeat(groupSize - digits.length())).append(digits);
            } else if (mode.equals("ALPHANUMERIC")) {
                groupSize = Math.min(2, count);
                int value = reader.read(groupSize == 2 ? 11 : 6);
                if (value >= (groupSize == 2 ? 2025 : 45))
                    return null;
                if (groupSize == 2)
                    text.append(Bitstream.ALPHANUMERIC.charAt(value / 45));
                text.append(Bitstream.ALPHANUMERIC.charAt(value % 45));
            } else {
                groupSize = 1;
                int value = reader.read(8);
                if (value < 32 || value > 126)
                    return null;
                text.append((char)value);
            }
            count -= groupSize;
        }
        return text.toString();
    }
    static void parseData(Attempt attempt, String bits, int version) {
        Bitstream.Reader reader = new Bitstream.Reader(bits);
        StringBuilder text = new StringBuilder();
        int end = 0;
        while (reader.remaining() >= 4) {
            int indicator = reader.read(4);
            if (indicator == 0)
                break;
            String mode = switch (indicator) {
                case 1 -> "NUMERIC";
                case 2 -> "ALPHANUMERIC";
                case 4 -> "BYTE";
                default -> null;
            };
            if (mode == null) {
                attempt.lines.add("parse failed indicator " + Bitstream.binary(indicator, 4));
                return;
            }
            int width = countWidth(mode, version);
            if (reader.remaining() < width) {
                attempt.lines.add("parse failed length " + mode);
                return;
            }
            int count = reader.read(width);
            if (reader.remaining() < dataWidth(mode, count)) {
                attempt.lines.add("parse failed length " + mode);
                return;
            }
            String segment = readSegment(reader, mode, count);
            if (segment == null) {
                attempt.lines.add("parse failed value " + mode);
                return;
            }
            text.append(segment);
            attempt.lines.add("segment " + mode + " " + count);
            end = reader.position;
        }
        attempt.lines.add(
            "padding " +
            (padBits(bits.substring(0, end), bits.length()).bits().equals(bits) ? "ok" : "bad"));
        attempt.text = text.toString();
        attempt.lines.add("text \"" + attempt.text + "\"");
    }
    static int[][] rotate(int[][] symbol) {
        int size = symbol.length;
        int[][] result = new int[size][size];
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
                result[y][x] = symbol[size - 1 - x][y];
        return result;
    }
    static int[][] transpose(int[][] symbol) {
        int size = symbol.length;
        int[][] result = new int[size][size];
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
                result[y][x] = symbol[x][y];
        return result;
    }
    static int finderRotation(int[][] symbol) {
        int size = symbol.length, best = 0, bestScore = Integer.MAX_VALUE;
        int[][] corners = {{size - 7, size - 7}, {size - 7, 0}, {0, 0}, {0, size - 7}};
        for (int k = 0; k < 4; k++) {
            int score = 0;
            for (int y = 0; y < 7; y++)
                for (int x = 0; x < 7; x++)
                    if (symbol[corners[k][1] + y][corners[k][0] + x] ==
                        (Math.max(Math.abs(x - 3), Math.abs(y - 3)) != 2 ? 1 : 0))
                        score++;
            if (score < bestScore) {
                bestScore = score;
                best = k;
            }
        }
        return best;
    }
    static final class Codec {
        BlockLayout[][] tables;
        int[][] alignments;
        Map<Integer, Geometry> geometries = new HashMap<>();
        Codec(BlockLayout[][] tables, int[][] alignments) {
            this.tables = tables;
            this.alignments = alignments;
        }
        BlockLayout table(int version, String level) {
            return tables[version][LEVELS.indexOf(level)];
        }
        Geometry geometry(int version) {
            if (!geometries.containsKey(version))
                geometries.put(version, new Geometry(version, alignments[version]));
            return geometries.get(version);
        }
        Attempt attempt(int[][] symbol) {
            Attempt attempt = new Attempt();
            int size = symbol.length, version = (size - 17) / 4;
            Matrix.Positions positions = Matrix.formatPositions(size);
            int first = Matrix.readValue(symbol, positions.first()),
                second = Matrix.readValue(symbol, positions.second()), firstDistance = 32,
                secondDistance = 32, firstChoice = 0, secondChoice = 0;
            for (int i = 0; i < 32; i++) {
                int information = Matrix.formatInformation(LEVELS.get(i / 8), i % 8),
                    d1 = Integer.bitCount(first ^ information),
                    d2 = Integer.bitCount(second ^ information);
                if (d1 < firstDistance) {
                    firstDistance = d1;
                    firstChoice = i;
                }
                if (d2 < secondDistance) {
                    secondDistance = d2;
                    secondChoice = i;
                }
            }
            String prefix = "format " + Bitstream.binary(first, 15) + " " +
                            Bitstream.binary(second, 15) + " distance " + firstDistance + " " +
                            secondDistance;
            if (Math.min(firstDistance, secondDistance) > 3) {
                attempt.lines.add(prefix + " unreadable");
                return attempt;
            }
            int chosen = secondDistance < firstDistance ? secondChoice : firstChoice,
                mask = chosen % 8;
            String level = LEVELS.get(chosen / 8);
            attempt.lines.add(prefix + " level " + level + " mask " + mask);
            if (version >= 7) {
                positions = Matrix.versionPositions(size);
                first = Matrix.readValue(symbol, positions.first());
                second = Matrix.readValue(symbol, positions.second());
                firstDistance = secondDistance = 32;
                firstChoice = secondChoice = 7;
                for (int v = 7; v <= 40; v++) {
                    int information = Matrix.versionInformation(v),
                        d1 = Integer.bitCount(first ^ information),
                        d2 = Integer.bitCount(second ^ information);
                    if (d1 < firstDistance) {
                        firstDistance = d1;
                        firstChoice = v;
                    }
                    if (d2 < secondDistance) {
                        secondDistance = d2;
                        secondChoice = v;
                    }
                }
                prefix = "version " + Bitstream.binary(first, 18) + " " +
                         Bitstream.binary(second, 18) + " distance " + firstDistance + " " +
                         secondDistance;
                if (Math.min(firstDistance, secondDistance) > 3) {
                    attempt.lines.add(prefix + " unreadable");
                    return attempt;
                }
                chosen = secondDistance < firstDistance ? secondChoice : firstChoice;
                attempt.lines.add(prefix + " decoded " + chosen);
                if (chosen != version)
                    return attempt;
            }
            Geometry geometry = geometry(version);
            BlockLayout layout = table(version, level);
            int[][] unmasked = Masking.apply(symbol, geometry.order, mask);
            StringBuilder bits = new StringBuilder();
            for (int i = 0; i < 8 * layout.total; i++) {
                Matrix.Point p = geometry.order.get(i);
                bits.append(unmasked[p.y()][p.x()]);
            }
            int[][] blocks = layout.deinterleave(Bitstream.toCodewords(bits.toString())),
                    corrected = new int[layout.count][];
            boolean failed = false;
            for (int b = 0; b < blocks.length; b++) {
                ReedSolomon.Correction result = ReedSolomon.correct(blocks[b], layout.degree);
                prefix = "block " + b + " syndromes " + Bitstream.hexadecimal(result.syndromes());
                String status;
                if (result.corrected() == null) {
                    status = "failed";
                    attempt.lines.add(prefix + " failed");
                    failed = true;
                } else if (!result.positions().isEmpty()) {
                    status = "corrected";
                    attempt.lines.add(prefix + " corrected " + joinIntegers(result.positions()));
                } else {
                    status = "ok";
                    attempt.lines.add(prefix + " ok");
                }
                attempt.blocks.add(new BlockResult(status, result.positions().size()));
                corrected[b] = result.corrected();
            }
            if (failed)
                return attempt;
            int[] data = new int[layout.data];
            int offset = 0;
            for (int b = 0; b < layout.count; b++) {
                System.arraycopy(corrected[b], 0, data, offset, layout.lengths[b]);
                offset += layout.lengths[b];
            }
            parseData(attempt, Bitstream.fromCodewords(data), version);
            return attempt;
        }
        Attempt decode(int[][] symbol) {
            int rotations = finderRotation(symbol);
            int[][] oriented = symbol;
            for (int i = 0; i < rotations; i++)
                oriented = rotate(oriented);
            Attempt adopted = attempt(oriented);
            boolean mirrored = false;
            if (adopted.text == null) {
                Attempt second = attempt(transpose(oriented));
                if (second.text != null) {
                    adopted = second;
                    mirrored = true;
                }
            }
            adopted.lines.addFirst("orientation rotations " + rotations + " mirrored " +
                                   (mirrored ? "yes" : "no"));
            return adopted;
        }
    }
    static String joinIntegers(Collection<Integer> values) {
        List<String> pieces = new ArrayList<>();
        for (int value : values)
            pieces.add(Integer.toString(value));
        return String.join(" ", pieces);
    }
    static String joinIntegers(int[] values) {
        List<String> pieces = new ArrayList<>();
        for (int value : values)
            pieces.add(Integer.toString(value));
        return String.join(" ", pieces);
    }
    static List<String> codesLines(Encoding encoding, Codec codec) {
        Request request = encoding.request;
        Geometry layout = encoding.layout;
        BlockLayout blocks = encoding.blockLayout;
        List<String> lines = new ArrayList<>();
        lines.add("symbol version " + request.version + " level " + request.level + " mask " +
                  encoding.mask + " size " + layout.size);
        List<String> segments = new ArrayList<>();
        for (Segment segment : request.segments)
            segments.add(segment.mode() + ":" + segment.text().length());
        lines.add("segments " + segments.size() + " " + String.join(" ", segments));
        List<String> alternatives = new ArrayList<>();
        for (String mode : MODES)
            alternatives.add(
                mode + " " +
                (encodable(mode, request.text)
                     ? Integer.toString(segmentWidth(mode, request.text, request.version))
                     : "-"));
        alternatives.add("MIXED " + (request.mode.equals("MIXED")
                                         ? request.bitCount
                                         : mixedSegments(request.text, request.version).bits()));
        lines.add("bits data " + request.bitCount + " capacity " + blocks.capacity +
                  " alternatives " + String.join(" ", alternatives));
        List<String> fits = new ArrayList<>();
        for (String level : LEVELS) {
            String fitting = "-";
            for (int v = 1; v <= 10; v++)
                if (request.split(v).bits() <= codec.table(v, level).capacity) {
                    fitting = Integer.toString(v);
                    break;
                }
            fits.add(level + " " + fitting);
        }
        lines.add("fits " + String.join(" ", fits));
        lines.add("modules function " + layout.functionModules + " data " + layout.dataModules +
                  " remainder " + (layout.dataModules - 8 * blocks.total) + " dark " +
                  encoding.dark);
        lines.add("format " +
                  Bitstream.binary(Matrix.formatInformation(request.level, encoding.mask), 15) +
                  " version " +
                  (request.version >= 7
                       ? Bitstream.binary(Matrix.versionInformation(request.version), 18)
                       : "none"));
        for (int m = 0; m < 8; m++) {
            Masking.Penalty p = encoding.penalties[m];
            lines.add("penalty " + m + " n1 " + p.n1() + " n2 " + p.n2() + " n3 " + p.n3() +
                      " n4 " + p.n4() + " total " + p.total());
        }
        lines.addAll(Render.symbolLines(encoding.symbol));
        return lines;
    }
    static List<String> codewordLines(Encoding encoding) {
        Request request = encoding.request;
        BlockLayout layout = encoding.blockLayout;
        List<String> lines = new ArrayList<>();
        lines.add("request " + request.identifier + " version " + request.version + " level " +
                  request.level + " blocks " + layout.count + " data " + layout.data +
                  " ec_per_block " + layout.degree + " total " + layout.total);
        for (int b = 0; b < layout.count; b++) {
            lines.add("block " + b + " data " +
                      Bitstream.hexadecimal(
                          Arrays.copyOfRange(encoding.blocks[b], 0, layout.lengths[b])));
            lines.add("block " + b + " ec " +
                      Bitstream.hexadecimal(Arrays.copyOfRange(
                          encoding.blocks[b], layout.lengths[b], encoding.blocks[b].length)));
        }
        lines.add("interleaved " + Bitstream.hexadecimal(encoding.codewords));
        return lines;
    }
    static List<String> bitstreamLines(Encoding encoding) {
        Request request = encoding.request;
        List<String> lines = new ArrayList<>();
        lines.add("request " + request.identifier + " version " + request.version + " bits " +
                  request.bitCount + " capacity " + encoding.blockLayout.capacity);
        lines.addAll(encoding.trace);
        Padding p = encoding.padding;
        lines.add("terminator " + p.terminator() + " zero_fill " + p.zeroFill() + " pad_bytes " +
                  p.padBytes());
        return lines;
    }
    static Image readImage(Path path) throws Exception {
        List<String> lines = Files.readAllLines(path, StandardCharsets.US_ASCII);
        String[] dimensions = lines.get(1).split(" ");
        int width = Integer.parseInt(dimensions[0]), height = Integer.parseInt(dimensions[1]),
            left = width, right = 0, top = height;
        int[][] pixels = new int[height][width];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                pixels[y][x] = lines.get(y + 2).charAt(x) - '0';
                if (pixels[y][x] == 1) {
                    left = Math.min(left, x);
                    right = Math.max(right, x);
                    top = Math.min(top, y);
                }
            }
        int run = 0;
        while (left + run < width && pixels[top][left + run] == 1)
            run++;
        int unit = run / 7, size = (right - left + 1) / unit;
        int[][] symbol = new int[size][size];
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
                symbol[y][x] = pixels[top + unit * y][left + unit * x];
        boolean wellFormed = true;
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                int expected =
                    x >= left && x < left + unit * size && y >= top && y < top + unit * size
                        ? symbol[(y - top) / unit][(x - left) / unit]
                        : 0;
                if (pixels[y][x] != expected)
                    wellFormed = false;
            }
        return new Image(symbol, "image " + width + " " + height + " quiet " + (left / unit) +
                                     " scale " + unit + " size " + size + " " +
                                     (wellFormed ? "ok" : "bad"));
    }
    static Damaged damagedSymbol(Encoding encoding, List<Damage> operations) {
        int[][] symbol = Matrix.copy(encoding.symbol);
        for (Damage operation : operations) {
            int[] a = operation.arguments();
            if (operation.operation().equals("flip"))
                symbol[a[1]][a[0]] ^= 1;
            else if (operation.operation().equals("fill"))
                for (int y = a[1]; y < a[1] + a[3]; y++)
                    for (int x = a[0]; x < a[0] + a[2]; x++)
                        symbol[y][x] = a[4];
        }
        int[] counts = new int[5];
        List<Set<Integer>> damagedWords = new ArrayList<>();
        for (int b = 0; b < encoding.blockLayout.count; b++)
            damagedWords.add(new HashSet<>());
        for (int y = 0; y < symbol.length; y++)
            for (int x = 0; x < symbol.length; x++)
                if (symbol[y][x] != encoding.symbol[y][x]) {
                    int area = encoding.layout.areas[y][x];
                    if (area == Matrix.FUNCTION)
                        counts[0]++;
                    else if (area == Matrix.FORMAT)
                        counts[1]++;
                    else if (area == Matrix.VERSION)
                        counts[2]++;
                    else {
                        int index = encoding.layout.indices[y][x];
                        if (index < 8 * encoding.blockLayout.total) {
                            counts[3]++;
                            Placement p = encoding.blockLayout.placement.get(index / 8);
                            damagedWords.get(p.block()).add(p.position());
                        } else
                            counts[4]++;
                    }
                }
        for (Damage operation : operations)
            if (operation.operation().equals("rotate"))
                symbol = rotate(symbol);
            else if (operation.operation().equals("mirror"))
                symbol = transpose(symbol);
        int total = 0;
        for (int count : counts)
            total += count;
        List<Integer> errors = new ArrayList<>();
        for (Set<Integer> words : damagedWords)
            errors.add(words.size());
        return new Damaged(symbol, List.of("check damaged operations " + operations.size(),
                                           "damage changed " + total + " function " + counts[0] +
                                               " format " + counts[1] + " version " + counts[2] +
                                               " data " + counts[3] + " remainder " + counts[4],
                                           "errors " + joinIntegers(errors) + " limit " +
                                               (encoding.blockLayout.degree / 2)));
    }
    static int tolerance(Encoding encoding, Codec codec, int color) {
        int size = encoding.layout.size;
        for (int side = 1; side <= size; side++) {
            int[][] symbol = Matrix.copy(encoding.symbol);
            int start = (size - side) / 2;
            for (int y = start; y < start + side; y++)
                for (int x = start; x < start + side; x++)
                    symbol[y][x] = color;
            if (!encoding.request.text.equals(codec.decode(symbol).text))
                return side - 1;
        }
        return size;
    }
    static final class Summary {
        Map<String, Integer> totals = new HashMap<>(), errors = new HashMap<>(),
                             modes = new HashMap<>(), levels = new HashMap<>(),
                             checks = new HashMap<>(), blocks = new HashMap<>(),
                             scans = new HashMap<>();
        int[] versions = new int[11], masks = new int[8];
        static int get(Map<String, Integer> map, String key) { return map.getOrDefault(key, 0); }
        static void add(Map<String, Integer> map, String key, int amount) {
            map.put(key, get(map, key) + amount);
        }
        static String named(Map<String, Integer> map, List<String> names) {
            List<String> items = new ArrayList<>();
            for (String name : names)
                items.add(name + " " + get(map, name));
            return String.join(" ", items);
        }
        static int sum(Map<String, Integer> map) {
            int sum = 0;
            for (int value : map.values())
                sum += value;
            return sum;
        }
        void recordError(String error) { add(errors, error.split(" ")[0], 1); }
        void recordEncoding(Encoding encoding) {
            Request r = encoding.request;
            add(totals, "encoded", 1);
            add(modes, r.mode, 1);
            add(levels, r.level, 1);
            add(totals, "boosted", r.boosted ? 1 : 0);
            versions[r.version]++;
            masks[encoding.mask]++;
            add(totals, "segments", r.segments.size());
            add(totals, "data", encoding.blockLayout.data);
            add(totals, "ec", encoding.blockLayout.degree * encoding.blockLayout.count);
            add(totals, "modules", encoding.layout.size * encoding.layout.size);
            add(totals, "dark", encoding.dark);
        }
        String recordCheck(Attempt attempt, String text) {
            String result = attempt.text == null        ? "failed"
                            : attempt.text.equals(text) ? "ok"
                                                        : "mismatch";
            add(checks, result, 1);
            for (BlockResult block : attempt.blocks) {
                add(blocks, block.status(), 1);
                add(totals, "corrected_positions", block.positions());
            }
            return result;
        }
        List<String> lines(int requests) {
            return List.of(
                "requests " + requests + " encoded " + get(totals, "encoded") + " errors " +
                    sum(errors),
                "error_kinds " + named(errors, ERROR_KINDS),
                "modes " + named(modes, List.of("NUMERIC", "ALPHANUMERIC", "BYTE", "MIXED")),
                "levels " + named(levels, LEVELS) + " boosted " + get(totals, "boosted"),
                "versions " + joinIntegers(Arrays.copyOfRange(versions, 1, 11)),
                "masks " + joinIntegers(masks),
                "segments " + get(totals, "segments") + " data_codewords " + get(totals, "data") +
                    " ec_codewords " + get(totals, "ec"),
                "modules " + get(totals, "modules") + " dark " + get(totals, "dark"),
                "checks " + sum(checks) + " " + named(checks, List.of("ok", "mismatch", "failed")),
                "blocks " + named(blocks, List.of("ok", "corrected", "failed")) + " codewords " +
                    get(totals, "corrected_positions"),
                "scans " + sum(scans) + " decoded " + get(scans, "decoded") + " failed " +
                    get(scans, "failed"));
        }
    }
    static List<String> checkLines(Encoding encoding, Codec codec, int quiet, int scale,
                                   List<Damage> operations, Summary summary, Path output)
        throws Exception {
        Request request = encoding.request;
        Path path = output.resolve("qr_" + request.identifier + ".pbm");
        Files.writeString(path, Render.pbmText(encoding.symbol, quiet, scale),
                          StandardCharsets.US_ASCII);
        Image image = readImage(path);
        List<String> lines =
            new ArrayList<>(List.of("request " + request.identifier, image.line(), "check clean"));
        Attempt attempt = codec.decode(image.symbol());
        lines.addAll(attempt.lines);
        lines.add("result " + summary.recordCheck(attempt, request.text));
        if (!operations.isEmpty()) {
            Damaged damaged = damagedSymbol(encoding, operations);
            lines.addAll(damaged.lines());
            attempt = codec.decode(damaged.symbol());
            lines.addAll(attempt.lines);
            lines.add("result " + summary.recordCheck(attempt, request.text));
        }
        lines.add("tolerance light " + tolerance(encoding, codec, 0) + " dark " +
                  tolerance(encoding, codec, 1));
        return lines;
    }
    static List<String> capacityLines(Codec codec) {
        List<String> lines = new ArrayList<>();
        for (int v = 1; v <= 10; v++) {
            Geometry geometry = codec.geometry(v);
            int total = codec.table(v, "L").total;
            String alignment =
                codec.alignments[v].length == 0 ? "none" : joinIntegers(codec.alignments[v]);
            lines.add("version " + v + " size " + geometry.size + " data_modules " +
                      geometry.dataModules + " codewords " + total + " remainder " +
                      (geometry.dataModules - 8 * total) + " alignment " + alignment);
            for (String level : LEVELS) {
                BlockLayout layout = codec.table(v, level);
                int[] maxima = new int[3];
                for (int m = 0; m < 3; m++)
                    while (4 + countWidth(MODES.get(m), v) +
                               dataWidth(MODES.get(m), maxima[m] + 1) <=
                           layout.capacity)
                        maxima[m]++;
                lines.add("level " + level + " blocks " + layout.count + " data " + layout.data +
                          " ec_per_block " + layout.degree + " numeric " + maxima[0] +
                          " alphanumeric " + maxima[1] + " byte " + maxima[2]);
            }
        }
        return lines;
    }
    static List<String> readLines(String name) throws Exception {
        return Files.readAllLines(Path.of("input", name + ".txt"), StandardCharsets.US_ASCII);
    }
    static void writeLines(Path output, String name, List<String> lines) throws Exception {
        Files.writeString(output.resolve(name + ".txt"),
                          lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws Exception {
        List<Request> requests = new ArrayList<>();
        for (String line : readLines("requests")) {
            int colon = line.indexOf(':');
            requests.add(
                new Request(line.substring(0, colon).split(" "), line.substring(colon + 1)));
        }
        List<String> params = readLines("params");
        int quiet = Integer.parseInt(params.get(0).split(" ")[1]),
            scale = Integer.parseInt(params.get(1).split(" ")[1]);
        BlockLayout[][] tables = new BlockLayout[11][4];
        int[][] alignments = new int[11][];
        for (String line : readLines("tables")) {
            String[] fields = line.split(" ");
            int v = Integer.parseInt(fields[1]);
            if (fields[0].equals("block"))
                tables[v][LEVELS.indexOf(fields[2])] =
                    new BlockLayout(Integer.parseInt(fields[3]), Integer.parseInt(fields[4]),
                                    Integer.parseInt(fields[5]), Integer.parseInt(fields[6]),
                                    Integer.parseInt(fields[7]));
            else {
                alignments[v] = new int[fields.length - 2];
                for (int i = 2; i < fields.length; i++)
                    alignments[v][i - 2] = Integer.parseInt(fields[i]);
            }
        }
        Map<String, List<Damage>> damage = new HashMap<>();
        for (String line : readLines("damage")) {
            String[] fields = line.split(" ");
            int[] arguments = new int[fields[1].equals("flip")   ? 2
                                      : fields[1].equals("fill") ? 5
                                                                 : 0];
            for (int i = 0; i < arguments.length; i++)
                arguments[i] = i == 4 ? (fields[i + 2].equals("dark") ? 1 : 0)
                                      : Integer.parseInt(fields[i + 2]);
            damage.computeIfAbsent(fields[0], key -> new ArrayList<>())
                .add(new Damage(fields[1], arguments));
        }
        List<String> scanLines = readLines("scans");
        List<Scan> scans = new ArrayList<>();
        for (int i = 0; i < scanLines.size();) {
            String name = scanLines.get(i).split(" ")[1];
            int size = scanLines.get(i + 1).length();
            int[][] symbol = new int[size][size];
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                    symbol[y][x] = scanLines.get(i + 1 + y).charAt(x) == '#' ? 1 : 0;
            scans.add(new Scan(name, symbol));
            i += size + 1;
        }
        Codec codec = new Codec(tables, alignments);
        Summary summary = new Summary();
        Path output = Path.of("output");
        Files.createDirectories(output);
        Map<String, List<String>> reports = new LinkedHashMap<>();
        for (String name : List.of("codes", "codewords", "bitstream", "selfcheck", "scans"))
            reports.put(name, new ArrayList<>());
        for (Request request : requests) {
            reports.get("codes").add("request " + request.identifier);
            String error = request.prepare(codec);
            if (error != null) {
                reports.get("codes").add("error " + error);
                summary.recordError(error);
                continue;
            }
            Encoding encoding = new Encoding(request, codec);
            reports.get("codes").addAll(codesLines(encoding, codec));
            reports.get("codewords").addAll(codewordLines(encoding));
            reports.get("bitstream").addAll(bitstreamLines(encoding));
            summary.recordEncoding(encoding);
            reports.get("selfcheck")
                .addAll(checkLines(encoding, codec, quiet, scale,
                                   damage.getOrDefault(request.identifier, List.of()), summary,
                                   output));
        }
        for (Scan scan : scans) {
            List<String> lines = reports.get("scans");
            lines.add("scan " + scan.name() + " size " + scan.symbol().length);
            Attempt attempt = codec.decode(scan.symbol());
            lines.addAll(attempt.lines);
            String result = attempt.text == null ? "failed" : "decoded";
            lines.add("result " + result);
            Summary.add(summary.scans, result, 1);
        }
        reports.put("capacity", capacityLines(codec));
        reports.put("summary", summary.lines(requests.size()));
        for (Map.Entry<String, List<String>> entry : reports.entrySet())
            writeLines(output, entry.getKey(), entry.getValue());
    }
}
