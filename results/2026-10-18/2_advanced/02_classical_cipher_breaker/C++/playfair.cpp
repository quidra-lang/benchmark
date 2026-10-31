#include "cipher.hpp"

#include <algorithm>

namespace classical {

std::string playfairSquare(std::string_view key) {
    std::string square;
    std::string sequence(key);
    sequence += "ABCDEFGHIKLMNOPQRSTUVWXYZ";
    std::array<bool, 26> seen{};
    for (char letter : sequence) {
        if (!seen[letter - 'A']) {
            seen[letter - 'A'] = true;
            square += letter;
        }
    }
    return square;
}

std::string playfairPlaintext(std::string text) {
    std::replace(text.begin(), text.end(), 'J', 'I');
    std::string prepared;
    for (std::size_t index = 0; index < text.size();) {
        char first = text[index++];
        prepared += first;
        if (index < text.size() && text[index] != first) {
            prepared += text[index++];
        } else {
            prepared += first == 'X' ? 'Q' : 'X';
        }
    }
    return prepared;
}

bool validPlayfair(std::string_view text) {
    if (text.size() % 2 != 0) {
        return false;
    }
    for (std::size_t index = 0; index < text.size(); index += 2) {
        char first = text[index] == 'J' ? 'I' : text[index];
        char second = text[index + 1] == 'J' ? 'I' : text[index + 1];
        if (first == second) {
            return false;
        }
    }
    return true;
}

std::string playfair(std::string text, std::string_view key, bool decrypt) {
    std::string square = playfairSquare(key);
    if (decrypt) {
        std::replace(text.begin(), text.end(), 'J', 'I');
    } else {
        text = playfairPlaintext(std::move(text));
    }
    std::array<int, 26> positions{};
    for (std::size_t index = 0; index < square.size(); ++index) {
        positions[square[index] - 'A'] = static_cast<int>(index);
    }
    int step = decrypt ? 4 : 1;
    for (std::size_t index = 0; index < text.size(); index += 2) {
        int first = positions[text[index] - 'A'];
        int second = positions[text[index + 1] - 'A'];
        int rowFirst = first / 5;
        int colFirst = first % 5;
        int rowSecond = second / 5;
        int colSecond = second % 5;
        if (rowFirst == rowSecond) {
            colFirst = (colFirst + step) % 5;
            colSecond = (colSecond + step) % 5;
        } else if (colFirst == colSecond) {
            rowFirst = (rowFirst + step) % 5;
            rowSecond = (rowSecond + step) % 5;
        } else {
            std::swap(colFirst, colSecond);
        }
        text[index] = square[5 * rowFirst + colFirst];
        text[index + 1] = square[5 * rowSecond + colSecond];
    }
    return text;
}

}
