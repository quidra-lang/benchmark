#include "cipher.hpp"

#include <algorithm>
#include <numeric>

namespace classical {

int railNumber(int position, int rails) {
    int cycle = 2 * rails - 2;
    int offset = position % cycle;
    return std::min(offset, cycle - offset);
}

std::string railFence(std::string_view text, int rails, bool decrypt) {
    std::string result(text.size(), ' ');
    std::size_t cursor = 0;
    for (int rail = 0; rail < rails; ++rail) {
        for (std::size_t position = 0; position < text.size(); ++position) {
            if (railNumber(static_cast<int>(position), rails) == rail) {
                if (decrypt) {
                    result[position] = text[cursor++];
                } else {
                    result[cursor++] = text[position];
                }
            }
        }
    }
    return result;
}

std::vector<int> columnOrder(std::string_view key) {
    std::vector<int> order(key.size());
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(), [key](int first, int second) {
        return key[first] < key[second];
    });
    return order;
}

std::string rankString(std::string_view key) {
    std::vector<int> order = columnOrder(key);
    std::string ranks(key.size(), '0');
    for (std::size_t rank = 0; rank < order.size(); ++rank) {
        ranks[order[rank]] = static_cast<char>('1' + rank);
    }
    return ranks;
}

std::string columnar(std::string_view text, std::string_view key, bool decrypt) {
    std::string result(text.size(), ' ');
    std::size_t cursor = 0;
    for (int column : columnOrder(key)) {
        for (std::size_t position = column; position < text.size(); position += key.size()) {
            if (decrypt) {
                result[position] = text[cursor++];
            } else {
                result[cursor++] = text[position];
            }
        }
    }
    return result;
}

}
