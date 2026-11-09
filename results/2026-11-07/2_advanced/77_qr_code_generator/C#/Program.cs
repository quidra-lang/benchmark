using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
public static class Program {
    public static readonly List<string> LEVELS = new List<string> { "L", "M", "Q", "H" },
                                        MODES =
                                            new List<string> { "NUMERIC", "ALPHANUMERIC", "BYTE" },
                                        ERROR_KINDS =
                                            new List<string> { "level",   "mode", "version",
                                                               "mask",    "text", "charset",
                                                               "capacity" };
    public record Segment(string mode, string text) {}
    public record Split(List<Segment> segments, int bits) {}
    public record Group(int value, int width, string text) {}
    public record Assembled(string bits, List<string> lines) {}
    public record Padding(string bits, int terminator, int zeroFill, int padBytes) {}
    public record Placement(int block, int position) {}
    public record BlockResult(string status, int positions) {}
    public record Scan(string name, int[][] symbol) {}
    public record Damage(string operation, int[] arguments) {}
    public record Image(int[][] symbol, string line) {}
    public record Damaged(int[][] symbol, List<string> lines) {}
    public static int CountWidth(string mode, int version) {
        return (version == 10 ? new int[] { 12, 11, 16 }
                              : new int[] { 10, 9, 8 })[MODES.IndexOf(mode)];
    }
    public static int DataWidth(string mode, int count) {
        return (mode) switch {
            "NUMERIC" => 10 * (count / 3) + (new int[] { 0, 4, 7 })[count % 3],
            "ALPHANUMERIC" => 11 * (count / 2) + 6 * (count % 2),
            _ => 8 * count,
        };
    }
    public static int Indicator(string mode) {
        return (new int[] { 1, 2, 4 })[MODES.IndexOf(mode)];
    }
    public static bool Encodable(string mode, char character) {
        return (mode) switch {
            "NUMERIC" => character >= '0' && character <= '9',
            "ALPHANUMERIC" => Bitstream.ALPHANUMERIC.IndexOf(character) >= 0,
            _ => character >= 32 && character <= 126,
        };
    }
    public static bool Encodable(string mode, string text) {
        for (int i = 0; i < text.Length; i++)
            if (!Encodable(mode, text[i]))
                return false;
        return true;
    }
    public static int SegmentWidth(string mode, string text, int version) {
        return 4 + CountWidth(mode, version) + DataWidth(mode, text.Length);
    }
    public static List<Group> Groups(string mode, string text) {
        int step = (mode) switch {
            "NUMERIC" => 3,
            "ALPHANUMERIC" => 2,
            _ => 1,
        };
        List<Group> groups = new();
        for (int start = 0; start < text.Length; start += step) {
            string characters =
                text.Substring(start, Math.Min(start + step, text.Length) - (start));
            int value, width;
            if (mode.Equals("NUMERIC")) {
                value = int.Parse(characters);
                width = (new int[] { 0, 4, 7, 10 })[characters.Length];
            } else if (mode.Equals("ALPHANUMERIC")) {
                value = Bitstream.ALPHANUMERIC.IndexOf(characters[0]);
                width = 6;
                if (characters.Length == 2) {
                    value = 45 * value + Bitstream.ALPHANUMERIC.IndexOf(characters[1]);
                    width = 11;
                }
            } else {
                value = characters[0];
                width = 8;
            }
            groups.Add(new Group(value, width, characters));
        }
        return groups;
    }
    public static Split MixedSegments(string text, int version) {
        int length = text.Length;
        int[][] invalid = Enumerable.Range(0, 3)
                              .Select(
                                  _ => new int[length + 1])
                              .ToArray();
        for (int i = 0; i < length; i++)
            for (int m = 0; m < 3; m++)
                invalid[m][i + 1] = invalid[m][i] + (Encodable(MODES[m], text[i]) ? 0 : 1);
        int[] costs = new int[length + 1], starts = new int[length + 1],
              modes = new int[length + 1];
        for (int end = 1; end <= length; end++) {
            costs[end] = int.MaxValue;
            for (int start = 0; start < end; start++)
                for (int m = 0; m < 3; m++)
                    if (invalid[m][end] == invalid[m][start]) {
                        string mode = MODES[m];
                        int cost = costs[start] + 4 + CountWidth(mode, version) +
                                   DataWidth(mode, end - start);
                        if (cost < costs[end]) {
                            costs[end] = cost;
                            starts[end] = start;
                            modes[end] = m;
                        }
                    }
        }
        List<Segment> segments = new();
        for (int end = length; end > 0; end = starts[end])
            segments.Add(
                new Segment(MODES[modes[end]], text.Substring(starts[end], end - (starts[end]))));
        segments.Reverse();
        return new Split(segments, costs[length]);
    }
    public static Assembled AssembleBits(List<Segment> segments, int version) {
        Bitstream.Writer writer = new Bitstream.Writer();
        List<string> lines = new();
        foreach (Segment segment in segments) {
            string mode = segment.mode, text = segment.text;
            int width = CountWidth(mode, version), indicator = Indicator(mode);
            writer.Write(indicator, 4);
            writer.Write(text.Length, width);
            lines.Add("segment " + mode + " indicator " + Bitstream.Binary(indicator, 4) +
                      " count " + text.Length + " " + Bitstream.Binary(text.Length, width));
            foreach (Group group in Groups(mode, text)) {
                writer.Write(group.value, group.width);
                lines.Add("group " + group.value + " " +
                          Bitstream.Binary(group.value, group.width) + " \"" + group.text + "\"");
            }
        }
        return new Assembled(writer.Value(), lines);
    }
    public static Padding PadBits(string bits, int capacity) {
        int terminator = Math.Min(4, capacity - bits.Length);
        string padded = bits + new string('0', terminator);
        int zeroFill = (8 - padded.Length % 8) % 8;
        padded += new string('0', zeroFill);
        int padBytes = (capacity - padded.Length) / 8;
        StringBuilder result = new StringBuilder(padded);
        for (int i = 0; i < padBytes; i++)
            result.Append(i % 2 == 0 ? "11101100" : "00010001");
        return new Padding(result.ToString(), terminator, zeroFill, padBytes);
    }
    public sealed class BlockLayout {
        public int degree, count, data, capacity, total;
        public int[] lengths;
        public List<Placement> placement = new();
        public BlockLayout(int degree, int firstCount, int firstSize, int secondCount,
                           int secondSize) {
            this.degree = degree;
            count = firstCount + secondCount;
            lengths = new int[count];
            for (int i = 0; i < count; i++) {
                lengths[i] = i < firstCount ? firstSize : secondSize;
                data += lengths[i];
            }
            capacity = 8 * data;
            total = data + degree * count;
            for (int position = 0; position < Math.Max(firstSize, secondSize); position++)
                for (int block = 0; block < count; block++)
                    if (position < lengths[block])
                        placement.Add(new Placement(block, position));
            for (int offset = 0; offset < degree; offset++)
                for (int block = 0; block < count; block++)
                    placement.Add(new Placement(block, lengths[block] + offset));
        }
        public int[][] Encode(int[] data) {
            int[][] blocks = new int [count][];
            int start = 0;
            for (int b = 0; b < count; b++) {
                int[] words = data[(start)..(start + lengths[b])],
                      parity = ReedSolomon.Parity(words, degree);
                blocks[b] = words.Concat(new int[degree]).ToArray();
                Array.Copy(parity, 0, blocks[b], words.Length, degree);
                start += lengths[b];
            }
            return blocks;
        }
        public int[] Interleave(int[][] blocks) {
            int[] words = new int[total];
            for (int i = 0; i < total; i++) {
                Placement p = placement[i];
                words[i] = blocks[p.block][p.position];
            }
            return words;
        }
        public int[][] Deinterleave(int[] words) {
            int[][] blocks = new int [count][];
            for (int b = 0; b < count; b++)
                blocks[b] = new int[lengths[b] + degree];
            for (int i = 0; i < words.Length; i++) {
                Placement p = placement[i];
                blocks[p.block][p.position] = words[i];
            }
            return blocks;
        }
    }
    public sealed class Geometry {
        public int size, dataModules, functionModules;
        public int[][] symbol, areas, indices;
        public List<Matrix.Point> order;
        public Geometry(int version, int[] alignments) {
            size = 17 + 4 * version;
            Matrix.Built built = Matrix.Build(version, alignments);
            symbol = built.symbol;
            areas = built.areas;
            order = built.order;
            dataModules = order.Count;
            functionModules = size * size - dataModules;
            indices = Enumerable.Range(0, size)
                          .Select(
                              _ => new int[size])
                          .ToArray();
            for (int i = 0; i < order.Count; i++) {
                Matrix.Point p = order[i];
                indices[p.y][p.x] = i;
            }
        }
    }
    public sealed class Request {
        public string identifier, levelToken, modeToken, versionToken, maskToken, text, mode, level;
        public int version, bitCount;
        public bool boosted;
        public List<Segment> segments;
        public Dictionary<int, Split> splits = new();
        public Request(string[] fields, string text) {
            identifier = fields[0];
            levelToken = fields[1];
            modeToken = fields[2];
            versionToken = fields[3];
            maskToken = fields[4];
            this.text = text;
        }
        public Split Split(int version) {
            int category = version == 10 ? 10 : 1;
            if (!splits.ContainsKey(category))
                splits[category] = mode.Equals("MIXED")
                                       ? MixedSegments(text, version)
                                       : new Split(new List<Segment> { new Segment(mode, text) },
                                                   SegmentWidth(mode, text, version));
            return splits[category];
        }
        public string Prepare(Codec codec) {
            if (!LEVELS.Contains(levelToken) &&
                !(levelToken.EndsWith("+") &&
                  LEVELS.Contains(levelToken.Substring(0, levelToken.Length - 1 - (0)))))
                return "level " + levelToken;
            if (!MODES.Contains(modeToken) && !modeToken.Equals("AUTO") &&
                !modeToken.Equals("MIXED"))
                return "mode " + modeToken;
            if (!versionToken.Equals("AUTO") &&
                !new List<string> { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" }.Contains(
                    versionToken))
                return "version " + versionToken;
            if (!maskToken.Equals("AUTO") &&
                !new List<string> { "0", "1", "2", "3", "4", "5", "6", "7" }.Contains(maskToken))
                return "mask " + maskToken;
            if (text.Length == 0)
                return "text";
            if (modeToken.Equals("NUMERIC") || modeToken.Equals("ALPHANUMERIC"))
                for (int p = 0; p < text.Length; p++)
                    if (!Encodable(modeToken, text[p]))
                        return "charset position " + p;
            mode = modeToken;
            if (mode.Equals("AUTO"))
                foreach (string candidate in MODES)
                    if (Encodable(candidate, text)) {
                        mode = candidate;
                        break;
                    }
            string baseLevel = levelToken.Substring(0, 1 - (0));
            int first = versionToken.Equals("AUTO") ? 1 : int.Parse(versionToken),
                last = versionToken.Equals("AUTO") ? 10 : first, bits = 0, capacity = 0;
            for (int v = first; v <= last; v++) {
                bits = Split(v).bits;
                capacity = codec.Table(v, baseLevel).capacity;
                if (bits <= capacity) {
                    version = v;
                    break;
                }
            }
            if (version == 0)
                return "capacity bits " + bits + " capacity " + capacity;
            Split split = Split(version);
            segments = split.segments;
            bitCount = split.bits;
            level = baseLevel;
            if (levelToken.EndsWith("+"))
                for (int index = LEVELS.IndexOf(baseLevel); index < 4; index++)
                    if (bitCount <= codec.Table(version, LEVELS[index]).capacity)
                        level = LEVELS[index];
            boosted = !level.Equals(baseLevel);
            return null;
        }
    }
    public sealed class Encoding {
        public Request request;
        public Geometry layout;
        public BlockLayout blockLayout;
        public string rawBits, paddedBits;
        public List<string> trace;
        public Padding padding;
        public int[][] blocks, symbol;
        public int[] codewords;
        public Masking.Penalty[] penalties = new Masking.Penalty[8];
        public int mask, dark;
        public Encoding(Request request, Codec codec) {
            this.request = request;
            layout = codec.Geometry(request.version);
            blockLayout = codec.Table(request.version, request.level);
            Assembled assembled = AssembleBits(request.segments, request.version);
            rawBits = assembled.bits;
            trace = assembled.lines;
            padding = PadBits(rawBits, blockLayout.capacity);
            paddedBits = padding.bits;
            blocks = blockLayout.Encode(Bitstream.ToCodewords(paddedBits));
            codewords = blockLayout.Interleave(blocks);
            int[][] unmasked = Matrix.Copy(layout.symbol);
            string bits = Bitstream.FromCodewords(codewords);
            for (int i = 0; i < bits.Length; i++) {
                Matrix.Point p = layout.order[i];
                unmasked[p.y][p.x] = bits[i] - '0';
            }
            List<int[][]> candidates = new();
            for (int m = 0; m < 8; m++) {
                int[][] candidate = Masking.Apply(unmasked, layout.order, m);
                Matrix.Positions positions = Matrix.FormatPositions(layout.size);
                int information = Matrix.FormatInformation(request.level, m);
                Matrix.WriteValue(candidate, positions.first, information);
                Matrix.WriteValue(candidate, positions.second, information);
                candidates.Add(candidate);
                penalties[m] = Masking.Penalties(candidate);
            }
            if (request.maskToken.Equals("AUTO")) {
                for (int m = 1; m < 8; m++)
                    if (penalties[m].Total() < penalties[mask].Total())
                        mask = m;
            } else
                mask = int.Parse(request.maskToken);
            symbol = candidates[mask];
            foreach (int[] row in symbol)
                foreach (int value in row)
                    dark += value;
        }
    }
    public sealed class Attempt {
        public List<string> lines = new();
        public string text;
        public List<BlockResult> blocks = new();
    }
    public static string ReadSegment(Bitstream.Reader reader, string mode, int count) {
        StringBuilder text = new StringBuilder();
        while (count > 0) {
            int groupSize;
            if (mode.Equals("NUMERIC")) {
                groupSize = Math.Min(3, count);
                int value = reader.Read((new int[] { 0, 4, 7, 10 })[groupSize]),
                    limit = (new int[] { 1, 10, 100, 1000 })[groupSize];
                if (value >= limit)
                    return null;
                string digits = Convert.ToString(value);
                text.Append(new string('0', groupSize - digits.Length)).Append(digits);
            } else if (mode.Equals("ALPHANUMERIC")) {
                groupSize = Math.Min(2, count);
                int value = reader.Read(groupSize == 2 ? 11 : 6);
                if (value >= (groupSize == 2 ? 2025 : 45))
                    return null;
                if (groupSize == 2)
                    text.Append(Bitstream.ALPHANUMERIC[value / 45]);
                text.Append(Bitstream.ALPHANUMERIC[value % 45]);
            } else {
                groupSize = 1;
                int value = reader.Read(8);
                if (value < 32 || value > 126)
                    return null;
                text.Append((char)value);
            }
            count -= groupSize;
        }
        return text.ToString();
    }
    public static void ParseData(Attempt attempt, string bits, int version) {
        Bitstream.Reader reader = new Bitstream.Reader(bits);
        StringBuilder text = new StringBuilder();
        int end = 0;
        while (reader.Remaining() >= 4) {
            int indicator = reader.Read(4);
            if (indicator == 0)
                break;
            string mode = (indicator) switch {
                1 => "NUMERIC",
                2 => "ALPHANUMERIC",
                4 => "BYTE",
                _ => null,
            };
            if (mode == null) {
                attempt.lines.Add("parse failed indicator " + Bitstream.Binary(indicator, 4));
                return;
            }
            int width = CountWidth(mode, version);
            if (reader.Remaining() < width) {
                attempt.lines.Add("parse failed length " + mode);
                return;
            }
            int count = reader.Read(width);
            if (reader.Remaining() < DataWidth(mode, count)) {
                attempt.lines.Add("parse failed length " + mode);
                return;
            }
            string segment = ReadSegment(reader, mode, count);
            if (segment == null) {
                attempt.lines.Add("parse failed value " + mode);
                return;
            }
            text.Append(segment);
            attempt.lines.Add("segment " + mode + " " + count);
            end = reader.position;
        }
        attempt.lines.Add(
            "padding " +
            (PadBits(bits.Substring(0, end - (0)), bits.Length).bits.Equals(bits) ? "ok" : "bad"));
        attempt.text = text.ToString();
        attempt.lines.Add("text \"" + attempt.text + "\"");
    }
    public static int[][] Rotate(int[][] symbol) {
        int size = symbol.Length;
        int[][] result = Enumerable.Range(0, size)
                             .Select(
                                 _ => new int[size])
                             .ToArray();
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
                result[y][x] = symbol[size - 1 - x][y];
        return result;
    }
    public static int[][] Transpose(int[][] symbol) {
        int size = symbol.Length;
        int[][] result = Enumerable.Range(0, size)
                             .Select(
                                 _ => new int[size])
                             .ToArray();
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
                result[y][x] = symbol[x][y];
        return result;
    }
    public static int FinderRotation(int[][] symbol) {
        int size = symbol.Length, best = 0, bestScore = int.MaxValue;
        int[][] corners = { new[] { size - 7, size - 7 }, new[] { size - 7, 0 }, new[] { 0, 0 },
                            new[] { 0, size - 7 } };
        for (int k = 0; k < 4; k++) {
            int score = 0;
            for (int y = 0; y < 7; y++)
                for (int x = 0; x < 7; x++)
                    if (symbol[corners[k][1] + y][corners[k][0] + x] ==
                        (Math.Max(Math.Abs(x - 3), Math.Abs(y - 3)) != 2 ? 1 : 0))
                        score++;
            if (score < bestScore) {
                bestScore = score;
                best = k;
            }
        }
        return best;
    }
    public sealed class Codec {
        public BlockLayout[][] tables;
        public int[][] alignments;
        public Dictionary<int, Geometry> geometries = new();
        public Codec(BlockLayout[][] tables, int[][] alignments) {
            this.tables = tables;
            this.alignments = alignments;
        }
        public BlockLayout Table(int version, string level) {
            return tables[version][LEVELS.IndexOf(level)];
        }
        public Geometry Geometry(int version) {
            if (!geometries.ContainsKey(version))
                geometries[version] = new Geometry(version, alignments[version]);
            return geometries[version];
        }
        public Attempt Attempt(int[][] symbol) {
            Attempt attempt = new Attempt();
            int size = symbol.Length, version = (size - 17) / 4;
            Matrix.Positions positions = Matrix.FormatPositions(size);
            int first = Matrix.ReadValue(symbol, positions.first),
                second = Matrix.ReadValue(symbol, positions.second), firstDistance = 32,
                secondDistance = 32, firstChoice = 0, secondChoice = 0;
            for (int i = 0; i < 32; i++) {
                int information = Matrix.FormatInformation(LEVELS[i / 8], i % 8),
                    d1 = System.Numerics.BitOperations.PopCount((uint)(first ^ information)),
                    d2 = System.Numerics.BitOperations.PopCount((uint)(second ^ information));
                if (d1 < firstDistance) {
                    firstDistance = d1;
                    firstChoice = i;
                }
                if (d2 < secondDistance) {
                    secondDistance = d2;
                    secondChoice = i;
                }
            }
            string prefix = "format " + Bitstream.Binary(first, 15) + " " +
                            Bitstream.Binary(second, 15) + " distance " + firstDistance + " " +
                            secondDistance;
            if (Math.Min(firstDistance, secondDistance) > 3) {
                attempt.lines.Add(prefix + " unreadable");
                return attempt;
            }
            int chosen = secondDistance < firstDistance ? secondChoice : firstChoice,
                mask = chosen % 8;
            string level = LEVELS[chosen / 8];
            attempt.lines.Add(prefix + " level " + level + " mask " + mask);
            if (version >= 7) {
                positions = Matrix.VersionPositions(size);
                first = Matrix.ReadValue(symbol, positions.first);
                second = Matrix.ReadValue(symbol, positions.second);
                firstDistance = secondDistance = 32;
                firstChoice = secondChoice = 7;
                for (int v = 7; v <= 40; v++) {
                    int information = Matrix.VersionInformation(v),
                        d1 = System.Numerics.BitOperations.PopCount((uint)(first ^ information)),
                        d2 = System.Numerics.BitOperations.PopCount((uint)(second ^ information));
                    if (d1 < firstDistance) {
                        firstDistance = d1;
                        firstChoice = v;
                    }
                    if (d2 < secondDistance) {
                        secondDistance = d2;
                        secondChoice = v;
                    }
                }
                prefix = "version " + Bitstream.Binary(first, 18) + " " +
                         Bitstream.Binary(second, 18) + " distance " + firstDistance + " " +
                         secondDistance;
                if (Math.Min(firstDistance, secondDistance) > 3) {
                    attempt.lines.Add(prefix + " unreadable");
                    return attempt;
                }
                chosen = secondDistance < firstDistance ? secondChoice : firstChoice;
                attempt.lines.Add(prefix + " decoded " + chosen);
                if (chosen != version)
                    return attempt;
            }
            Geometry geometry = Geometry(version);
            BlockLayout layout = Table(version, level);
            int[][] unmasked = Masking.Apply(symbol, geometry.order, mask);
            StringBuilder bits = new StringBuilder();
            for (int i = 0; i < 8 * layout.total; i++) {
                Matrix.Point p = geometry.order[i];
                bits.Append(unmasked[p.y][p.x]);
            }
            int[][] blocks = layout.Deinterleave(Bitstream.ToCodewords(bits.ToString())),
                    corrected = new int [layout.count][];
            bool failed = false;
            for (int b = 0; b < blocks.Length; b++) {
                ReedSolomon.Correction result = ReedSolomon.Correct(blocks[b], layout.degree);
                prefix = "block " + b + " syndromes " + Bitstream.Hexadecimal(result.syndromes);
                string status;
                if (result.corrected == null) {
                    status = "failed";
                    attempt.lines.Add(prefix + " failed");
                    failed = true;
                } else if (result.positions.Count != 0) {
                    status = "corrected";
                    attempt.lines.Add(prefix + " corrected " + JoinIntegers(result.positions));
                } else {
                    status = "ok";
                    attempt.lines.Add(prefix + " ok");
                }
                attempt.blocks.Add(new BlockResult(status, result.positions.Count));
                corrected[b] = result.corrected;
            }
            if (failed)
                return attempt;
            int[] data = new int[layout.data];
            int offset = 0;
            for (int b = 0; b < layout.count; b++) {
                Array.Copy(corrected[b], 0, data, offset, layout.lengths[b]);
                offset += layout.lengths[b];
            }
            ParseData(attempt, Bitstream.FromCodewords(data), version);
            return attempt;
        }
        public Attempt Decode(int[][] symbol) {
            int rotations = FinderRotation(symbol);
            int[][] oriented = symbol;
            for (int i = 0; i < rotations; i++)
                oriented = Rotate(oriented);
            Attempt adopted = Attempt(oriented);
            bool mirrored = false;
            if (adopted.text == null) {
                Attempt second = Attempt(Transpose(oriented));
                if (second.text != null) {
                    adopted = second;
                    mirrored = true;
                }
            }
            adopted.lines.Insert(0, "orientation rotations " + rotations + " mirrored " +
                                        (mirrored ? "yes" : "no"));
            return adopted;
        }
    }
    public static string JoinIntegers(IEnumerable<int> values) {
        List<string> pieces = new();
        foreach (int value in values)
            pieces.Add(Convert.ToString(value));
        return string.Join(" ", pieces);
    }
    public static string JoinIntegers(int[] values) {
        List<string> pieces = new();
        foreach (int value in values)
            pieces.Add(Convert.ToString(value));
        return string.Join(" ", pieces);
    }
    public static List<string> CodesLines(Encoding encoding, Codec codec) {
        Request request = encoding.request;
        Geometry layout = encoding.layout;
        BlockLayout blocks = encoding.blockLayout;
        List<string> lines = new();
        lines.Add("symbol version " + request.version + " level " + request.level + " mask " +
                  encoding.mask + " size " + layout.size);
        List<string> segments = new();
        foreach (Segment segment in request.segments)
            segments.Add(segment.mode + ":" + segment.text.Length);
        lines.Add("segments " + segments.Count + " " + string.Join(" ", segments));
        List<string> alternatives = new();
        foreach (string mode in MODES)
            alternatives.Add(
                mode + " " +
                (Encodable(mode, request.text)
                     ? Convert.ToString(SegmentWidth(mode, request.text, request.version))
                     : "-"));
        alternatives.Add("MIXED " + (request.mode.Equals("MIXED")
                                         ? request.bitCount
                                         : MixedSegments(request.text, request.version).bits));
        lines.Add("bits data " + request.bitCount + " capacity " + blocks.capacity +
                  " alternatives " + string.Join(" ", alternatives));
        List<string> fits = new();
        foreach (string level in LEVELS) {
            string fitting = "-";
            for (int v = 1; v <= 10; v++)
                if (request.Split(v).bits <= codec.Table(v, level).capacity) {
                    fitting = Convert.ToString(v);
                    break;
                }
            fits.Add(level + " " + fitting);
        }
        lines.Add("fits " + string.Join(" ", fits));
        lines.Add("modules function " + layout.functionModules + " data " + layout.dataModules +
                  " remainder " + (layout.dataModules - 8 * blocks.total) + " dark " +
                  encoding.dark);
        lines.Add("format " +
                  Bitstream.Binary(Matrix.FormatInformation(request.level, encoding.mask), 15) +
                  " version " +
                  (request.version >= 7
                       ? Bitstream.Binary(Matrix.VersionInformation(request.version), 18)
                       : "none"));
        for (int m = 0; m < 8; m++) {
            Masking.Penalty p = encoding.penalties[m];
            lines.Add("penalty " + m + " n1 " + p.n1 + " n2 " + p.n2 + " n3 " + p.n3 + " n4 " +
                      p.n4 + " total " + p.Total());
        }
        lines.AddRange(Render.SymbolLines(encoding.symbol));
        return lines;
    }
    public static List<string> CodewordLines(Encoding encoding) {
        Request request = encoding.request;
        BlockLayout layout = encoding.blockLayout;
        List<string> lines = new();
        lines.Add("request " + request.identifier + " version " + request.version + " level " +
                  request.level + " blocks " + layout.count + " data " + layout.data +
                  " ec_per_block " + layout.degree + " total " + layout.total);
        for (int b = 0; b < layout.count; b++) {
            lines.Add("block " + b + " data " +
                      Bitstream.Hexadecimal(encoding.blocks[b][(0)..(layout.lengths[b])]));
            lines.Add("block " + b + " ec " +
                      Bitstream.Hexadecimal(
                          encoding.blocks[b][(layout.lengths[b])..(encoding.blocks[b].Length)]));
        }
        lines.Add("interleaved " + Bitstream.Hexadecimal(encoding.codewords));
        return lines;
    }
    public static List<string> BitstreamLines(Encoding encoding) {
        Request request = encoding.request;
        List<string> lines = new();
        lines.Add("request " + request.identifier + " version " + request.version + " bits " +
                  request.bitCount + " capacity " + encoding.blockLayout.capacity);
        lines.AddRange(encoding.trace);
        Padding p = encoding.padding;
        lines.Add("terminator " + p.terminator + " zero_fill " + p.zeroFill + " pad_bytes " +
                  p.padBytes);
        return lines;
    }
    public static Image ReadImage(string path) {
        List<string> lines = File.ReadAllLines(path, System.Text.Encoding.ASCII).ToList();
        string[] dimensions = lines[1].Split(" ");
        int width = int.Parse(dimensions[0]), height = int.Parse(dimensions[1]), left = width,
            right = 0, top = height;
        int[][] pixels = Enumerable.Range(0, height)
                             .Select(
                                 _ => new int[width])
                             .ToArray();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                pixels[y][x] = lines[y + 2][x] - '0';
                if (pixels[y][x] == 1) {
                    left = Math.Min(left, x);
                    right = Math.Max(right, x);
                    top = Math.Min(top, y);
                }
            }
        int run = 0;
        while (left + run < width && pixels[top][left + run] == 1)
            run++;
        int unit = run / 7, size = (right - left + 1) / unit;
        int[][] symbol = Enumerable.Range(0, size)
                             .Select(
                                 _ => new int[size])
                             .ToArray();
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
                symbol[y][x] = pixels[top + unit * y][left + unit * x];
        bool wellFormed = true;
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
    public static Damaged DamagedSymbol(Encoding encoding, List<Damage> operations) {
        int[][] symbol = Matrix.Copy(encoding.symbol);
        foreach (Damage operation in operations) {
            int[] a = operation.arguments;
            if (operation.operation.Equals("flip"))
                symbol[a[1]][a[0]] ^= 1;
            else if (operation.operation.Equals("fill"))
                for (int y = a[1]; y < a[1] + a[3]; y++)
                    for (int x = a[0]; x < a[0] + a[2]; x++)
                        symbol[y][x] = a[4];
        }
        int[] counts = new int[5];
        List<HashSet<int>> damagedWords = new();
        for (int b = 0; b < encoding.blockLayout.count; b++)
            damagedWords.Add(new());
        for (int y = 0; y < symbol.Length; y++)
            for (int x = 0; x < symbol.Length; x++)
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
                            Placement p = encoding.blockLayout.placement[index / 8];
                            damagedWords[p.block].Add(p.position);
                        } else
                            counts[4]++;
                    }
                }
        foreach (Damage operation in operations)
            if (operation.operation.Equals("rotate"))
                symbol = Rotate(symbol);
            else if (operation.operation.Equals("mirror"))
                symbol = Transpose(symbol);
        int total = 0;
        foreach (int count in counts)
            total += count;
        List<int> errors = new();
        foreach (HashSet<int> words in damagedWords)
            errors.Add(words.Count);
        return new Damaged(symbol, new List<string> {
            "check damaged operations " + operations.Count,
            "damage changed " + total + " function " + counts[0] + " format " + counts[1] +
                " version " + counts[2] + " data " + counts[3] + " remainder " + counts[4],
            "errors " + JoinIntegers(errors) + " limit " + (encoding.blockLayout.degree / 2)
        });
    }
    public static int Tolerance(Encoding encoding, Codec codec, int color) {
        int size = encoding.layout.size;
        for (int side = 1; side <= size; side++) {
            int[][] symbol = Matrix.Copy(encoding.symbol);
            int start = (size - side) / 2;
            for (int y = start; y < start + side; y++)
                for (int x = start; x < start + side; x++)
                    symbol[y][x] = color;
            if (!encoding.request.text.Equals(codec.Decode(symbol).text))
                return side - 1;
        }
        return size;
    }
    public sealed class Summary {
        public Dictionary<string, int> totals = new(), errors = new(), modes = new(),
                                       levels = new(), checks = new(), blocks = new(),
                                       scans = new();
        public int[] versions = new int[11], masks = new int[8];
        public static int Get(Dictionary<string, int> map, string key) {
            return map.GetValueOrDefault(key, 0);
        }
        public static void Add(Dictionary<string, int> map, string key, int amount) {
            map[key] = Get(map, key) + amount;
        }
        public static string Named(Dictionary<string, int> map, List<string> names) {
            List<string> items = new();
            foreach (string name in names)
                items.Add(name + " " + Get(map, name));
            return string.Join(" ", items);
        }
        public static int Sum(Dictionary<string, int> map) {
            int sum = 0;
            foreach (int value in map.Values)
                sum += value;
            return sum;
        }
        public void RecordError(string error) { Add(errors, error.Split(" ")[0], 1); }
        public void RecordEncoding(Encoding encoding) {
            Request r = encoding.request;
            Add(totals, "encoded", 1);
            Add(modes, r.mode, 1);
            Add(levels, r.level, 1);
            Add(totals, "boosted", r.boosted ? 1 : 0);
            versions[r.version]++;
            masks[encoding.mask]++;
            Add(totals, "segments", r.segments.Count);
            Add(totals, "data", encoding.blockLayout.data);
            Add(totals, "ec", encoding.blockLayout.degree * encoding.blockLayout.count);
            Add(totals, "modules", encoding.layout.size * encoding.layout.size);
            Add(totals, "dark", encoding.dark);
        }
        public string RecordCheck(Attempt attempt, string text) {
            string result = attempt.text == null        ? "failed"
                            : attempt.text.Equals(text) ? "ok"
                                                        : "mismatch";
            Add(checks, result, 1);
            foreach (BlockResult block in attempt.blocks) {
                Add(blocks, block.status, 1);
                Add(totals, "corrected_positions", block.positions);
            }
            return result;
        }
        public List<string> Lines(int requests) {
            return new List<string> {
                "requests " + requests + " encoded " + Get(totals, "encoded") + " errors " +
                    Sum(errors),
                "error_kinds " + Named(errors, ERROR_KINDS),
                "modes " +
                    Named(modes, new List<string> { "NUMERIC", "ALPHANUMERIC", "BYTE", "MIXED" }),
                "levels " + Named(levels, LEVELS) + " boosted " + Get(totals, "boosted"),
                "versions " + JoinIntegers(versions[(1)..(11)]),
                "masks " + JoinIntegers(masks),
                "segments " + Get(totals, "segments") + " data_codewords " + Get(totals, "data") +
                    " ec_codewords " + Get(totals, "ec"),
                "modules " + Get(totals, "modules") + " dark " + Get(totals, "dark"),
                "checks " + Sum(checks) + " " +
                    Named(checks, new List<string> { "ok", "mismatch", "failed" }),
                "blocks " + Named(blocks, new List<string> { "ok", "corrected", "failed" }) +
                    " codewords " + Get(totals, "corrected_positions"),
                "scans " + Sum(scans) + " decoded " + Get(scans, "decoded") + " failed " +
                    Get(scans, "failed")
            };
        }
    }
    public static List<string> CheckLines(Encoding encoding, Codec codec, int quiet, int scale,
                                          List<Damage> operations, Summary summary, string output) {
        Request request = encoding.request;
        string path = Path.Combine(output, "qr_" + request.identifier + ".pbm");
        File.WriteAllText(path, Render.PbmText(encoding.symbol, quiet, scale),
                          System.Text.Encoding.ASCII);
        Image image = ReadImage(path);
        List<string> lines =
            new(new List<string> { "request " + request.identifier, image.line, "check clean" });
        Attempt attempt = codec.Decode(image.symbol);
        lines.AddRange(attempt.lines);
        lines.Add("result " + summary.RecordCheck(attempt, request.text));
        if (operations.Count != 0) {
            Damaged damaged = DamagedSymbol(encoding, operations);
            lines.AddRange(damaged.lines);
            attempt = codec.Decode(damaged.symbol);
            lines.AddRange(attempt.lines);
            lines.Add("result " + summary.RecordCheck(attempt, request.text));
        }
        lines.Add("tolerance light " + Tolerance(encoding, codec, 0) + " dark " +
                  Tolerance(encoding, codec, 1));
        return lines;
    }
    public static List<string> CapacityLines(Codec codec) {
        List<string> lines = new();
        for (int v = 1; v <= 10; v++) {
            Geometry geometry = codec.Geometry(v);
            int total = codec.Table(v, "L").total;
            string alignment =
                codec.alignments[v].Length == 0 ? "none" : JoinIntegers(codec.alignments[v]);
            lines.Add("version " + v + " size " + geometry.size + " data_modules " +
                      geometry.dataModules + " codewords " + total + " remainder " +
                      (geometry.dataModules - 8 * total) + " alignment " + alignment);
            foreach (string level in LEVELS) {
                BlockLayout layout = codec.Table(v, level);
                int[] maxima = new int[3];
                for (int m = 0; m < 3; m++)
                    while (4 + CountWidth(MODES[m], v) + DataWidth(MODES[m], maxima[m] + 1) <=
                           layout.capacity)
                        maxima[m]++;
                lines.Add("level " + level + " blocks " + layout.count + " data " + layout.data +
                          " ec_per_block " + layout.degree + " numeric " + maxima[0] +
                          " alphanumeric " + maxima[1] + " byte " + maxima[2]);
            }
        }
        return lines;
    }
    public static List<string> ReadLines(string name) {
        return File.ReadAllLines(Path.Combine("input", name + ".txt"), System.Text.Encoding.ASCII)
            .ToList();
    }
    public static void WriteLines(string output, string name, List<string> lines) {
        File.WriteAllText(Path.Combine(output, name + ".txt"),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n",
                          System.Text.Encoding.ASCII);
    }
    public static void Main(string[] args) {
        System.Globalization.CultureInfo.CurrentCulture =
            System.Globalization.CultureInfo.InvariantCulture;
        List<Request> requests = new();
        foreach (string line in ReadLines("requests")) {
            int colon = line.IndexOf(':');
            requests.Add(
                new Request(line.Substring(0, colon - (0)).Split(" "), line.Substring(colon + 1)));
        }
        List<string> settings = ReadLines("params");
        int quiet = int.Parse(settings[0].Split(" ")[1]),
            scale = int.Parse(settings[1].Split(" ")[1]);
        BlockLayout[][] tables = Enumerable.Range(0, 11)
                                     .Select(
                                         _ => new BlockLayout[4])
                                     .ToArray();
        int[][] alignments = new int [11][];
        foreach (string line in ReadLines("tables")) {
            string[] fields = line.Split(" ");
            int v = int.Parse(fields[1]);
            if (fields[0].Equals("block"))
                tables[v][LEVELS.IndexOf(fields[2])] = new BlockLayout(
                    int.Parse(fields[3]), int.Parse(fields[4]), int.Parse(fields[5]),
                    int.Parse(fields[6]), int.Parse(fields[7]));
            else {
                alignments[v] = new int[fields.Length - 2];
                for (int i = 2; i < fields.Length; i++)
                    alignments[v][i - 2] = int.Parse(fields[i]);
            }
        }
        Dictionary<string, List<Damage>> damage = new();
        foreach (string line in ReadLines("damage")) {
            string[] fields = line.Split(" ");
            int[] arguments = new int [fields [1].Equals("flip")   ? 2
                                       : fields [1].Equals("fill") ? 5
                                                                   : 0];
            for (int i = 0; i < arguments.Length; i++)
                arguments[i] =
                    i == 4 ? (fields[i + 2].Equals("dark") ? 1 : 0) : int.Parse(fields[i + 2]);
            if (!damage.ContainsKey(fields[0]))
                damage[fields[0]] = new();
            damage[fields[0]].Add(new Damage(fields[1], arguments));
        }
        List<string> scanLines = ReadLines("scans");
        List<Scan> scans = new();
        for (int i = 0; i < scanLines.Count;) {
            string name = scanLines[i].Split(" ")[1];
            int size = scanLines[i + 1].Length;
            int[][] symbol = Enumerable.Range(0, size)
                                 .Select(
                                     _ => new int[size])
                                 .ToArray();
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                    symbol[y][x] = scanLines[i + 1 + y][x] == '#' ? 1 : 0;
            scans.Add(new Scan(name, symbol));
            i += size + 1;
        }
        Codec codec = new Codec(tables, alignments);
        Summary summary = new Summary();
        string output = Path.Combine("output");
        Directory.CreateDirectory(output);
        Dictionary<string, List<string>> reports = new();
        foreach (string name in new List<string> { "codes", "codewords", "bitstream", "selfcheck",
                                                   "scans" })
            reports[name] = new();
        foreach (Request request in requests) {
            reports["codes"].Add("request " + request.identifier);
            string error = request.Prepare(codec);
            if (error != null) {
                reports["codes"].Add("error " + error);
                summary.RecordError(error);
                continue;
            }
            Encoding encoding = new Encoding(request, codec);
            reports["codes"].AddRange(CodesLines(encoding, codec));
            reports["codewords"].AddRange(CodewordLines(encoding));
            reports["bitstream"].AddRange(BitstreamLines(encoding));
            summary.RecordEncoding(encoding);
            reports["selfcheck"].AddRange(
                CheckLines(encoding, codec, quiet, scale,
                           damage.GetValueOrDefault(request.identifier, new()), summary, output));
        }
        foreach (Scan scan in scans) {
            List<string> lines = reports["scans"];
            lines.Add("scan " + scan.name + " size " + scan.symbol.Length);
            Attempt attempt = codec.Decode(scan.symbol);
            lines.AddRange(attempt.lines);
            string result = attempt.text == null ? "failed" : "decoded";
            lines.Add("result " + result);
            Summary.Add(summary.scans, result, 1);
        }
        reports["capacity"] = CapacityLines(codec);
        reports["summary"] = summary.Lines(requests.Count);
        foreach (KeyValuePair<string, List<string>> entry in reports)
            WriteLines(output, entry.Key, entry.Value);
    }
}
