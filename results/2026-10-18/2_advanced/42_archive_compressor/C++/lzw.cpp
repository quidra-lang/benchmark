#include "archive.hpp"
Bytes lzw_encode(const Bytes &data, LzwStats &stats) {
    std::map<std::string, int> dictionary;
    int next = 258, counter = 0;
    auto initialize = [&]() {
        dictionary.clear();
        for (int i = 0; i < 256; ++i)
            dictionary.emplace(std::string(1, char(i)), i);
        next = 258;
    };
    BitWriter writer;
    auto emit = [&](int code) {
        const int width = std::min(12, bits(258 + counter));
        writer.write(code, width);
        ++stats.codes;
        ++stats.widths[width - 9];
        if (code == 256) {
            ++stats.clears;
            counter = 0;
        } else
            ++counter;
    };
    initialize();
    emit(256);
    std::string sequence;
    for (Byte byte : data) {
        const std::string candidate = sequence + char(byte);
        if (dictionary.count(candidate))
            sequence = candidate;
        else {
            emit(dictionary.at(sequence));
            stats.longest = std::max(stats.longest, int(sequence.size()));
            dictionary[candidate] = next++;
            if (next == 4096) {
                emit(256);
                initialize();
            }
            sequence = std::string(1, char(byte));
        }
    }
    if (!sequence.empty()) {
        emit(dictionary.at(sequence));
        stats.longest = std::max(stats.longest, int(sequence.size()));
    }
    emit(257);
    return writer.bytes;
}
void lzw_decode(const Bytes &payload, std::uint32_t size, Bytes &output) {
    std::array<Bytes, 4096> dictionary;
    int next = 258, previous = -1, counter = 0;
    auto initialize = [&]() {
        for (int i = 0; i < 4096; ++i)
            dictionary[i].clear();
        for (int i = 0; i < 256; ++i)
            dictionary[i].push_back(Byte(i));
        next = 258;
        previous = -1;
    };
    initialize();
    BitReader reader{payload};
    while (true) {
        const int before = counter, code = reader.read(std::min(12, bits(258 + counter)));
        if (code == 256) {
            initialize();
            counter = 0;
            continue;
        }
        ++counter;
        if (code == 257) {
            if (output.size() < size)
                throw DecodeError{"early_end"};
            return;
        }
        if (before == 3838)
            throw DecodeError{"bad_code"};
        Bytes entry;
        if (previous < 0) {
            if (code >= 256)
                throw DecodeError{"bad_code"};
            entry = dictionary[code];
        } else if (code < next)
            entry = dictionary[code];
        else if (code == next) {
            entry = dictionary[previous];
            entry.push_back(entry[0]);
        } else
            throw DecodeError{"bad_code"};
        if (output.size() + entry.size() > size)
            throw DecodeError{"overrun"};
        output.insert(output.end(), entry.begin(), entry.end());
        if (previous >= 0) {
            dictionary[next] = dictionary[previous];
            dictionary[next++].push_back(entry[0]);
        }
        previous = code;
    }
}
