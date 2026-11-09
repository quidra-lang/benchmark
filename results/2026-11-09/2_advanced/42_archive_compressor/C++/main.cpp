#include "archive.hpp"
#include <filesystem>
static const std::array<std::string, 5> methods = {"STORE", "LZW", "LZ77", "LZH", "ARITH"};
static std::string number(Integer value) {
    return std::to_string(value);
}
static Bytes read_bytes(const std::string &path) {
    std::ifstream file(path, std::ios::binary);
    return Bytes(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
}
static Lines text_lines(const Bytes &bytes) {
    Lines lines;
    std::string line;
    for (Byte byte : bytes) {
        if (byte == 10) {
            lines.push_back(line);
            line.clear();
        } else
            line += char(byte);
    }
    return lines;
}
static Lines words(const std::string &line) {
    Lines out;
    std::istringstream input(line);
    std::string word;
    while (input >> word)
        out.push_back(word);
    return out;
}
static void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream file("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        file << line << '\n';
}
static std::string hex8(std::uint32_t value) {
    std::ostringstream out;
    out << std::hex << std::nouppercase << std::setfill('0') << std::setw(8) << value;
    return out.str();
}
static Lines hex_lines(const Bytes &bytes) {
    Lines lines;
    const char *digits = "0123456789abcdef";
    for (std::size_t first = 0; first < bytes.size(); first += 32) {
        std::string line;
        for (std::size_t i = first; i < std::min(first + 32, bytes.size()); ++i) {
            line += digits[bytes[i] >> 4];
            line += digits[bytes[i] & 15];
        }
        lines.push_back(line);
    }
    return lines;
}
static std::uint32_t adler(const Bytes &bytes) {
    std::uint32_t s1 = 1, s2 = 0;
    for (Byte byte : bytes) {
        s1 = (s1 + byte) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    return s2 * 65536 + s1;
}
static std::string ratio(Integer original, Integer compressed) {
    return original ? number(1000 * compressed / original) : "-";
}
static std::string method_name(int method) {
    return method < 5 ? methods[method] : "#" + number(method);
}
static void write_table(BitWriter &writer, const std::vector<int> &lengths) {
    std::size_t position = 0;
    while (position < lengths.size()) {
        if (lengths[position])
            writer.write(lengths[position++], 4);
        else {
            std::size_t count = 1;
            while (count < 256 && position + count < lengths.size() && lengths[position + count] == 0)
                ++count;
            writer.write(0, 4);
            writer.write(count - 1, 8);
            position += count;
        }
    }
}
static std::vector<int> read_table(BitReader &reader, int symbols) {
    std::vector<int> lengths;
    while (int(lengths.size()) < symbols) {
        const int value = reader.read(4);
        if (value)
            lengths.push_back(value);
        else {
            const int count = reader.read(8) + 1;
            if (int(lengths.size()) + count > symbols)
                throw DecodeError{"bad_table"};
            lengths.insert(lengths.end(), count, 0);
        }
    }
    int used = 0, only = 0, sum = 0;
    for (int length : lengths)
        if (length) {
            ++used;
            only = length;
            sum += 1 << (15 - length);
        }
    if ((used == 1 && only != 1) || (used >= 2 && sum != (1 << 15)))
        throw DecodeError{"bad_table"};
    return lengths;
}
static std::vector<int> fixed_lengths(int symbols) {
    const int width = bits(symbols - 1), shorter = (1 << width) - symbols;
    std::vector<int> lengths(symbols, width);
    for (int s = 0; s < shorter; ++s)
        lengths[s] = width - 1;
    return lengths;
}
static int read_symbol(BitReader &reader, const std::vector<int> &lengths, const std::vector<int> &codes) {
    int maximum = 0;
    for (int length : lengths)
        maximum = std::max(maximum, length);
    if (maximum == 0)
        throw DecodeError{"bad_code"};
    int code = 0;
    for (int width = 1; width <= maximum; ++width) {
        code = 2 * code + reader.read(1);
        for (std::size_t symbol = 0; symbol < lengths.size(); ++symbol)
            if (lengths[symbol] == width && codes[symbol] == code)
                return symbol;
    }
    throw DecodeError{"bad_code"};
}
static void token_part(BitWriter &writer, const std::vector<Token> &tokens, const std::vector<int> &lengths,
                       const std::vector<int> &distances) {
    const auto codes = canonical_codes(lengths), offset_codes = canonical_codes(distances);
    for (const Token &token : tokens) {
        const int symbol = token.match() ? 256 + token.length - 3 : token.literal;
        writer.write(codes[symbol], lengths[symbol]);
        if (token.match()) {
            const int u = token.distance - 1, slot = bits(u);
            writer.write(offset_codes[slot], distances[slot]);
            if (slot >= 2)
                writer.write(u - (1 << (slot - 1)), slot - 1);
        }
    }
}
struct LzhStats {
    bool dynamic = false;
    int fixed_bits = 0, table_bits = 0, code_bits = 0, halvings = 0, litlen_used = 0, litlen_max = 0,
        offset_used = 0, offset_max = 0;
    std::vector<int> slots;
};
static Bytes lzh_encode(const std::vector<Token> &tokens, int b, int k, int maximum, LzhStats &stats) {
    const int symbols = 256 + (1 << k);
    std::vector<int> frequency(symbols), offset_frequency(b + 1);
    stats.slots.resize(b + 1);
    for (const Token &token : tokens) {
        ++frequency[token.match() ? 256 + token.length - 3 : token.literal];
        if (token.match()) {
            const int slot = bits(token.distance - 1);
            ++offset_frequency[slot];
            ++stats.slots[slot];
        }
    }
    const Huffman literal = huffman_lengths(frequency, maximum),
                  distance = huffman_lengths(offset_frequency, maximum);
    stats.halvings = literal.halvings + distance.halvings;
    for (int length : literal.lengths) {
        stats.litlen_used += length > 0;
        stats.litlen_max = std::max(stats.litlen_max, length);
    }
    for (int length : distance.lengths) {
        stats.offset_used += length > 0;
        stats.offset_max = std::max(stats.offset_max, length);
    }
    BitWriter tables, dynamic, fixed;
    write_table(tables, literal.lengths);
    write_table(tables, distance.lengths);
    token_part(dynamic, tokens, literal.lengths, distance.lengths);
    const auto fixed_literal = fixed_lengths(symbols), fixed_distance = fixed_lengths(b + 1);
    token_part(fixed, tokens, fixed_literal, fixed_distance);
    stats.fixed_bits = fixed.count;
    stats.table_bits = tables.count;
    stats.code_bits = dynamic.count;
    stats.dynamic = stats.fixed_bits > stats.table_bits + stats.code_bits;
    BitWriter writer;
    writer.write(stats.dynamic ? 1 : 0, 1);
    if (stats.dynamic) {
        write_table(writer, literal.lengths);
        write_table(writer, distance.lengths);
        token_part(writer, tokens, literal.lengths, distance.lengths);
    } else
        token_part(writer, tokens, fixed_literal, fixed_distance);
    return writer.bytes;
}
static Bytes lz77_encode(const std::vector<Token> &tokens, int b, int k) {
    BitWriter writer;
    for (const Token &token : tokens) {
        writer.write(token.match() ? 1 : 0, 1);
        if (token.match()) {
            writer.write(token.distance - 1, b);
            writer.write(token.length - 3, k);
        } else
            writer.write(token.literal, 8);
    }
    return writer.bytes;
}
static void decode(int method, const Bytes &payload, std::uint32_t original, int b, int k, Bytes &output) {
    if (method == 0) {
        for (Byte byte : payload) {
            if (output.size() == original)
                return;
            output.push_back(byte);
        }
        if (output.size() < original)
            throw DecodeError{"end_of_data"};
    } else if (method == 1)
        lzw_decode(payload, original, output);
    else if (method == 4)
        arith_decode(payload, original, output);
    else {
        BitReader reader{payload};
        if (method == 2) {
            while (output.size() < original) {
                if (reader.read(1) == 0)
                    output.push_back(Byte(reader.read(8)));
                else {
                    const int distance = reader.read(b) + 1, length = reader.read(k) + 3;
                    output_match(output, original, distance, length);
                }
            }
        } else {
            const bool dynamic = reader.read(1) != 0;
            const auto lengths = dynamic ? read_table(reader, 256 + (1 << k)) : fixed_lengths(256 + (1 << k));
            const auto offsets = dynamic ? read_table(reader, b + 1) : fixed_lengths(b + 1);
            const auto codes = canonical_codes(lengths), offset_codes = canonical_codes(offsets);
            while (output.size() < original) {
                const int symbol = read_symbol(reader, lengths, codes);
                if (symbol < 256)
                    output.push_back(Byte(symbol));
                else {
                    const int length = symbol - 253, slot = read_symbol(reader, offsets, offset_codes);
                    const int u = slot >= 2 ? (1 << (slot - 1)) + int(reader.read(slot - 1)) : slot;
                    output_match(output, original, u + 1, length);
                }
            }
        }
    }
}
struct Encoded {
    std::array<Bytes, 5> payloads;
    int best = 0;
    std::vector<Token> tokens;
    LzwStats lzw;
    LzhStats lzh;
    ArithStats arith;
};
static Encoded encode(const Bytes &data, int b, int k, int maximum) {
    Encoded out;
    out.tokens = tokenize(data, b, k);
    out.payloads[0] = data;
    out.payloads[1] = lzw_encode(data, out.lzw);
    out.payloads[2] = lz77_encode(out.tokens, b, k);
    out.payloads[3] = lzh_encode(out.tokens, b, k, maximum, out.lzh);
    out.payloads[4] = arith_encode(data, out.arith);
    for (int method = 1; method < 5; ++method)
        if (out.payloads[method].size() < out.payloads[out.best].size())
            out.best = method;
    return out;
}
struct File {
    std::string name;
    Bytes data, payload;
    int method = 0;
};
static void big_endian(Bytes &bytes, std::uint32_t value, int count) {
    for (int shift = 8 * (count - 1); shift >= 0; shift -= 8)
        bytes.push_back(Byte((value >> shift) & 255));
}
static std::uint32_t read_integer(const Bytes &bytes, std::size_t first, int count) {
    std::uint32_t value = 0;
    for (int i = 0; i < count; ++i)
        value = (value << 8) | bytes[first + i];
    return value;
}
static Bytes build_archive(const std::vector<File> &files, int b, int k) {
    Bytes archive = {'T', 'X', 'A', 'R', Byte(b), Byte(k)};
    big_endian(archive, files.size(), 2);
    for (const File &file : files) {
        const std::size_t first = archive.size();
        archive.push_back(Byte(file.name.size()));
        archive.insert(archive.end(), file.name.begin(), file.name.end());
        archive.push_back(Byte(file.method));
        big_endian(archive, file.data.size(), 4);
        big_endian(archive, file.payload.size(), 4);
        big_endian(archive, adler(file.data), 4);
        int sum = 0;
        for (std::size_t i = first; i < archive.size(); ++i)
            sum += archive[i];
        archive.push_back(Byte(sum % 256));
        archive.insert(archive.end(), file.payload.begin(), file.payload.end());
    }
    return archive;
}
struct Entry {
    int number = 0, method = 0;
    std::size_t position = 0, start = 0;
    std::uint32_t original = 0, compressed = 0, stored = 0, computed = 0;
    std::string name, status, error;
    bool valid = false, header_cut = false;
    Bytes output;
    std::size_t error_position = 0, repair_position = 0;
    int repair_from = 0, repair_to = 0;
};
struct Parsed {
    std::string error;
    int b = 0, k = 0, declared = 0;
    std::size_t size = 0, trailing = 0;
    bool stopped = false;
    std::vector<Entry> entries;
};
static Integer modulo(Integer value, Integer modulus) {
    Integer remainder = value % modulus;
    return remainder < 0 ? remainder + modulus : remainder;
}
static Integer power_mod(Integer value, Integer exponent) {
    Integer result = 1;
    while (exponent) {
        if (exponent % 2)
            result = result * value % 65521;
        value = value * value % 65521;
        exponent /= 2;
    }
    return result;
}
static bool repair(Entry &entry) {
    const Integer delta_a = modulo(Integer(entry.stored % 65536) - Integer(entry.computed % 65536), 65521),
                  delta_b = modulo(Integer(entry.stored / 65536) - Integer(entry.computed / 65536), 65521);
    Integer delta = 0;
    if (delta_a >= 1 && delta_a <= 255)
        delta = delta_a;
    else if (delta_a >= 65266 && delta_a <= 65520)
        delta = delta_a - 65521;
    else
        return false;
    const Integer inverse = power_mod(modulo(delta, 65521), 65519), t = delta_b * inverse % 65521;
    if (t < 1 || t > Integer(entry.output.size()))
        return false;
    const std::size_t position = entry.output.size() - t;
    const int old = entry.output[position], value = old + int(delta);
    if (value < 0 || value > 255)
        return false;
    entry.output[position] = Byte(value);
    if (adler(entry.output) != entry.stored) {
        entry.output[position] = Byte(old);
        return false;
    }
    entry.repair_position = position;
    entry.repair_from = old;
    entry.repair_to = value;
    return true;
}
static bool valid_name(const std::string &name) {
    if (name.empty() || name.size() > 32)
        return false;
    for (char c : name)
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-'))
            return false;
    return true;
}
static Parsed parse(const Bytes &bytes) {
    Parsed out;
    out.size = bytes.size();
    if (bytes.size() < 8 || !std::equal(bytes.begin(), bytes.begin() + 4, std::string("TXAR").begin())) {
        out.error = "bad_magic";
        return out;
    }
    out.b = bytes[4];
    out.k = bytes[5];
    if (out.b < 6 || out.b > 12 || out.k < 2 || out.k > 5) {
        out.error = "bad_params";
        return out;
    }
    out.declared = read_integer(bytes, 6, 2);
    std::size_t position = 8;
    for (int number = 1; number <= out.declared; ++number) {
        Entry entry;
        entry.number = number;
        entry.position = position;
        if (position >= bytes.size() || position + 15 + bytes[position] > bytes.size()) {
            entry.status = "truncated";
            entry.header_cut = true;
            out.entries.push_back(std::move(entry));
            out.stopped = true;
            break;
        }
        const int length = bytes[position];
        entry.name = std::string(bytes.begin() + position + 1, bytes.begin() + position + 1 + length);
        entry.method = bytes[position + 1 + length];
        entry.original = read_integer(bytes, position + 2 + length, 4);
        entry.compressed = read_integer(bytes, position + 6 + length, 4);
        entry.stored = read_integer(bytes, position + 10 + length, 4);
        entry.start = position + 15 + length;
        const std::size_t next = entry.start + entry.compressed;
        int sum = 0;
        for (std::size_t i = position; i < entry.start - 1; ++i)
            sum += bytes[i];
        if (sum % 256 != bytes[entry.start - 1] || !valid_name(entry.name)) {
            entry.status = "bad_header";
            position = next;
            out.entries.push_back(std::move(entry));
            if (position > bytes.size()) {
                out.stopped = true;
                break;
            }
            continue;
        }
        entry.valid = true;
        if (next > bytes.size()) {
            entry.status = "truncated";
            out.entries.push_back(std::move(entry));
            out.stopped = true;
            break;
        }
        if (entry.method >= 5)
            entry.status = "unsupported";
        else {
            const Bytes payload(bytes.begin() + entry.start, bytes.begin() + next);
            try {
                decode(entry.method, payload, entry.original, out.b, out.k, entry.output);
                entry.computed = adler(entry.output);
                entry.status = entry.computed == entry.stored ? "ok"
                               : repair(entry)                ? "repaired"
                                                              : "checksum";
            } catch (const DecodeError &error) {
                entry.status = "error";
                entry.error = error.kind;
                entry.error_position = entry.output.size();
            }
        }
        out.entries.push_back(std::move(entry));
        position = next;
    }
    if (!out.stopped)
        out.trailing = bytes.size() - position;
    return out;
}
static int verified(const Parsed &parsed, const std::vector<File> &files) {
    int count = 0;
    for (std::size_t i = 0; i < parsed.entries.size() && i < files.size(); ++i)
        count += parsed.entries[i].status == "ok" && parsed.entries[i].output == files[i].data;
    return count;
}
static Lines listing(const Parsed &parsed) {
    if (!parsed.error.empty())
        return {"archive bytes " + number(parsed.size) + " error " + parsed.error};
    Lines out = {"archive bytes " + number(parsed.size) + " offset_bits " + number(parsed.b) +
                 " length_bits " + number(parsed.k) + " entries " + number(parsed.declared)};
    std::array<Integer, 5> counts{}, original{}, compressed{};
    int listed = 0;
    for (const Entry &entry : parsed.entries) {
        const std::string prefix = "entry " + number(entry.number) + " offset " + number(entry.position);
        if (entry.header_cut)
            out.push_back(prefix + " truncated header");
        else if (!entry.valid)
            out.push_back(prefix + " bad_header");
        else {
            ++listed;
            out.push_back(prefix + " method " + method_name(entry.method) + " original " +
                          number(entry.original) + " compressed " + number(entry.compressed) + " ratio " +
                          ratio(entry.original, entry.compressed) + " adler " + hex8(entry.stored) +
                          " name " + entry.name);
            if (entry.method < 5) {
                ++counts[entry.method];
                original[entry.method] += entry.original;
                compressed[entry.method] += entry.compressed;
            }
        }
    }
    for (int method = 0; method < 5; ++method)
        out.push_back("method " + methods[method] + " entries " + number(counts[method]) + " original " +
                      number(original[method]) + " compressed " + number(compressed[method]) + " ratio " +
                      ratio(original[method], compressed[method]));
    out.push_back("end listed " + number(listed) + " of " + number(parsed.declared) + " stop " +
                  (parsed.stopped ? "truncated" : "complete") + " trailing " + number(parsed.trailing));
    return out;
}
static void compare(Lines &out, const std::string &name, const Lines &old, const Lines &fresh) {
    std::size_t first = 0;
    while (first < std::min(old.size(), fresh.size()) && old[first] == fresh[first])
        ++first;
    if (first == old.size() && first == fresh.size()) {
        out.push_back("same " + name + " lines " + number(old.size()));
        return;
    }
    const int a = old.size(), b = fresh.size();
    std::vector<std::vector<int>> lcs(a + 1, std::vector<int>(b + 1));
    for (int i = a - 1; i >= 0; --i)
        for (int j = b - 1; j >= 0; --j)
            lcs[i][j] = old[i] == fresh[j] ? 1 + lcs[i + 1][j + 1] : std::max(lcs[i + 1][j], lcs[i][j + 1]);
    Lines edits;
    int i = 0, j = 0, removed = 0, added = 0;
    while (i < a || j < b) {
        if (i < a && j < b && old[i] == fresh[j]) {
            ++i;
            ++j;
        } else if (j == b || (i < a && lcs[i + 1][j] >= lcs[i][j + 1])) {
            edits.push_back("-" + number(i + 1) + ":" + old[i]);
            ++i;
            ++removed;
        } else {
            edits.push_back("+" + number(j + 1) + ":" + fresh[j]);
            ++j;
            ++added;
        }
    }
    out.push_back("differs " + name + " first_line " + number(first + 1) + " archive_lines " + number(a) +
                  " manifest_lines " + number(b) + " removed " + number(removed) + " added " + number(added));
    out.insert(out.end(), edits.begin(), edits.end());
}
int main() {
    std::filesystem::create_directories("output");
    const Lines manifest = text_lines(read_bytes("input/manifest.txt"));
    const int b = std::stoi(words(manifest[0])[1]), k = std::stoi(words(manifest[1])[1]),
              maximum = std::stoi(words(manifest[2])[1]);
    std::vector<File> files;
    Lines sizes = {"params offset_bits " + number(b) + " length_bits " + number(k) + " window " +
                   number(1 << b) + " lookahead " + number((1 << k) + 2) + " max_code_length " +
                   number(maximum)},
          analysis;
    Integer original_total = 0, best_total = 0;
    std::array<Integer, 5> totals{}, chosen{};
    for (std::size_t i = 3; i < manifest.size(); ++i) {
        File file;
        file.name = words(manifest[i])[1];
        file.data = read_bytes("input/files/" + file.name);
        const Encoded encoded = encode(file.data, b, k, maximum);
        file.method = encoded.best;
        file.payload = encoded.payloads[file.method];
        original_total += file.data.size();
        best_total += file.payload.size();
        ++chosen[file.method];
        std::string line = "file " + file.name + " original " + number(file.data.size());
        for (int method = 0; method < 5; ++method) {
            totals[method] += encoded.payloads[method].size();
            line += " " + methods[method] + " " + number(encoded.payloads[method].size()) + " " +
                    ratio(file.data.size(), encoded.payloads[method].size());
        }
        sizes.push_back(line + " best " + methods[file.method]);
        const LzwStats &lzw = encoded.lzw;
        analysis.push_back("lzw " + file.name + " codes " + number(lzw.codes) + " clears " +
                           number(lzw.clears) + " widths " + number(lzw.widths[0]) + " " +
                           number(lzw.widths[1]) + " " + number(lzw.widths[2]) + " " + number(lzw.widths[3]) +
                           " longest " + number(lzw.longest));
        int literals = 0, matches = 0, matched = 0, longest = 0, farthest = 0;
        for (const Token &token : encoded.tokens) {
            if (token.match()) {
                ++matches;
                matched += token.length;
                longest = std::max(longest, token.length);
                farthest = std::max(farthest, token.distance);
            } else
                ++literals;
        }
        analysis.push_back("lz77 " + file.name + " tokens " + number(encoded.tokens.size()) + " literals " +
                           number(literals) + " matches " + number(matches) + " matched " + number(matched) +
                           " longest " + number(longest) + " farthest " + number(farthest));
        const LzhStats &lzh = encoded.lzh;
        analysis.push_back("lzh " + file.name + " mode " + (lzh.dynamic ? "dynamic" : "fixed") +
                           " fixed_bits " + number(lzh.fixed_bits) + " table_bits " + number(lzh.table_bits) +
                           " code_bits " + number(lzh.code_bits) + " halvings " + number(lzh.halvings) +
                           " litlen_used " + number(lzh.litlen_used) + " litlen_max " +
                           number(lzh.litlen_max) + " offset_used " + number(lzh.offset_used) +
                           " offset_max " + number(lzh.offset_max));
        line = "slots " + file.name;
        for (int count : lzh.slots)
            line += " " + number(count);
        analysis.push_back(line);
        analysis.push_back("arith " + file.name + " bits " + number(encoded.arith.bits) + " contexts " +
                           number(encoded.arith.contexts) + " rescales " + number(encoded.arith.rescales));
        files.push_back(std::move(file));
    }
    std::string total = "total original " + number(original_total), choice = "chosen";
    for (int method = 0; method < 5; ++method) {
        total += " " + methods[method] + " " + number(totals[method]) + " " +
                 ratio(original_total, totals[method]);
        choice += " " + methods[method] + " " + number(chosen[method]);
    }
    sizes.push_back(total + " best " + number(best_total) + " " + ratio(original_total, best_total));
    sizes.push_back(choice);
    const Bytes created = build_archive(files, b, k);
    const Parsed verification = parse(created);
    sizes.push_back("archive bytes " + number(created.size()) + " entries " + number(files.size()) +
                    " ratio " + ratio(original_total, created.size()));
    sizes.push_back("verify entries " + number(verification.entries.size()) + " ok " +
                    number(verified(verification, files)));
    write_lines("sizes.txt", sizes);
    write_lines("analysis.txt", analysis);
    write_lines("archive.hex", hex_lines(created));
    Bytes given;
    for (const std::string &line : text_lines(read_bytes("input/archive.hex")))
        for (std::size_t i = 0; i < line.size(); i += 2)
            given.push_back(Byte(std::stoul(line.substr(i, 2), nullptr, 16)));
    const Parsed parsed = parse(given);
    write_lines("listing.txt", listing(parsed));
    Lines tested, extracted, comparison;
    std::vector<File> salvage;
    std::set<std::string> intact_names;
    if (!parsed.error.empty())
        tested.push_back("archive error " + parsed.error);
    else {
        std::map<std::string, int> statuses;
        for (const Entry &entry : parsed.entries) {
            ++statuses[entry.status];
            const std::string prefix = "entry " + number(entry.number) + " offset " + number(entry.position);
            if (entry.header_cut)
                tested.push_back(prefix + " status truncated header");
            else if (!entry.valid)
                tested.push_back(prefix + " status bad_header");
            else {
                std::string line = prefix + " name " + entry.name + " method " + method_name(entry.method) +
                                   " status " + entry.status;
                if (entry.status == "repaired")
                    line += " byte " + number(entry.repair_position) + " from " + number(entry.repair_from) +
                            " to " + number(entry.repair_to);
                else if (entry.status == "checksum")
                    line += " stored " + hex8(entry.stored) + " computed " + hex8(entry.computed);
                else if (entry.status == "error")
                    line += " " + entry.error + " at " + number(entry.error_position);
                else if (entry.status == "truncated")
                    line += " payload have " + number(parsed.size - entry.start) + " need " +
                            number(entry.compressed);
                tested.push_back(line);
            }
        }
        std::string summary =
            "summary entries " + number(parsed.declared) + " checked " + number(parsed.entries.size());
        for (const std::string status :
             {"ok", "repaired", "checksum", "error", "unsupported", "truncated", "bad_header"})
            summary += " " + status + " " + number(statuses[status]);
        summary += " missing " + number(parsed.declared - parsed.entries.size()) + " trailing " +
                   number(parsed.trailing);
        tested.push_back(summary);
    }
    const int salvage_b = parsed.error.empty() ? parsed.b : b,
              salvage_k = parsed.error.empty() ? parsed.k : k;
    Integer salvage_original = 0;
    for (const Entry &entry : parsed.entries)
        if (entry.status == "ok" || entry.status == "repaired") {
            intact_names.insert(entry.name);
            const Lines lines = text_lines(entry.output);
            int word_count = 0, longest = 0;
            for (const std::string &line : lines) {
                longest = std::max(longest, int(line.size()));
                bool in_word = false;
                for (char byte : line) {
                    if (byte == ' ')
                        in_word = false;
                    else if (!in_word) {
                        ++word_count;
                        in_word = true;
                    }
                }
            }
            extracted.push_back("file " + entry.name + " bytes " + number(entry.output.size()) + " lines " +
                                number(lines.size()) + " words " + number(word_count) + " longest " +
                                number(longest));
            extracted.insert(extracted.end(), lines.begin(), lines.end());
            const auto found = std::find_if(files.begin(), files.end(),
                                            [&](const File &file) { return file.name == entry.name; });
            if (found == files.end())
                comparison.push_back("archive_only " + entry.name);
            else
                compare(comparison, entry.name, lines, text_lines(found->data));
            const Encoded encoded = encode(entry.output, salvage_b, salvage_k, maximum);
            File file{entry.name, entry.output, encoded.payloads[encoded.best], encoded.best};
            tested.push_back("salvage " + entry.name + " method " + methods[file.method] + " compressed " +
                             number(file.payload.size()) + " was " + method_name(entry.method) + " " +
                             number(entry.compressed));
            salvage_original += file.data.size();
            salvage.push_back(std::move(file));
        }
    for (const File &file : files)
        if (!intact_names.count(file.name))
            comparison.push_back("new " + file.name);
    const Bytes salvaged = build_archive(salvage, salvage_b, salvage_k);
    tested.push_back("salvaged entries " + number(salvage.size()) + " bytes " + number(salvaged.size()) +
                     " original " + number(salvage_original) + " verified " +
                     number(verified(parse(salvaged), salvage)));
    write_lines("test_report.txt", tested);
    write_lines("extracted.txt", extracted);
    write_lines("compare.txt", comparison);
    write_lines("salvaged.hex", hex_lines(salvaged));
}
