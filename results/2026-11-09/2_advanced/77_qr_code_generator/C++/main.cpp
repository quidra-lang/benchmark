#include "qr.hpp"
static const std::array<std::string, 3> modes{"NUMERIC", "ALPHANUMERIC", "BYTE"};
static const std::string levels = "LMQH";
static Lines read_lines(const std::string &path) {
    std::ifstream file(path);
    Lines lines;
    std::string source;
    while (std::getline(file, source))
        lines.push_back(source);
    return lines;
}
static Lines fields(const std::string &source) {
    std::istringstream input(source);
    Lines out;
    std::string field;
    while (input >> field)
        out.push_back(field);
    return out;
}
static std::string join(const Lines &values, const std::string &separator = " ") {
    std::string out;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i)
            out += separator;
        out += values[i];
    }
    return out;
}
static void extend(Lines &out, const Lines &other) {
    out.insert(out.end(), other.begin(), other.end());
}
static int count_width(int mode, int version) {
    const int widths[2][3] = {{10, 9, 8}, {12, 11, 16}};
    return widths[version == 10][mode];
}
static int data_width(int mode, int count) {
    const int remainder[] = {0, 4, 7};
    return mode == 0   ? 10 * (count / 3) + remainder[count % 3]
           : mode == 1 ? 11 * (count / 2) + 6 * (count % 2)
                       : 8 * count;
}
static bool encodable(int mode, char c) {
    return mode == 0   ? c >= '0' && c <= '9'
           : mode == 1 ? alphanumeric.find(c) != std::string::npos
                       : c >= 32 && c <= 126;
}
static bool encodable(int mode, const std::string &source) {
    return std::all_of(source.begin(), source.end(), [&](char c) { return encodable(mode, c); });
}
static int segment_width(int mode, int count, int version) {
    return 4 + count_width(mode, version) + data_width(mode, count);
}
struct Segment {
    int mode;
    std::string characters;
};
struct Split {
    std::vector<Segment> segments;
    int bits = 0;
};
static Split mixed_segments(const std::string &source, int version) {
    std::array<std::array<int, 401>, 3> invalid{};
    int length = int(source.size());
    for (int i = 0; i < length; ++i)
        for (int mode = 0; mode < 3; ++mode)
            invalid[mode][i + 1] = invalid[mode][i] + !encodable(mode, source[i]);
    std::array<int, 401> costs{}, starts{}, choices{};
    for (int end = 1; end <= length; ++end) {
        costs[end] = 1000000;
        for (int start = 0; start < end; ++start)
            for (int mode = 0; mode < 3; ++mode)
                if (invalid[mode][end] == invalid[mode][start]) {
                    int cost = costs[start] + segment_width(mode, end - start, version);
                    if (cost < costs[end]) {
                        costs[end] = cost;
                        starts[end] = start;
                        choices[end] = mode;
                    }
                }
    }
    Split out;
    out.bits = costs[length];
    for (int end = length; end; end = starts[end])
        out.segments.push_back({choices[end], source.substr(starts[end], end - starts[end])});
    std::reverse(out.segments.begin(), out.segments.end());
    return out;
}
struct Padding {
    std::string bits;
    int terminator, zero_fill, pad_bytes;
};
static Padding pad_bits(std::string bits, int capacity) {
    Padding out;
    out.terminator = std::min(4, capacity - int(bits.size()));
    bits.append(out.terminator, '0');
    out.zero_fill = (8 - int(bits.size()) % 8) % 8;
    bits.append(out.zero_fill, '0');
    out.pad_bytes = (capacity - int(bits.size())) / 8;
    for (int i = 0; i < out.pad_bytes; ++i)
        bits += i % 2 == 0 ? "11101100" : "00010001";
    out.bits = std::move(bits);
    return out;
}
struct Placement {
    int block, position;
};
struct BlockLayout {
    int degree = 0, data = 0, capacity = 0, total = 0;
    Words lengths;
    std::vector<Placement> placement;
    BlockLayout() = default;
    BlockLayout(int e, int b1, int k1, int b2, int k2) : degree(e) {
        lengths.insert(lengths.end(), b1, k1);
        lengths.insert(lengths.end(), b2, k2);
        int maximum = 0;
        for (int length : lengths) {
            data += length;
            maximum = std::max(maximum, length);
        }
        capacity = 8 * data;
        total = data + e * int(lengths.size());
        for (int i = 0; i < maximum; ++i)
            for (int b = 0; b < int(lengths.size()); ++b)
                if (i < lengths[b])
                    placement.push_back({b, i});
        for (int i = 0; i < e; ++i)
            for (int b = 0; b < int(lengths.size()); ++b)
                placement.push_back({b, lengths[b] + i});
    }
    std::vector<Words> deinterleave(const Words &words) const {
        std::vector<Words> blocks;
        for (int length : lengths)
            blocks.emplace_back(length + degree);
        for (int i = 0; i < int(placement.size()); ++i)
            blocks[placement[i].block][placement[i].position] = words[i];
        return blocks;
    }
};
struct Attempt {
    Lines lines;
    std::optional<std::string> decoded;
    std::array<int, 3> blocks{};
    int corrected_positions = 0;
};
static Matrix rotate(const Matrix &symbol) {
    Matrix out;
    out.size = symbol.size;
    for (int y = 0; y < out.size; ++y)
        for (int x = 0; x < out.size; ++x)
            out.cells[y][x] = symbol.cells[out.size - 1 - x][y];
    return out;
}
static Matrix transpose(const Matrix &symbol) {
    Matrix out;
    out.size = symbol.size;
    for (int y = 0; y < out.size; ++y)
        for (int x = 0; x < out.size; ++x)
            out.cells[y][x] = symbol.cells[x][y];
    return out;
}
static int finder_rotation(const Matrix &symbol) {
    int n = symbol.size;
    std::array<Point, 4> corners{{{n - 7, n - 7}, {n - 7, 0}, {0, 0}, {0, n - 7}}};
    int best = 100, chosen = 0;
    for (int k = 0; k < 4; ++k) {
        int score = 0;
        for (int y = 0; y < 7; ++y)
            for (int x = 0; x < 7; ++x)
                score += symbol.cells[corners[k].y + y][corners[k].x + x] ==
                         (std::max(std::abs(x - 3), std::abs(y - 3)) != 2);
        if (score < best) {
            best = score;
            chosen = k;
        }
    }
    return chosen;
}
static void parse_data(Attempt &attempt, const std::string &bits, int version) {
    BitReader reader{bits};
    std::string decoded;
    int end = 0;
    while (reader.remaining() >= 4) {
        int indicator = reader.read(4);
        if (!indicator)
            break;
        int mode = indicator == 1 ? 0 : indicator == 2 ? 1 : indicator == 4 ? 2 : -1;
        if (mode < 0) {
            line(attempt.lines, "parse failed indicator ", binary(indicator, 4));
            return;
        }
        int width = count_width(mode, version);
        if (reader.remaining() < width) {
            line(attempt.lines, "parse failed length ", modes[mode]);
            return;
        }
        int count = reader.read(width);
        if (reader.remaining() < data_width(mode, count)) {
            line(attempt.lines, "parse failed length ", modes[mode]);
            return;
        }
        int remaining = count;
        bool valid = true;
        while (remaining) {
            int group = std::min(mode == 0 ? 3 : mode == 1 ? 2 : 1, remaining);
            int widths[] = {0, 4, 7, 10};
            int value = reader.read(mode == 0   ? widths[group]
                                    : mode == 1 ? (group == 2 ? 11 : 6)
                                                : 8);
            if (mode == 0) {
                int maximum = group == 3 ? 1000 : group == 2 ? 100 : 10;
                if (value >= maximum)
                    valid = false;
                else {
                    std::string digits = std::to_string(value);
                    decoded.append(group - digits.size(), '0');
                    decoded += digits;
                }
            } else if (mode == 1) {
                if (value >= (group == 2 ? 2025 : 45))
                    valid = false;
                else {
                    if (group == 2)
                        decoded += alphanumeric[value / 45];
                    decoded += alphanumeric[value % 45];
                }
            } else {
                if (value < 32 || value > 126)
                    valid = false;
                else
                    decoded += char(value);
            }
            if (!valid)
                break;
            remaining -= group;
        }
        if (!valid) {
            line(attempt.lines, "parse failed value ", modes[mode]);
            return;
        }
        line(attempt.lines, "segment ", modes[mode], " ", count);
        end = reader.position;
    }
    Padding expected = pad_bits(bits.substr(0, end), int(bits.size()));
    line(attempt.lines, "padding ", expected.bits == bits ? "ok" : "bad");
    attempt.decoded = decoded;
    line(attempt.lines, "text \"", decoded, "\"");
}
static int hamming(int value) {
    int count = 0;
    while (value) {
        value &= value - 1;
        ++count;
    }
    return count;
}
class Codec {
    std::array<std::optional<Geometry>, 11> geometries;

