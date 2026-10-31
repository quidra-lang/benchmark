#pragma once

#include <array>
#include <map>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

namespace classical {

enum class Cipher { Caesar, Affine, Vigenere, Autokey, Playfair, Railfence, Columnar };
using AffineKey = std::pair<int, int>;
using Key = std::variant<int, AffineKey, std::string>;

inline constexpr std::array<int, 12> affineMultipliers{
    1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25
};

bool isLetter(char character);
int letterValue(char character);
std::string uppercase(std::string text);
std::string letterString(std::string_view text);

struct Weights {
    std::array<int, 26> monograms{};
    std::array<std::array<int, 26>, 26> bigrams{};

    int monogramFitness(std::string_view text) const;
    int bigramFitness(std::string_view text) const;
};

Weights readWeights(const std::string& path);
std::string substitute(std::string text, Cipher cipher, const Key& key, bool decrypt);

int railNumber(int position, int rails);
std::string railFence(std::string_view text, int rails, bool decrypt);
std::vector<int> columnOrder(std::string_view key);
std::string rankString(std::string_view key);
std::string columnar(std::string_view text, std::string_view key, bool decrypt);

std::string playfairSquare(std::string_view key);
std::string playfairPlaintext(std::string text);
bool validPlayfair(std::string_view text);
std::string playfair(std::string text, std::string_view key, bool decrypt);

struct RepeatedTrigram {
    std::string trigram;
    std::vector<int> positions;
    std::vector<int> gaps;
    int divisor = 0;
};

std::array<int, 26> letterCounts(std::string_view text);
int indexOfCoincidence(std::string_view text);
std::vector<std::string> columns(std::string_view text, int period);
std::vector<int> columnIndices(std::string_view text, int period);
std::vector<RepeatedTrigram> repeatedTrigrams(std::string_view text);
std::string percentage(int count, int total);
std::map<std::string, int> pairCounts(std::string_view text, int stride);
std::vector<std::pair<std::string, int>> topCounts(
    const std::map<std::string, int>& counts, int limit = 10);

}
