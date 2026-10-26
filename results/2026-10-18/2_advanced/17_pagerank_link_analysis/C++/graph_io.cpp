#include "analysis.hpp"
#include <fstream>
#include <stdexcept>

static Lines readLines(const std::string& name) {
    std::ifstream file("input/" + name, std::ios::binary);
    if (!file) throw std::runtime_error("cannot read " + name);
    Lines result;
    std::string line;
    while (std::getline(file, line)) result.push_back(line);
    if (file.bad()) throw std::runtime_error("cannot read " + name);
    return result;
}
Lines split(const std::string& value, char separator) {
    Lines result;
    std::istringstream stream(value);
    std::string part;
    while (std::getline(stream, part, separator)) result.push_back(part);
    return result;
}
Input readInput() {
    Input input;
    Lines pages = readLines("pages.csv");
    for (std::size_t i = 1; i < pages.size(); ++i) { Lines fields = split(pages[i], ','); input.pages.push_back({std::stoi(fields[0]), fields[1], fields[2], split(fields[2], ' ')}); }
    std::sort(input.pages.begin(), input.pages.end(), [](const Page& first, const Page& second) { return first.id < second.id; });
    Lines links = readLines("links.csv");
    for (std::size_t i = 1; i < links.size(); ++i) { Lines fields = split(links[i], ','); input.records.push_back({static_cast<int>(i + 1), std::stoi(fields[0]), std::stoi(fields[1])}); }
    Lines queries = readLines("queries.txt");
    for (std::size_t i = 0; i < queries.size(); ++i) {
        std::size_t separator = queries[i].find(" | ");
        Query query{static_cast<int>(i + 1), split(queries[i].substr(0, separator), ' '), {}};
        for (const std::string& word : split(queries[i].substr(separator + 3), ' ')) query.seeds.push_back(std::stoi(word));
        input.queries.push_back(std::move(query));
    }
    std::map<std::string, Lines> entries;
    for (const std::string& line : readLines("params.txt")) { Lines words = split(line, ' '); entries[words[0]] = Lines(words.begin() + 1, words.end()); }
    Settings& p = input.settings;
    p.damping = std::stod(entries.at("DAMPING")[0]);
    p.iterations = std::stoi(entries.at("PAGERANK_ITERATIONS")[0]);
    p.tolerance = std::stod(entries.at("TOLERANCE")[0]);
    for (const std::string& word : entries.at("DAMPING_SWEEP")) p.sweep.push_back(std::stod(word));
    for (const std::string& word : entries.at("TRUSTED")) p.trusted.push_back(std::stoi(word));
    p.spamTop = std::stoi(entries.at("SPAM_TOP")[0]);
    p.spamThreshold = std::stod(entries.at("SPAM_THRESHOLD")[0]);
    p.hitsIterations = std::stoi(entries.at("HITS_ITERATIONS")[0]);
    p.topK = std::stoi(entries.at("TOP_K")[0]);
    p.rootLimit = std::stoi(entries.at("ROOT_LIMIT")[0]);
    p.neighborLimit = std::stoi(entries.at("NEIGHBOR_LIMIT")[0]);
    return input;
}
