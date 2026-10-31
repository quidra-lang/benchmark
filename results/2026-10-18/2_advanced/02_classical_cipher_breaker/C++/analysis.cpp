#include "cipher.hpp"

#include <algorithm>
#include <cstdint>
#include <numeric>

namespace classical {

std::array<int, 26> letterCounts(std::string_view text) {
    std::array<int, 26> counts{};
    for (char letter : text) {
        ++counts[letter - 'A'];
    }
    return counts;
}

int indexOfCoincidence(std::string_view text) {
    std::int64_t sum = 0;
    for (int count : letterCounts(text)) {
        sum += static_cast<std::int64_t>(count) * (count - 1);
    }
    std::int64_t length = static_cast<std::int64_t>(text.size());
    return static_cast<int>(100000 * sum / (length * (length - 1)));
}

std::vector<std::string> columns(std::string_view text, int period) {
    std::vector<std::string> result(period);
    for (std::size_t index = 0; index < text.size(); ++index) {
        result[index % period] += text[index];
    }
    return result;
}

std::vector<int> columnIndices(std::string_view text, int period) {
    std::vector<int> indices;
    for (const std::string& column : columns(text, period)) {
        indices.push_back(indexOfCoincidence(column));
    }
    return indices;
}

std::vector<RepeatedTrigram> repeatedTrigrams(std::string_view text) {
    std::map<std::string, std::vector<int>> positions;
    for (std::size_t index = 0; index + 2 < text.size(); ++index) {
        positions[std::string(text.substr(index, 3))].push_back(static_cast<int>(index) + 1);
    }
    std::vector<RepeatedTrigram> repeats;
    for (const auto& [trigram, found] : positions) {
        if (found.size() < 2) {
            continue;
        }
        RepeatedTrigram repeat{trigram, found, {}, 0};
        for (std::size_t index = 1; index < found.size(); ++index) {
            int gap = found[index] - found[index - 1];
            repeat.gaps.push_back(gap);
            repeat.divisor = std::gcd(repeat.divisor, gap);
        }
        repeats.push_back(std::move(repeat));
    }
    return repeats;
}

std::string percentage(int count, int total) {
    int tenths = (2000 * count + total) / (2 * total);
    return std::to_string(tenths / 10) + "." + std::to_string(tenths % 10);
}

std::map<std::string, int> pairCounts(std::string_view text, int stride) {
    std::map<std::string, int> counts;
    for (std::size_t index = 0; index + 1 < text.size(); index += stride) {
        ++counts[std::string(text.substr(index, 2))];
    }
    return counts;
}

std::vector<std::pair<std::string, int>> topCounts(
    const std::map<std::string, int>& counts, int limit) {
    std::vector<std::pair<std::string, int>> entries(counts.begin(), counts.end());
    std::sort(entries.begin(), entries.end(), [](const auto& first, const auto& second) {
        return first.second != second.second ? first.second > second.second : first.first < second.first;
    });
    if (entries.size() > static_cast<std::size_t>(limit)) {
        entries.resize(limit);
    }
    return entries;
}

}
