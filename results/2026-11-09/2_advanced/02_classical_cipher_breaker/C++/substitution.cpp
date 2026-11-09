#include "cipher.hpp"

namespace classical {

namespace {

int mod26(int value) {
    int remainder = value % 26;
    return remainder < 0 ? remainder + 26 : remainder;
}

int inverse(int multiplier) {
    for (int candidate = 1; candidate < 26; ++candidate) {
        if (multiplier * candidate % 26 == 1) {
            return candidate;
        }
    }
    return 0;
}

}

std::string substitute(std::string text, Cipher cipher, const Key& key, bool decrypt) {
    int multiplier = 1;
    int offset = 0;
    std::string keyword;
    if (cipher == Cipher::Caesar) {
        offset = std::get<int>(key);
    } else if (cipher == Cipher::Affine) {
        const AffineKey& affine = std::get<AffineKey>(key);
        multiplier = decrypt ? inverse(affine.first) : affine.first;
        offset = affine.second;
    } else {
        keyword = std::get<std::string>(key);
    }
    std::vector<int> plaintext;
    for (char& character : text) {
        if (!isLetter(character)) {
            continue;
        }
        int value = letterValue(character);
        int result;
        if (cipher == Cipher::Caesar || cipher == Cipher::Affine) {
            result = decrypt ? multiplier * (value - offset) : multiplier * value + offset;
        } else {
            std::size_t position = plaintext.size();
            int shift;
            if (cipher == Cipher::Vigenere) {
                shift = keyword[position % keyword.size()] - 'A';
            } else if (position < keyword.size()) {
                shift = keyword[position] - 'A';
            } else {
                shift = plaintext[position - keyword.size()];
            }
            result = value + (decrypt ? -shift : shift);
        }
        result = mod26(result);
        plaintext.push_back(decrypt ? result : value);
        char base = character >= 'a' && character <= 'z' ? 'a' : 'A';
        character = static_cast<char>(base + result);
    }
    return text;
}

}