  public:
    std::array<std::array<BlockLayout, 4>, 11> tables;
    std::array<Words, 11> alignments;
    ReedSolomon rs;
    Geometry &geometry(int version) {
        if (!geometries[version])
            geometries[version] = function_matrix(version, alignments[version]);
        return *geometries[version];
    }
    Attempt attempt(const Matrix &symbol) {
        Attempt out;
        int version = (symbol.size - 17) / 4;
        auto positions = format_positions(symbol.size);
        int f1 = read_value(symbol, positions[0]), f2 = read_value(symbol, positions[1]);
        struct Nearest {
            int distance = 100, level = 0, mask = 0;
        };
        auto nearest_format = [&](int value) {
            Nearest best;
            for (int level = 0; level < 4; ++level)
                for (int mask = 0; mask < 8; ++mask) {
                    int distance = hamming(value ^ format_information(level, mask));
                    if (distance < best.distance)
                        best = {distance, level, mask};
                }
            return best;
        };
        Nearest first = nearest_format(f1), second = nearest_format(f2),
                chosen = second.distance < first.distance ? second : first;
        std::string prefix = text("format ", binary(f1, 15), " ", binary(f2, 15), " distance ",
                                  first.distance, " ", second.distance);
        if (chosen.distance > 3) {
            line(out.lines, prefix, " unreadable");
            return out;
        }
        int level = chosen.level, mask = chosen.mask;
        line(out.lines, prefix, " level ", levels[level], " mask ", mask);
        if (version >= 7) {
            auto version_fields = version_positions(symbol.size);
            int g1 = read_value(symbol, version_fields[0]),
                g2 = read_value(symbol, version_fields[1]);
            auto nearest_version = [&](int value) {
                std::pair<int, int> best{100, 7};
                for (int v = 7; v <= 40; ++v) {
                    int distance = hamming(value ^ version_information(v));
                    if (distance < best.first)
                        best = {distance, v};
                }
                return best;
            };
            auto a = nearest_version(g1), b = nearest_version(g2),
                 selected = b.first < a.first ? b : a;
            prefix = text("version ", binary(g1, 18), " ", binary(g2, 18), " distance ", a.first,
                          " ", b.first);
            if (selected.first > 3) {
                line(out.lines, prefix, " unreadable");
                return out;
            }
            line(out.lines, prefix, " decoded ", selected.second);
            if (selected.second != version)
                return out;
        }
        Geometry &g = geometry(version);
        const BlockLayout &layout = tables[version][level];
        Matrix unmasked = apply_mask(symbol, g.order, mask);
        std::string bits;
        for (int i = 0; i < 8 * layout.total; ++i)
            bits += char('0' + unmasked.cells[g.order[i].y][g.order[i].x]);
        std::vector<Words> blocks = layout.deinterleave(to_codewords(bits));
        bool failed = false;
        Words data;
        for (int b = 0; b < int(blocks.size()); ++b) {
            Correction result = rs.correct(blocks[b], layout.degree);
            prefix = text("block ", b, " syndromes ", hexadecimal(result.syndromes));
            if (!result.success) {
                line(out.lines, prefix, " failed");
                ++out.blocks[2];
                failed = true;
            } else {
                if (result.positions.empty()) {
                    line(out.lines, prefix, " ok");
                    ++out.blocks[0];
                } else {
                    Lines positions_text;
                    for (int position : result.positions)
                        positions_text.push_back(std::to_string(position));
                    line(out.lines, prefix, " corrected ", join(positions_text));
                    ++out.blocks[1];
                    out.corrected_positions += int(result.positions.size());
                }
                data.insert(data.end(), result.corrected.begin(),
                            result.corrected.begin() + layout.lengths[b]);
            }
        }
        if (!failed)
            parse_data(out, from_codewords(data), version);
        return out;
    }
    Attempt decode(Matrix symbol) {
        int rotations = finder_rotation(symbol);
        for (int i = 0; i < rotations; ++i)
            symbol = rotate(symbol);
        Attempt adopted = attempt(symbol);
        bool mirrored = false;
        if (!adopted.decoded) {
            Attempt other = attempt(transpose(symbol));
            if (other.decoded) {
                adopted = std::move(other);
                mirrored = true;
            }
        }
        adopted.lines.insert(adopted.lines.begin(), text("orientation rotations ", rotations,
                                                         " mirrored ", mirrored ? "yes" : "no"));
        return adopted;
    }
};
struct Request {
    std::string identifier, level_token, mode_token, version_token, mask_token, characters;
    int mode = 0, version = 0, level = 0, bit_count = 0;
    bool boosted = false;
    std::array<std::optional<Split>, 2> splits;
    const Split &split(int v) {
        int category = v == 10;
        if (!splits[category])
            splits[category] = mode == 3 ? mixed_segments(characters, v)
                                         : Split{{{mode, characters}},
                                                 segment_width(mode, int(characters.size()), v)};
        return *splits[category];
    }
    std::string prepare(Codec &codec) {
        bool valid_level = level_token.size() >= 1 && level_token.size() <= 2 &&
                           levels.find(level_token[0]) != std::string::npos &&
                           (level_token.size() == 1 || level_token[1] == '+');
        if (!valid_level)
            return "level " + level_token;
        if (mode_token != "NUMERIC" && mode_token != "ALPHANUMERIC" && mode_token != "BYTE" &&
            mode_token != "AUTO" && mode_token != "MIXED")
            return "mode " + mode_token;
        bool valid_version = version_token == "AUTO";
        for (int i = 1; i <= 10; ++i)
            valid_version |= version_token == std::to_string(i);
        if (!valid_version)
            return "version " + version_token;
        bool valid_mask = mask_token == "AUTO";
        for (int i = 0; i < 8; ++i)
            valid_mask |= mask_token == std::to_string(i);
        if (!valid_mask)
            return "mask " + mask_token;
        if (characters.empty())
            return "text";
        mode = mode_token == "NUMERIC"        ? 0
               : mode_token == "ALPHANUMERIC" ? 1
               : mode_token == "BYTE"         ? 2
                                              : 3;
        if (mode < 2)
            for (int i = 0; i < int(characters.size()); ++i)
                if (!encodable(mode, characters[i]))
                    return text("charset position ", i);
        if (mode_token == "AUTO") {
            mode = 0;
            while (!encodable(mode, characters))
                ++mode;
        }
        int base = int(levels.find(level_token[0]));
        int first = version_token == "AUTO" ? 1 : std::stoi(version_token),
            last = version_token == "AUTO" ? 10 : first, bits = 0, capacity = 0;
        for (int candidate = first; candidate <= last; ++candidate) {
            bits = split(candidate).bits;
            capacity = codec.tables[candidate][base].capacity;
            if (bits <= capacity) {
                version = candidate;
                break;
            }
        }
        if (!version)
            return text("capacity bits ", bits, " capacity ", capacity);
        bit_count = split(version).bits;
        level = base;
        if (level_token.size() == 2)
            for (int candidate = base; candidate < 4; ++candidate)
                if (bit_count <= codec.tables[version][candidate].capacity)
                    level = candidate;
        boosted = level != base;
        return "";
    }
};
struct Encoding {
    Request &request;
    Geometry &geometry;
    const BlockLayout &layout;
    std::string raw_bits;
    Lines trace;
    Padding padding;
    std::vector<Words> blocks;
    Words codewords;
    std::array<Penalty, 8> scores;
    int mask = 0, dark = 0;
    Matrix symbol;
    Encoding(Request &request, Codec &codec)
        : request(request), geometry(codec.geometry(request.version)),
          layout(codec.tables[request.version][request.level]) {
        BitWriter writer;
        const int indicators[] = {1, 2, 4}, widths[] = {0, 4, 7, 10};
        for (const Segment &segment : request.split(request.version).segments) {
            int mode = segment.mode, count = int(segment.characters.size()),
                width = count_width(mode, request.version);
            writer.write(indicators[mode], 4);
            writer.write(count, width);
            line(trace, "segment ", modes[mode], " indicator ", binary(indicators[mode], 4),
                 " count ", count, " ", binary(count, width));
            int step = mode == 0 ? 3 : mode == 1 ? 2 : 1;
            for (int start = 0; start < count; start += step) {
                std::string characters = segment.characters.substr(start, step);
                int value, group_width;
                if (mode == 0) {
                    value = std::stoi(characters);
                    group_width = widths[characters.size()];
                } else if (mode == 1) {
                    value = int(alphanumeric.find(characters[0]));
                    group_width = 6;
                    if (characters.size() == 2) {
                        value = value * 45 + int(alphanumeric.find(characters[1]));
                        group_width = 11;
                    }
                } else {
                    value = int(characters[0]);
                    group_width = 8;
                }
                writer.write(value, group_width);
                line(trace, "group ", value, " ", binary(value, group_width), " \"", characters,
                     "\"");
            }
        }
        raw_bits = writer.bits;
        padding = pad_bits(raw_bits, layout.capacity);
        Words data = to_codewords(padding.bits);
        int start = 0;
        for (int length : layout.lengths) {
            Words block(data.begin() + start, data.begin() + start + length);
            Words parity = codec.rs.parity(block, layout.degree);
            block.insert(block.end(), parity.begin(), parity.end());
            blocks.push_back(std::move(block));
            start += length;
        }
        for (Placement p : layout.placement)
            codewords.push_back(blocks[p.block][p.position]);
        Matrix unmasked = geometry.symbol;
        std::string bits = from_codewords(codewords);
        for (int i = 0; i < int(bits.size()); ++i)
            unmasked.cells[geometry.order[i].y][geometry.order[i].x] = bits[i] - '0';
        int best = 1000000;
        for (int m = 0; m < 8; ++m) {
            Matrix candidate = apply_mask(unmasked, geometry.order, m);
            for (const Positions &positions : format_positions(candidate.size))
                write_value(candidate, positions, format_information(request.level, m));
            scores[m] = penalties(candidate);
            if (request.mask_token == "AUTO" ? scores[m].total() < best
                                             : request.mask_token == std::to_string(m)) {
                best = scores[m].total();
                mask = m;
                symbol = candidate;
            }
        }
        for (int y = 0; y < symbol.size; ++y)
            for (int x = 0; x < symbol.size; ++x)
                dark += symbol.cells[y][x];
    }
};
struct Operation {
    std::string kind;
    int x = 0, y = 0, width = 0, height = 0, color = 0;
};
struct Scan {
    std::string name;
    Matrix symbol;
};
struct Inputs {
    std::vector<Request> requests;
    int quiet = 0, scale = 1;
    std::map<std::string, std::vector<Operation>> damage;
    std::vector<Scan> scans;
};
static Inputs read_inputs(Codec &codec) {
    Inputs out;
    for (const std::string &source : read_lines("input/requests.txt")) {
        std::size_t colon = source.find(':');
        Lines f = fields(source.substr(0, colon));
        Request request;
        request.identifier = f[0];
        request.level_token = f[1];
        request.mode_token = f[2];
        request.version_token = f[3];
        request.mask_token = f[4];
        request.characters = source.substr(colon + 1);
        out.requests.push_back(request);
    }
    Lines params = read_lines("input/params.txt");
    out.quiet = std::stoi(fields(params[0])[1]);
    out.scale = std::stoi(fields(params[1])[1]);
    for (const std::string &source : read_lines("input/tables.txt")) {
        Lines f = fields(source);
        int v = std::stoi(f[1]);
        if (f[0] == "block")
            codec.tables[v][levels.find(f[2][0])] =
                BlockLayout(std::stoi(f[3]), std::stoi(f[4]), std::stoi(f[5]), std::stoi(f[6]),
                            std::stoi(f[7]));
        else
            for (std::size_t i = 2; i < f.size(); ++i)
                codec.alignments[v].push_back(std::stoi(f[i]));
    }
    for (const std::string &source : read_lines("input/damage.txt")) {
        Lines f = fields(source);
        Operation op;
        op.kind = f[1];
        if (op.kind == "flip" || op.kind == "fill") {
            op.x = std::stoi(f[2]);
            op.y = std::stoi(f[3]);
        }
        if (op.kind == "fill") {
            op.width = std::stoi(f[4]);
            op.height = std::stoi(f[5]);
            op.color = f[6] == "dark";
        }
        out.damage[f[0]].push_back(op);
    }
    Lines scans = read_lines("input/scans.txt");
    for (std::size_t i = 0; i < scans.size();) {
        Scan scan;
        scan.name = fields(scans[i++])[1];
        scan.symbol.size = int(scans[i].size());
        for (int y = 0; y < scan.symbol.size; ++y) {
            for (int x = 0; x < scan.symbol.size; ++x)
                scan.symbol.cells[y][x] = scans[i][x] == '#';
            ++i;
        }
        out.scans.push_back(std::move(scan));
    }
    return out;
}
static Lines codes_lines(Encoding &encoding, Codec &codec) {
    Request &q = encoding.request;
    Geometry &g = encoding.geometry;
    const BlockLayout &layout = encoding.layout;
    Lines out;
    line(out, "symbol version ", q.version, " level ", levels[q.level], " mask ", encoding.mask,
         " size ", g.symbol.size);
    Lines segments;
    for (const Segment &s : q.split(q.version).segments)
        segments.push_back(text(modes[s.mode], ":", s.characters.size()));
    line(out, "segments ", segments.size(), " ", join(segments));
    Lines alternatives;
    for (int mode = 0; mode < 3; ++mode)
        alternatives.push_back(
            text(modes[mode], " ",
                 encodable(mode, q.characters)
                     ? std::to_string(segment_width(mode, int(q.characters.size()), q.version))
                     : "-"));
    alternatives.push_back(
        text("MIXED ", q.mode == 3 ? q.bit_count : mixed_segments(q.characters, q.version).bits));
    line(out, "bits data ", q.bit_count, " capacity ", layout.capacity, " alternatives ",
         join(alternatives));
    Lines fits;
    for (int level = 0; level < 4; ++level) {
        std::string fitting = "-";
        for (int version = 1; version <= 10; ++version)
            if (q.split(version).bits <= codec.tables[version][level].capacity) {
                fitting = std::to_string(version);
                break;
            }
        fits.push_back(text(levels[level], " ", fitting));
    }
    line(out, "fits ", join(fits));
    line(out, "modules function ", g.function_modules(), " data ", g.order.size(), " remainder ",
         int(g.order.size()) - 8 * layout.total, " dark ", encoding.dark);
    line(out, "format ", binary(format_information(q.level, encoding.mask), 15), " version ",
         q.version >= 7 ? binary(version_information(q.version), 18) : "none");
    for (int mask = 0; mask < 8; ++mask) {
        Penalty p = encoding.scores[mask];
        line(out, "penalty ", mask, " n1 ", p.n1, " n2 ", p.n2, " n3 ", p.n3, " n4 ", p.n4,
             " total ", p.total());
    }
    extend(out, symbol_lines(encoding.symbol));
    return out;
}
static Lines codeword_lines(const Encoding &encoding) {
    const Request &q = encoding.request;
    const BlockLayout &layout = encoding.layout;
    Lines out;
    line(out, "request ", q.identifier, " version ", q.version, " level ", levels[q.level],
         " blocks ", layout.lengths.size(), " data ", layout.data, " ec_per_block ", layout.degree,
         " total ", layout.total);
    for (int b = 0; b < int(encoding.blocks.size()); ++b) {
        const Words &words = encoding.blocks[b];
        int length = layout.lengths[b];
        line(out, "block ", b, " data ", hexadecimal(Words(words.begin(), words.begin() + length)));
        line(out, "block ", b, " ec ", hexadecimal(Words(words.begin() + length, words.end())));
    }
    line(out, "interleaved ", hexadecimal(encoding.codewords));
    return out;
}
static Lines bitstream_lines(const Encoding &encoding) {
    Lines out;
    line(out, "request ", encoding.request.identifier, " version ", encoding.request.version,
         " bits ", encoding.request.bit_count, " capacity ", encoding.layout.capacity);
    extend(out, encoding.trace);
    line(out, "terminator ", encoding.padding.terminator, " zero_fill ", encoding.padding.zero_fill,
         " pad_bytes ", encoding.padding.pad_bytes);
    return out;
}
struct Image {
    Matrix symbol;
    std::string description;
};
static Image read_image(const std::string &path) {
    Lines lines = read_lines(path), dimensions = fields(lines[1]);
    int width = std::stoi(dimensions[0]), height = std::stoi(dimensions[1]), left = width,
        right = 0, top = height;
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x)
            if (lines[y + 2][x] == '1') {
                left = std::min(left, x);
                right = std::max(right, x);
                top = std::min(top, y);
            }
    int run = 0;
    while (left + run < width && lines[top + 2][left + run] == '1')
        ++run;
    int unit = run / 7;
    Image out;
    out.symbol.size = (right - left + 1) / unit;
    for (int y = 0; y < out.symbol.size; ++y)
        for (int x = 0; x < out.symbol.size; ++x)
            out.symbol.cells[y][x] = lines[top + unit * y + 2][left + unit * x] - '0';
    bool well_formed = true;
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            int expected = 0;
            if (x >= left && x < left + unit * out.symbol.size && y >= top &&
                y < top + unit * out.symbol.size)
                expected = out.symbol.cells[(y - top) / unit][(x - left) / unit];
            well_formed &= lines[y + 2][x] - '0' == expected;
        }
    out.description = text("image ", width, " ", height, " quiet ", left / unit, " scale ", unit,
                           " size ", out.symbol.size, " ", well_formed ? "ok" : "bad");
    return out;
}
static std::pair<Matrix, Lines> damaged_symbol(const Encoding &encoding,
                                               const std::vector<Operation> &operations) {
    Matrix symbol = encoding.symbol;
    int n = symbol.size;
    for (const Operation &op : operations) {
        if (op.kind == "flip")
            symbol.cells[op.y][op.x] ^= 1;
        else if (op.kind == "fill")
            for (int y = op.y; y < op.y + op.height; ++y)
                for (int x = op.x; x < op.x + op.width; ++x)
                    symbol.cells[y][x] = op.color;
    }
    std::array<int, 5> counts{};
    std::vector<std::vector<bool>> damaged_words;
    for (int length : encoding.layout.lengths)
        damaged_words.emplace_back(length + encoding.layout.degree, false);
    for (int y = 0; y < n; ++y)
        for (int x = 0; x < n; ++x)
            if (symbol.cells[y][x] != encoding.symbol.cells[y][x]) {
                int area = encoding.geometry.areas.cells[y][x];
                if (area != Data)
                    ++counts[area - 1];
                else {
                    int index = encoding.geometry.indices[y][x];
                    if (index < 8 * encoding.layout.total) {
                        ++counts[3];
                        Placement p = encoding.layout.placement[index / 8];
                        damaged_words[p.block][p.position] = true;
                    } else
                        ++counts[4];
                }
            }
    for (const Operation &op : operations) {
        if (op.kind == "rotate")
            symbol = rotate(symbol);
        else if (op.kind == "mirror")
            symbol = transpose(symbol);
    }
    Lines out;
    line(out, "check damaged operations ", operations.size());
    int changed = 0;
    for (int count : counts)
        changed += count;
    line(out, "damage changed ", changed, " function ", counts[0], " format ", counts[1],
         " version ", counts[2], " data ", counts[3], " remainder ", counts[4]);
    Lines errors;
    for (const std::vector<bool> &words : damaged_words)
        errors.push_back(std::to_string(std::count(words.begin(), words.end(), true)));
    line(out, "errors ", join(errors), " limit ", encoding.layout.degree / 2);
    return {symbol, out};
}
static int tolerance(const Encoding &encoding, Codec &codec, int color) {
    int n = encoding.symbol.size;
    for (int side = 1; side <= n; ++side) {
        Matrix symbol = encoding.symbol;
        int start = (n - side) / 2;
        for (int y = start; y < start + side; ++y)
            for (int x = start; x < start + side; ++x)
                symbol.cells[y][x] = color;
        Attempt result = codec.decode(symbol);
        if (!result.decoded || *result.decoded != encoding.request.characters)
            return side - 1;
    }
    return n;
}
struct Summary {
    int encoded = 0, boosted = 0, segments = 0, data = 0, ec = 0, modules = 0, dark = 0,
        corrected_positions = 0;
    std::array<int, 7> errors{};
    std::array<int, 4> mode_counts{}, level_counts{};
    std::array<int, 11> versions{};
    std::array<int, 8> masks{};
    std::array<int, 3> checks{}, blocks{};
    std::array<int, 2> scans{};
    void record_encoding(const Encoding &e) {
        ++encoded;
        boosted += e.request.boosted;
        ++mode_counts[e.request.mode];
        ++level_counts[e.request.level];
        ++versions[e.request.version];
        ++masks[e.mask];
        segments += int(e.request.splits[e.request.version == 10]->segments.size());
        data += e.layout.data;
        ec += e.layout.degree * int(e.layout.lengths.size());
        modules += e.symbol.size * e.symbol.size;
        dark += e.dark;
    }
    std::string record_check(const Attempt &attempt, const std::string &expected) {
        int status = !attempt.decoded ? 2 : *attempt.decoded == expected ? 0 : 1;
        ++checks[status];
        for (int i = 0; i < 3; ++i)
            blocks[i] += attempt.blocks[i];
        corrected_positions += attempt.corrected_positions;
        return status == 0 ? "ok" : status == 1 ? "mismatch" : "failed";
    }
    Lines report(int requests) const {
        const Lines kinds{"level", "mode", "version", "mask", "text", "charset", "capacity"};
        int error_count = 0;
        for (int count : errors)
            error_count += count;
        Lines out;
        line(out, "requests ", requests, " encoded ", encoded, " errors ", error_count);
        Lines parts;
        for (int i = 0; i < 7; ++i)
            parts.push_back(text(kinds[i], " ", errors[i]));
        line(out, "error_kinds ", join(parts));
        parts.clear();
        for (int mode = 0; mode < 4; ++mode)
            parts.push_back(text(mode < 3 ? modes[mode] : "MIXED", " ", mode_counts[mode]));
        line(out, "modes ", join(parts));
        parts.clear();
        for (int level = 0; level < 4; ++level)
            parts.push_back(text(levels[level], " ", level_counts[level]));
        line(out, "levels ", join(parts), " boosted ", boosted);
        parts.clear();
        for (int version = 1; version <= 10; ++version)
            parts.push_back(std::to_string(versions[version]));
        line(out, "versions ", join(parts));
        parts.clear();
        for (int count : masks)
            parts.push_back(std::to_string(count));
        line(out, "masks ", join(parts));
        line(out, "segments ", segments, " data_codewords ", data, " ec_codewords ", ec);
        line(out, "modules ", modules, " dark ", dark);
        line(out, "checks ", checks[0] + checks[1] + checks[2], " ok ", checks[0], " mismatch ",
             checks[1], " failed ", checks[2]);
        line(out, "blocks ok ", blocks[0], " corrected ", blocks[1], " failed ", blocks[2],
             " codewords ", corrected_positions);
        line(out, "scans ", scans[0] + scans[1], " decoded ", scans[0], " failed ", scans[1]);
        return out;
    }
};
static Lines check_lines(const Encoding &e, Codec &codec, const Inputs &inputs,
                         const std::vector<Operation> &operations, Summary &summary) {
    std::string path = "output/qr_" + e.request.identifier + ".pbm";
    {
        std::ofstream file(path);
        file << pbm_text(e.symbol, inputs.quiet, inputs.scale);
    }
    Image image = read_image(path);
    Lines out;
    line(out, "request ", e.request.identifier);
    out.push_back(image.description);
    out.push_back("check clean");
    Attempt clean = codec.decode(image.symbol);
    extend(out, clean.lines);
    line(out, "result ", summary.record_check(clean, e.request.characters));
    if (!operations.empty()) {
        auto damage = damaged_symbol(e, operations);
        extend(out, damage.second);
        Attempt result = codec.decode(damage.first);
        extend(out, result.lines);
        line(out, "result ", summary.record_check(result, e.request.characters));
    }
    line(out, "tolerance light ", tolerance(e, codec, 0), " dark ", tolerance(e, codec, 1));
    return out;
}
static Lines capacity_lines(Codec &codec) {
    Lines out;
    for (int v = 1; v <= 10; ++v) {
        Geometry &g = codec.geometry(v);
        int total = codec.tables[v][0].total;
        Lines alignments;
        for (int value : codec.alignments[v])
            alignments.push_back(std::to_string(value));
        line(out, "version ", v, " size ", g.symbol.size, " data_modules ", g.order.size(),
             " codewords ", total, " remainder ", int(g.order.size()) - 8 * total, " alignment ",
             alignments.empty() ? "none" : join(alignments));
        for (int level = 0; level < 4; ++level) {
            const BlockLayout &layout = codec.tables[v][level];
            std::array<int, 3> maxima{};
            for (int mode = 0; mode < 3; ++mode)
                while (segment_width(mode, maxima[mode] + 1, v) <= layout.capacity)
                    ++maxima[mode];
            line(out, "level ", levels[level], " blocks ", layout.lengths.size(), " data ",
                 layout.data, " ec_per_block ", layout.degree, " numeric ", maxima[0],
                 " alphanumeric ", maxima[1], " byte ", maxima[2]);
        }
    }
    return out;
}
static void write(const std::string &name, const Lines &lines) {
    std::ofstream file("output/" + name + ".txt");
    for (const std::string &source : lines)
        file << source << '\n';
}
int main() {
    Codec codec;
    Inputs inputs = read_inputs(codec);
    Summary summary;
    std::map<std::string, Lines> reports;
    std::filesystem::create_directories("output");
    const Lines kinds{"level", "mode", "version", "mask", "text", "charset", "capacity"};
    for (Request &request : inputs.requests) {
        line(reports["codes"], "request ", request.identifier);
        std::string error = request.prepare(codec);
        if (!error.empty()) {
            line(reports["codes"], "error ", error);
            std::string kind = error.substr(0, error.find(' '));
            ++summary.errors[std::find(kinds.begin(), kinds.end(), kind) - kinds.begin()];
            continue;
        }
        Encoding encoding(request, codec);
        extend(reports["codes"], codes_lines(encoding, codec));
        extend(reports["codewords"], codeword_lines(encoding));
        extend(reports["bitstream"], bitstream_lines(encoding));
        summary.record_encoding(encoding);
        extend(reports["selfcheck"],
               check_lines(encoding, codec, inputs, inputs.damage[request.identifier], summary));
    }
    for (const Scan &scan : inputs.scans) {
        line(reports["scans"], "scan ", scan.name, " size ", scan.symbol.size);
        Attempt result = codec.decode(scan.symbol);
        extend(reports["scans"], result.lines);
        line(reports["scans"], "result ", result.decoded ? "decoded" : "failed");
        ++summary.scans[result.decoded ? 0 : 1];
    }
    reports["capacity"] = capacity_lines(codec);
    reports["summary"] = summary.report(int(inputs.requests.size()));
    for (const std::string &name :
         Lines{"codes", "codewords", "bitstream", "selfcheck", "scans", "capacity", "summary"})
        write(name, reports[name]);
}
