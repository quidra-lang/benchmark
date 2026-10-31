#include "columnar.hpp"
const std::array<std::string, 5> methods{"PLAIN", "DICTIONARY", "RLE", "DELTA_BINARY_PACKED",
                                         "DELTA_LENGTH_BYTE_ARRAY"};
std::vector<int> candidates(Type kind) {
    if (kind == Type::Bool)
        return {0, 2};
    return kind == Type::String ? std::vector<int>{0, 1, 4} : std::vector<int>{0, 1, 3};
}
Bytes delta_encode(const Numbers &values) {
    Bytes out;
    write_uleb(out, 128);
    write_uleb(out, 4);
    write_uleb(out, Number(values.size()));
    write_zigzag(out, values.empty() ? 0 : values[0]);
    Numbers differences;
    for (std::size_t i = 1; i < values.size(); ++i)
        differences.push_back(values[i] - values[i - 1]);
    for (std::size_t start = 0; start < differences.size(); start += 128) {
        std::size_t end = std::min(start + 128, differences.size());
        Number minimum = *std::min_element(differences.begin() + start, differences.begin() + end);
        write_zigzag(out, minimum);
        std::array<Numbers, 4> miniblocks;
        std::array<int, 4> widths{};
        for (int t = 0; t < 4; ++t)
            for (std::size_t i = start + 32 * t; i < std::min(start + 32 * (t + 1), end); ++i) {
                Number value = differences[i] - minimum;
                miniblocks[t].push_back(value);
                widths[t] = std::max(widths[t], bits(value));
            }
        for (int width : widths)
            out.push_back(std::uint8_t(width));
        for (int t = 0; t < 4; ++t)
            if (!miniblocks[t].empty()) {
                miniblocks[t].resize(32);
                append(out, pack(miniblocks[t], widths[t]));
            }
    }
    return out;
}
Numbers delta_decode(Reader &reader) {
    int block_size = int(reader.uleb()), miniblock_count = int(reader.uleb()),
        count = int(reader.uleb());
    Number first = reader.zigzag();
    Numbers values;
    if (count)
        values.push_back(first);
    int miniblock_size = block_size / miniblock_count;
    while (int(values.size()) < count) {
        Number minimum = reader.zigzag();
        std::vector<int> widths;
        for (int i = 0; i < miniblock_count; ++i)
            widths.push_back(reader.byte());
        for (int width : widths) {
            if (int(values.size()) == count)
                break;
            Numbers differences = unpack(reader, width, miniblock_size);
            int remaining = count - int(values.size());
            for (int i = 0; i < std::min(miniblock_size, remaining); ++i)
                values.push_back(values.back() + minimum + differences[i]);
        }
    }
    return values;
}
Bytes encode_values(Type kind, int method, const Values &values, const Values &dictionary) {
    Bytes out;
    Numbers numbers;
    for (const Value &v : values)
        numbers.push_back(v.number);
    if (method == 0) {
        if (kind == Type::Int || kind == Type::Date)
            for (Number value : numbers)
                write_integer(out, value);
        else if (kind == Type::String)
            for (const Value &value : values) {
                write_integer(out, Number(value.string.size()));
                out.insert(out.end(), value.string.begin(), value.string.end());
            }
        else {
            numbers.resize((numbers.size() + 7) / 8 * 8);
            out = pack(numbers, 1);
        }
        return out;
    }
    if (method == 1) {
        int width = bits(Number(dictionary.size()) - 1);
        out.push_back(std::uint8_t(width));
        Numbers ranks;
        for (const Value &v : values)
            ranks.push_back(std::find(dictionary.begin(), dictionary.end(), v) -
                            dictionary.begin());
        append(out, hybrid_encode(ranks, width));
        return out;
    }
    if (method == 2) {
        Bytes encoded = hybrid_encode(numbers, 1);
        write_integer(out, Number(encoded.size()));
        append(out, encoded);
        return out;
    }
    if (method == 3)
        return delta_encode(numbers);
    Numbers lengths;
    for (const Value &v : values)
        lengths.push_back(Number(v.string.size()));
    out = delta_encode(lengths);
    for (const Value &v : values)
        out.insert(out.end(), v.string.begin(), v.string.end());
    return out;
}
Values decode_values(Reader &reader, Type kind, int method, int count, const Values &dictionary) {
    Values out;
    if (method == 0) {
        if (kind == Type::Int || kind == Type::Date)
            for (int i = 0; i < count; ++i)
                out.push_back(Value::integer(reader.integer(true)));
        else if (kind == Type::String)
            for (int i = 0; i < count; ++i) {
                std::size_t length = std::size_t(reader.integer());
                out.push_back(Value::word(reader.string(length)));
            }
        else {
            Numbers values = unpack(reader, 1, (count + 7) / 8 * 8);
            for (int i = 0; i < count; ++i)
                out.push_back(Value::integer(values[i] != 0));
        }
        return out;
    }
    if (method == 1) {
        int width = reader.byte();
        for (Number rank : hybrid_decode(reader, width, count))
            out.push_back(dictionary[rank]);
        return out;
    }
    if (method == 2) {
        std::size_t size = std::size_t(reader.integer());
        Bytes data = reader.read(size);
        Reader encoded{data};
        for (Number v : hybrid_decode(encoded, 1, count))
            out.push_back(Value::integer(v != 0));
        return out;
    }
    if (method == 3) {
        for (Number value : delta_decode(reader))
            out.push_back(Value::integer(value));
        return out;
    }
    for (Number length : delta_decode(reader))
        out.push_back(Value::word(reader.string(std::size_t(length))));
    return out;
}
Bytes encode_statistics(Type kind, const Bounds &bounds) {
    Bytes out{std::uint8_t(bounds ? 1 : 0)};
    if (!bounds)
        return out;
    for (const Value &v : Values{bounds->first, bounds->second}) {
        if (kind == Type::Int || kind == Type::Date)
            write_zigzag(out, v.number);
        else if (kind == Type::String) {
            write_uleb(out, Number(v.string.size()));
            out.insert(out.end(), v.string.begin(), v.string.end());
        } else
            out.push_back(std::uint8_t(v.number));
    }
    return out;
}
Bounds decode_statistics(Reader &reader, Type kind) {
    if (!reader.byte())
        return {};
    Values values;
    for (int i = 0; i < 2; ++i) {
        if (kind == Type::Int || kind == Type::Date)
            values.push_back(Value::integer(reader.zigzag()));
        else if (kind == Type::String) {
            std::size_t length = std::size_t(reader.uleb());
            values.push_back(Value::word(reader.string(length)));
        } else
            values.push_back(Value::integer(reader.byte() != 0));
    }
    return std::make_pair(values[0], values[1]);
}
