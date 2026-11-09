#include "regions.hpp"
#include <fstream>
#include <stdexcept>

Lines readLines(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("cannot read " + path);
    Lines result;
    std::string line;
    while (std::getline(file, line)) result.push_back(line);
    if (file.bad()) throw std::runtime_error("cannot read " + path);
    return result;
}
Lines words(const std::string& line) { std::istringstream stream(line); Lines result; std::string word; while (stream >> word) result.push_back(word); return result; }
std::vector<Image> readImages(const std::string& path) {
    Lines tokens;
    for (const std::string& line : readLines(path)) { Lines parts = words(line.substr(0, line.find('#'))); tokens.insert(tokens.end(), parts.begin(), parts.end()); }
    std::vector<Image> result;
    std::size_t position = 0;
    while (position < tokens.size()) {
        Image image{tokens[position + 1], std::stoi(tokens[position + 3]), std::stoi(tokens[position + 4]), std::stoi(tokens[position + 5]), {}};
        position += 6;
        int count = image.width * image.height;
        for (int i = 0; i < count; ++i) image.pixels.push_back(std::stoi(tokens[position++]));
        result.push_back(std::move(image));
    }
    return result;
}
