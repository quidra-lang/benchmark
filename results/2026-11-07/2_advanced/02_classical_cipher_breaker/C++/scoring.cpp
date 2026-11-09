#include "cipher.hpp"

#include <fstream>

namespace classical {

bool isLetter(char character) {
    return (character >= 'A' && character <= 'Z') ||
           (character >= 'a' && character <= 'z');
}

int letterValue(char character) {
    return character >= 'a' && character <= 'z' ? character - 'a' : character - 'A';
}

std::string uppercase(std::string text) {
    for (char& character : text) {
        if (character >= 'a' && character <= 'z') {
            character = static_cast<char>(character - 'a' + 'A');
        }
    }
    return text;
}

std::string letterString(std::string_view text) {
    std::string letters;
    for (char character : text) {
        if (isLetter(character)) {
            letters += static_cast<char>('A' + letterValue(character));
        }
    }
    return letters;
}

int Weights::monogramFitness(std::string_view text) const {
    int score = 0;
    for (char letter : text) {
        score += monograms[letter - 'A'];
    }
    return score;
}

int Weights::bigramFitness(std::string_view text) const {
    int score = 0;
    for (std::size_t index = 1; index < text.size(); ++index) {
        score += bigrams[text[index - 1] - 'A'][text[index] - 'A'];
    }
    return score;
}

Weights readWeights(const std::string& path) {
    std::ifstream input(path);
    std::string label;
    Weights weights;
    input >> label;
    for (int& weight : weights.monograms) {
        input >> weight;
    }
    input >> label;
    for (std::array<int, 26>& row : weights.bigrams) {
        for (int& weight : row) {
            input >> weight;
        }
    }
    return weights;
}

}
