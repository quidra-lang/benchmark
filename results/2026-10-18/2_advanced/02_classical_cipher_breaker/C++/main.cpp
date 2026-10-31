#include "cipher.hpp"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <numeric>
#include <optional>
#include <set>
#include <stdexcept>

using namespace classical;

namespace {

const std::array<std::string, 6> commands{
    "ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY"
};
const std::array<std::string, 7> cipherNames{
    "caesar", "affine", "vigenere", "autokey", "playfair", "railfence", "columnar"
};
using Lines = std::vector<std::string>;
using Messages = std::map<std::string, Lines>;
using Limits = std::map<std::string, std::array<int, 3>>;

struct JobError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

bool isDigit(char character) {
    return character >= '0' && character <= '9';
}

bool validName(const std::string& word) {
    return !word.empty() && word.size() <= 16 &&
           std::all_of(word.begin(), word.end(), [](char character) {
               return (character >= 'a' && character <= 'z') ||
                      isDigit(character) || character == '_';
           });
}

bool digitString(const std::string& word, std::size_t maximum) {
    return !word.empty() && word.size() <= maximum &&
           std::all_of(word.begin(), word.end(), isDigit);
}

bool namingCommand(const std::string& command) {
    return command == "ENCRYPT" || command == "DECRYPT" || command == "BREAK";
}

bool substitutionCipher(Cipher cipher) {
    return cipher == Cipher::Caesar || cipher == Cipher::Affine ||
           cipher == Cipher::Vigenere || cipher == Cipher::Autokey;
}

const std::string& cipherName(Cipher cipher) {
    return cipherNames[static_cast<std::size_t>(cipher)];
}

Cipher parseCipher(const std::string& word) {
    auto found = std::find(cipherNames.begin(), cipherNames.end(), word);
    if (found == cipherNames.end()) {
        throw JobError("unknown cipher " + word);
    }
    return static_cast<Cipher>(found - cipherNames.begin());
}

Key parseKey(Cipher cipher, const std::string& word) {
    if (cipher == Cipher::Caesar || cipher == Cipher::Railfence) {
        if (digitString(word, 2)) {
            int value = std::stoi(word);
            int minimum = cipher == Cipher::Caesar ? 0 : 2;
            int maximum = cipher == Cipher::Caesar ? 25 : 20;
            if (value >= minimum && value <= maximum) {
                return value;
            }
        }
    } else if (cipher == Cipher::Affine) {
        std::size_t comma = word.find(',');
        if (comma != std::string::npos && word.find(',', comma + 1) == std::string::npos) {
            std::string first = word.substr(0, comma);
            std::string second = word.substr(comma + 1);
            if (digitString(first, 2) && digitString(second, 2)) {
                int multiplier = std::stoi(first);
                int offset = std::stoi(second);
                if (std::find(affineMultipliers.begin(), affineMultipliers.end(), multiplier) !=
                        affineMultipliers.end() && offset <= 25) {
                    return AffineKey{multiplier, offset};
                }
            }
        }
    } else {
        std::size_t minimum = cipher == Cipher::Columnar ? 2 : 1;
        std::size_t maximum = cipher == Cipher::Columnar ? 9 :
                              cipher == Cipher::Playfair ? 25 : 20;
        bool valid = std::all_of(word.begin(), word.end(), [cipher](char character) {
            return isLetter(character) || (cipher == Cipher::Columnar && isDigit(character));
        });
        if (word.size() >= minimum && word.size() <= maximum && valid) {
            std::string key = uppercase(word);
            if (cipher == Cipher::Playfair) {
                std::replace(key.begin(), key.end(), 'J', 'I');
            }
            return key;
        }
    }
    throw JobError("bad key " + word);
}

std::string keyNotation(const Key& key) {
    if (const int* number = std::get_if<int>(&key)) {
        return std::to_string(*number);
    }
    if (const AffineKey* affine = std::get_if<AffineKey>(&key)) {
        return std::to_string(affine->first) + "," + std::to_string(affine->second);
    }
    return std::get<std::string>(key);
}

Limits allowedOptions(const std::string& command, Cipher cipher) {
    if (command == "ANALYZE") {
        return {{"MAXLEN", {2, 20, 10}}};
    }
    if (command == "IDENTIFY") {
        return {{"KEYS", {0, 0, 0}}};
    }
    Limits limits{{"TOP", {1, 20, 5}}};
    if (cipher == Cipher::Vigenere) {
        limits.insert({{"MAXLEN", {2, 20, 10}}, {"IOC", {1, 100000, 6000}},
                       {"KASISKI", {1, 100, 60}}, {"REFINE", {0, 10, 5}}});
    } else if (cipher == Cipher::Autokey) {
        limits["MAXLEN"] = {1, 20, 8};
    } else if (cipher == Cipher::Railfence) {
        limits["MAXRAILS"] = {2, 20, 10};
    } else if (cipher == Cipher::Columnar) {
        limits["MAXLEN"] = {2, 6, 6};
    } else if (cipher == Cipher::Playfair) {
        limits["KEYS"] = {0, 0, 0};
    }
    return limits;
}

struct Options {
    std::map<std::string, int> numbers;
    std::string keys;

    int operator()(const std::string& name) const {
        return numbers.at(name);
    }
};

Options parseOptions(const Lines& words, std::size_t start, const Limits& limits) {
    Options options;
    for (const auto& [name, range] : limits) {
        if (name != "KEYS") {
            options.numbers[name] = range[2];
        }
    }
    std::set<std::string> seen;
    for (std::size_t index = start; index < words.size(); ++index) {
        const std::string& word = words[index];
        std::size_t equal = word.find('=');
        std::string name = word.substr(0, equal);
        auto limit = limits.find(name);
        if (equal == std::string::npos || limit == limits.end() || !seen.insert(name).second) {
            throw JobError("bad option " + word);
        }
        std::string value = word.substr(equal + 1);
        if (name == "KEYS") {
            if (!validName(value)) {
                throw JobError("bad option " + word);
            }
            options.keys = value;
        } else {
            if (!digitString(value, 6)) {
                throw JobError("bad option " + word);
            }
            int number = std::stoi(value);
            if (number < limit->second[0] || number > limit->second[1]) {
                throw JobError("bad option " + word);
            }
            options.numbers[name] = number;
        }
    }
    return options;
}

Options defaultOptions(Cipher cipher) {
    return parseOptions({}, 0, allowedOptions("BREAK", cipher));
}

Lines split(const std::string& text, char separator) {
    Lines pieces;
    std::size_t start = 0;
    std::size_t end;
    while ((end = text.find(separator, start)) != std::string::npos) {
        pieces.push_back(text.substr(start, end - start));
        start = end + 1;
    }
    pieces.push_back(text.substr(start));
    return pieces;
}

std::string join(const Lines& lines, const std::string& separator) {
    std::string text;
    for (std::size_t index = 0; index < lines.size(); ++index) {
        if (index != 0) {
            text += separator;
        }
        text += lines[index];
    }
    return text;
}

std::string numberList(const std::vector<int>& numbers) {
    Lines parts;
    for (int number : numbers) {
        parts.push_back(std::to_string(number));
    }
    return join(parts, ",");
}

std::string countList(const std::map<std::string, int>& counts) {
    Lines parts;
    for (const auto& [item, count] : topCounts(counts)) {
        parts.push_back(item + ":" + std::to_string(count));
    }
    return join(parts, " ");
}

void append(Lines& destination, const Lines& source) {
    destination.insert(destination.end(), source.begin(), source.end());
}

Lines groupForm(const std::string& letters) {
    Lines lines;
    for (std::size_t start = 0; start < letters.size(); start += 50) {
        Lines groups;
        std::size_t end = std::min(start + 50, letters.size());
        for (std::size_t index = start; index < end; index += 5) {
            groups.push_back(letters.substr(index, std::min<std::size_t>(5, end - index)));
        }
        lines.push_back(join(groups, " "));
    }
    return lines;
}

std::string transform(Cipher cipher, const Key& key, const std::string& text, bool decrypt) {
    if (substitutionCipher(cipher)) {
        return substitute(text, cipher, key, decrypt);
    }
    if (cipher == Cipher::Railfence) {
        return railFence(text, std::get<int>(key), decrypt);
    }
    if (cipher == Cipher::Columnar) {
        return columnar(text, std::get<std::string>(key), decrypt);
    }
    return playfair(text, std::get<std::string>(key), decrypt);
}

Lines solutionLines(Cipher cipher, const Key& key, const std::string& text,
                    const std::string& letters) {
    if (substitutionCipher(cipher)) {
        return split(transform(cipher, key, text, true), '\n');
    }
    return groupForm(transform(cipher, key, letters, true));
}

Lines playfairKeys(const std::string& text) {
    Lines keys;
    std::set<std::string> seen;
    for (std::size_t index = 0; index < text.size();) {
        if (!isLetter(text[index])) {
            ++index;
            continue;
        }
        std::size_t start = index;
        while (index < text.size() && isLetter(text[index])) {
            ++index;
        }
        std::string key = uppercase(text.substr(start, index - start));
        std::replace(key.begin(), key.end(), 'J', 'I');
        if (seen.insert(key).second) {
            keys.push_back(std::move(key));
        }
    }
    return keys;
}

struct Period {
    int length;
    std::vector<int> indices;
    int average;
    int kasiski;
};

struct PeriodProfile {
    std::vector<RepeatedTrigram> repeats;
    std::vector<Period> periods;
    int gapCount = 0;

    PeriodProfile(const std::string& letters, int maximum)
        : repeats(repeatedTrigrams(letters)) {
        for (const RepeatedTrigram& repeat : repeats) {
            gapCount += static_cast<int>(repeat.gaps.size());
        }
        for (int length = 1; length <= maximum; ++length) {
            std::vector<int> indices = columnIndices(letters, length);
            int average = std::accumulate(indices.begin(), indices.end(), 0) / length;
            int kasiski = 0;
            for (const RepeatedTrigram& repeat : repeats) {
                for (int gap : repeat.gaps) {
                    kasiski += gap % length == 0;
                }
            }
            periods.push_back({length, std::move(indices), average, kasiski});
        }
    }

    std::pair<int, std::string> keyLength(const Options& options) const {
        int kasiskiLength = 0;
        if (gapCount != 0) {
            for (const Period& period : periods) {
                if (period.length >= 2 &&
                    100 * period.kasiski >= options("KASISKI") * gapCount) {
                    kasiskiLength = period.length;
                }
            }
        }
        if (kasiskiLength != 0 && periods[kasiskiLength - 1].average >= options("IOC")) {
            return {kasiskiLength, "kasiski"};
        }
        int bestLength = 1;
        for (const Period& period : periods) {
            if (period.average >= options("IOC")) {
                return {period.length, "ioc"};
            }
            if (period.average > periods[bestLength - 1].average) {
                bestLength = period.length;
            }
        }
        return {bestLength, "maxioc"};
    }

    Lines lines() const {
        Lines report;
        for (const Period& period : periods) {
            report.push_back("L=" + std::to_string(period.length) +
                " ioc=" + std::to_string(period.average) +
                " kasiski=" + std::to_string(period.kasiski) +
                " cols=" + numberList(period.indices));
        }
        report.push_back("kasiski repeats=" + std::to_string(repeats.size()) +
                         " spacings=" + std::to_string(gapCount));
        for (const RepeatedTrigram& repeat : repeats) {
            report.push_back(repeat.trigram + " at=" + numberList(repeat.positions) +
                " gaps=" + numberList(repeat.gaps) + " gcd=" + std::to_string(repeat.divisor));
        }
        return report;
    }
};

struct Candidate {
    Key key;
    std::string plaintext;
    int score;
};

struct BreakResult {
    std::vector<Candidate> candidates;
    Key key = 0;
    int score = 0;
    std::optional<PeriodProfile> profile;
    int length = 0;
    std::string method;
    int passes = 0;
    int changes = 0;
};

struct Job {
    std::string command;
    Cipher cipher = Cipher::Caesar;
    Key key = 0;
    Options options;
    std::string source;
    std::string second;
    std::string newName;
};

class CipherDesk {
    Weights weights;
    Messages messages;
    int jobCount = 0;
    std::array<int, 6> okCounts{};
    std::array<int, 6> errorCounts{};
    Lines results;
    Lines candidates;
    Lines analysis;

    std::string messageText(const std::string& name) const {
        return join(messages.at(name), "\n");
    }

    Job validate(Lines words) const {
        Job job;
        job.command = words[0];
        if (namingCommand(job.command) && words.size() >= 5 && words[words.size() - 2] == "AS") {
            job.newName = words.back();
            words.resize(words.size() - 2);
            if (!validName(job.newName)) {
                throw JobError("bad syntax");
            }
        }
        bool validCount;
        if (job.command == "ENCRYPT" || job.command == "DECRYPT") {
            validCount = words.size() == 4;
        } else if (job.command == "BREAK") {
            validCount = words.size() >= 3;
        } else if (job.command == "COMPARE") {
            validCount = words.size() == 3;
        } else {
            validCount = words.size() == 2 || words.size() == 3;
        }
        if (!validCount) {
            throw JobError("bad syntax");
        }
        if (namingCommand(job.command)) {
            job.cipher = parseCipher(words[1]);
        }
        if (job.command == "ENCRYPT" || job.command == "DECRYPT") {
            job.key = parseKey(job.cipher, words[2]);
            job.source = words[3];
        } else if (job.command == "BREAK") {
            job.source = words[2];
            job.options = parseOptions(words, 3, allowedOptions(job.command, job.cipher));
            if (job.cipher == Cipher::Playfair && job.options.keys.empty()) {
                throw JobError("missing option KEYS");
            }
        } else {
            job.source = words[1];
            if (job.command == "COMPARE") {
                job.second = words[2];
            } else {
                job.options = parseOptions(words, 2, allowedOptions(job.command, job.cipher));
            }
        }
        Lines references{job.source};
        if (job.command == "COMPARE") {
            references.push_back(job.second);
        } else if (!job.options.keys.empty()) {
            references.push_back(job.options.keys);
        }
        for (const std::string& reference : references) {
            if (messages.find(reference) == messages.end()) {
                throw JobError("unknown message " + reference);
            }
        }
        if (!job.newName.empty() && messages.find(job.newName) != messages.end()) {
            throw JobError("duplicate message " + job.newName);
        }
        return job;
    }

    int fitness(Cipher cipher, const std::string& plaintext) const {
        return cipher == Cipher::Caesar || cipher == Cipher::Affine ?
            weights.monogramFitness(plaintext) : weights.bigramFitness(plaintext);
    }

    std::string columnKey(Cipher cipher, const std::string& letters, int length) const {
        std::string key;
        for (const std::string& column : columns(letters, length)) {
            int bestShift = 0;
            int bestScore = -1;
            for (int shift = 0; shift < 26; ++shift) {
                int previous = shift;
                int score = 0;
                for (char letter : column) {
                    int value = (letter - 'A' - previous + 26) % 26;
                    score += weights.monograms[value];
                    if (cipher == Cipher::Autokey) {
                        previous = value;
                    }
                }
                if (score > bestScore) {
                    bestScore = score;
                    bestShift = shift;
                }
            }
            key += static_cast<char>('A' + bestShift);
        }
        return key;
    }

    void refineVigenere(BreakResult& result, const std::string& letters,
                        const Options& options) const {
        result.profile.emplace(letters, options("MAXLEN"));
        auto [length, method] = result.profile->keyLength(options);
        result.length = length;
        result.method = method;
        std::string key = std::get<std::string>(result.candidates[length - 1].key);
        int reference = result.candidates[length - 1].score;
        while (result.passes < options("REFINE")) {
            ++result.passes;
            bool changed = false;
            for (int index = 0; index < length; ++index) {
                char original = key[index];
                char bestLetter = 'A';
                int bestScore = -1;
                for (char letter = 'A'; letter <= 'Z'; ++letter) {
                    key[index] = letter;
                    int score = weights.bigramFitness(substitute(letters, Cipher::Vigenere, key, true));
                    if (score > bestScore) {
                        bestScore = score;
                        bestLetter = letter;
                    }
                }
                if (bestScore > reference) {
                    key[index] = bestLetter;
                    reference = bestScore;
                    ++result.changes;
                    changed = true;
                } else {
                    key[index] = original;
                }
            }
            if (!changed) {
                break;
            }
        }
        result.key = std::move(key);
        result.score = reference;
    }

    BreakResult breakCipher(Cipher cipher, const std::string& letters,
                            const Options& options, const Lines& keys) const {
        BreakResult result;
        auto add = [&](const Key& key) {
            std::string plaintext = transform(cipher, key, letters, true);
            int score = fitness(cipher, plaintext);
            result.candidates.push_back({key, std::move(plaintext), score});
        };
        if (cipher == Cipher::Caesar) {
            for (int key = 0; key < 26; ++key) {
                add(key);
            }
        } else if (cipher == Cipher::Affine) {
            for (int multiplier : affineMultipliers) {
                for (int offset = 0; offset < 26; ++offset) {
                    add(AffineKey{multiplier, offset});
                }
            }
        } else if (cipher == Cipher::Railfence) {
            for (int rails = 2; rails <= options("MAXRAILS"); ++rails) {
                add(rails);
            }
        } else if (cipher == Cipher::Columnar) {
            for (int length = 2; length <= options("MAXLEN"); ++length) {
                std::string key;
                for (int digit = 1; digit <= length; ++digit) {
                    key += static_cast<char>('0' + digit);
                }
                do {
                    add(key);
                } while (std::next_permutation(key.begin(), key.end()));
            }
        } else if (cipher == Cipher::Playfair) {
            for (const std::string& key : keys) {
                add(key);
            }
        } else {
            for (int length = 1; length <= options("MAXLEN"); ++length) {
                add(columnKey(cipher, letters, length));
            }
        }
        if (cipher == Cipher::Vigenere) {
            refineVigenere(result, letters, options);
        }
        std::stable_sort(result.candidates.begin(), result.candidates.end(),
                         [](const Candidate& first, const Candidate& second) {
                             return first.score > second.score;
                         });
        if (cipher != Cipher::Vigenere) {
            result.key = result.candidates.front().key;
            result.score = result.candidates.front().score;
        }
        return result;
    }

    std::string prefix(const Job& job) const {
        return "JOB " + std::to_string(jobCount) + " " + job.command;
    }

    std::string suffix(const Job& job) const {
        return job.newName.empty() ? "" : " as=" + job.newName;
    }

    void store(const Job& job, const Lines& lines) {
        append(results, lines);
        if (!job.newName.empty()) {
            messages.emplace(job.newName, lines);
        }
    }

    void transformMessage(const Job& job) {
        std::string text = messageText(job.source);
        std::string letters = letterString(text);
        if (letters.empty()) {
            throw JobError("no letters");
        }
        bool decrypt = job.command == "DECRYPT";
        if (decrypt && job.cipher == Cipher::Playfair && !validPlayfair(letters)) {
            throw JobError("bad playfair text");
        }
        std::string transformed = transform(job.cipher, job.key,
            substitutionCipher(job.cipher) ? text : letters, decrypt);
        Lines lines = substitutionCipher(job.cipher) ? split(transformed, '\n') : groupForm(transformed);
        results.push_back(prefix(job) + " " + cipherName(job.cipher) +
            " key=" + keyNotation(job.key) + " source=" + job.source +
            " letters=" + std::to_string(letterString(transformed).size()) +
            " lines=" + std::to_string(lines.size()) + suffix(job));
        store(job, lines);
    }

    void breakMessage(const Job& job) {
        std::string text = messageText(job.source);
        std::string letters = letterString(text);
        if (letters.size() < 40) {
            throw JobError("text too short");
        }
        Lines keys;
        if (job.cipher == Cipher::Playfair) {
            if (!validPlayfair(letters)) {
                throw JobError("bad playfair text");
            }
            keys = playfairKeys(messageText(job.options.keys));
            if (keys.empty()) {
                throw JobError("empty key list");
            }
        }
        BreakResult result = breakCipher(job.cipher, letters, job.options, keys);
        Lines lines = solutionLines(job.cipher, result.key, text, letters);
        std::string header = prefix(job) + " " + cipherName(job.cipher) + " source=" + job.source;
        results.push_back(header + " key=" + keyNotation(result.key) +
            " score=" + std::to_string(result.score) + " lines=" + std::to_string(lines.size()) + suffix(job));
        store(job, lines);
        int margin = result.candidates.size() == 1 ? 0 :
            result.candidates[0].score - result.candidates[1].score;
        candidates.push_back(header + " tried=" + std::to_string(result.candidates.size()) +
                             " margin=" + std::to_string(margin));
        int count = std::min(job.options("TOP"), static_cast<int>(result.candidates.size()));
        for (int index = 0; index < count; ++index) {
            const Candidate& candidate = result.candidates[index];
            candidates.push_back(std::to_string(index + 1) + " " + keyNotation(candidate.key) +
                " " + std::to_string(candidate.score) + " " + candidate.plaintext.substr(0, 40));
        }
        if (job.cipher == Cipher::Vigenere) {
            analysis.push_back(header);
            analysis.push_back("letters=" + std::to_string(letters.size()));
            append(analysis, result.profile->lines());
            analysis.push_back("decision length=" + std::to_string(result.length) + " method=" + result.method);
            analysis.push_back("refine passes=" + std::to_string(result.passes) +
                " changes=" + std::to_string(result.changes) + " key=" + keyNotation(result.key));
        } else if (job.cipher == Cipher::Playfair) {
            std::replace(letters.begin(), letters.end(), 'J', 'I');
            std::map<std::string, int> pairs = pairCounts(letters, 2);
            std::string square = playfairSquare(std::get<std::string>(result.key));
            Lines rows;
            for (int start = 0; start < 25; start += 5) {
                rows.push_back(square.substr(start, 5));
            }
            analysis.push_back(header);
            analysis.push_back("letters=" + std::to_string(letters.size()));
            analysis.push_back("digraphs pairs=" + std::to_string(letters.size() / 2) +
                               " distinct=" + std::to_string(pairs.size()));
            analysis.push_back("top " + countList(pairs));
            analysis.push_back("square " + join(rows, " "));
        }
    }

    void analyzeMessage(const Job& job) {
        std::string letters = letterString(messageText(job.source));
        int count = static_cast<int>(letters.size());
        if (count < 40) {
            throw JobError("text too short");
        }
        std::array<int, 26> counts = letterCounts(letters);
        int distinct = static_cast<int>(std::count_if(counts.begin(), counts.end(), [](int n) { return n != 0; }));
        int doubles = 0;
        int pairDoubles = 0;
        for (int index = 0; index + 1 < count; ++index) {
            if (letters[index] == letters[index + 1]) {
                ++doubles;
                pairDoubles += index % 2 == 0;
            }
        }
        std::string header = prefix(job) + " source=" + job.source;
        results.push_back(header + " letters=" + std::to_string(count));
        analysis.push_back(header);
        analysis.push_back("letters=" + std::to_string(count));
        analysis.push_back("ioc=" + std::to_string(indexOfCoincidence(letters)) +
            " mono=" + std::to_string(weights.monogramFitness(letters)) +
            " bigram=" + std::to_string(weights.bigramFitness(letters)));
        analysis.push_back("doubles=" + std::to_string(doubles) +
            " pair_doubles=" + std::to_string(pairDoubles) + " distinct=" + std::to_string(distinct));
        for (int index = 0; index < 26; ++index) {
            analysis.push_back(std::string(1, static_cast<char>('A' + index)) + " " +
                std::to_string(counts[index]) + " " + percentage(counts[index], count));
        }
        analysis.push_back("bigrams " + countList(pairCounts(letters, 1)));
        append(analysis, PeriodProfile(letters, job.options("MAXLEN")).lines());
    }

    void compareMessages(const Job& job) {
        std::string first = letterString(messageText(job.source));
        std::string second = letterString(messageText(job.second));
        std::string header = prefix(job) + " " + job.source + " " + job.second;
        if (first == second) {
            results.push_back(header + " equal letters=" + std::to_string(first.size()));
            return;
        }
        std::size_t shared = std::min(first.size(), second.size());
        std::size_t firstMismatch = shared + 1;
        int mismatches = 0;
        for (std::size_t index = 0; index < shared; ++index) {
            if (first[index] != second[index]) {
                if (mismatches == 0) {
                    firstMismatch = index + 1;
                }
                ++mismatches;
            }
        }
        results.push_back(header + " differ letters=" + std::to_string(first.size()) + "," +
            std::to_string(second.size()) + " first=" + std::to_string(firstMismatch) +
            " mismatches=" + std::to_string(mismatches));
    }

    void identifyMessage(const Job& job) {
        std::string text = messageText(job.source);
        std::string letters = letterString(text);
        if (letters.size() < 40) {
            throw JobError("text too short");
        }
        int ioc = indexOfCoincidence(letters);
        int monoAverage = weights.monogramFitness(letters) / static_cast<int>(letters.size());
        std::array<int, 26> counts = letterCounts(letters);
        int distinct = static_cast<int>(std::count_if(counts.begin(), counts.end(), [](int n) { return n != 0; }));
        bool shaped = letters.size() % 2 == 0 && letters.find('J') == std::string::npos && validPlayfair(letters);
        std::string family;
        std::vector<Cipher> ciphers;
        Lines keys;
        if (shaped) {
            family = "playfair";
            if (!job.options.keys.empty()) {
                keys = playfairKeys(messageText(job.options.keys));
                if (keys.empty()) {
                    throw JobError("empty key list");
                }
                ciphers = {Cipher::Playfair};
            }
        } else if (ioc >= 5500 && monoAverage >= 44) {
            family = "transposition";
            ciphers = {Cipher::Railfence, Cipher::Columnar};
        } else if (ioc >= 5500) {
            family = "monoalphabetic";
            ciphers = {Cipher::Affine};
        } else {
            family = "polyalphabetic";
            ciphers = {Cipher::Vigenere, Cipher::Autokey};
        }
        std::string header = prefix(job) + " source=" + job.source;
        Lines report{header,
            "letters=" + std::to_string(letters.size()) + " ioc=" + std::to_string(ioc) +
            " mono_avg=" + std::to_string(monoAverage) + " distinct=" + std::to_string(distinct) +
            " shape=" + (shaped ? "yes" : "no"), "family=" + family};
        std::optional<BreakResult> chosen;
        Cipher chosenCipher = Cipher::Caesar;
        for (Cipher cipher : ciphers) {
            BreakResult result = breakCipher(cipher, letters, defaultOptions(cipher), keys);
            report.push_back("try " + cipherName(cipher) + " key=" + keyNotation(result.key) +
                             " score=" + std::to_string(result.score));
            if (!chosen || result.score > chosen->score) {
                chosen = std::move(result);
                chosenCipher = cipher;
            }
        }
        header += " family=" + family;
        if (!chosen) {
            results.push_back(header);
        } else {
            Key key = chosen->key;
            if (chosenCipher == Cipher::Affine && std::get<AffineKey>(key).first == 1) {
                int offset = std::get<AffineKey>(key).second;
                chosenCipher = Cipher::Caesar;
                key = offset;
            }
            Lines lines = solutionLines(chosenCipher, key, text, letters);
            results.push_back(header + " cipher=" + cipherName(chosenCipher) + " key=" + keyNotation(key) +
                " score=" + std::to_string(chosen->score) + " lines=" + std::to_string(lines.size()));
            append(results, lines);
            report.push_back("choice " + cipherName(chosenCipher));
        }
        append(analysis, report);
    }

public:
    CipherDesk(Weights weights, Messages messages)
        : weights(std::move(weights)), messages(std::move(messages)) {}

    void run(const std::string& line) {
        ++jobCount;
        Lines words = split(line, ' ');
        auto command = std::find(commands.begin(), commands.end(), words[0]);
        if (command == commands.end()) {
            results.push_back("JOB " + std::to_string(jobCount) + " ERROR unknown command");
            return;
        }
        std::size_t index = static_cast<std::size_t>(command - commands.begin());
        try {
            Job job = validate(std::move(words));
            if (job.command == "ENCRYPT" || job.command == "DECRYPT") {
                transformMessage(job);
            } else if (job.command == "BREAK") {
                breakMessage(job);
            } else if (job.command == "ANALYZE") {
                analyzeMessage(job);
            } else if (job.command == "COMPARE") {
                compareMessages(job);
            } else {
                identifyMessage(job);
            }
            ++okCounts[index];
        } catch (const JobError& error) {
            ++errorCounts[index];
            results.push_back("JOB " + std::to_string(jobCount) + " ERROR " + error.what());
        }
    }

    void finish() {
        int ok = 0;
        for (std::size_t index = 0; index < commands.size(); ++index) {
            ok += okCounts[index];
            results.push_back("TOTAL " + commands[index] + " ok=" + std::to_string(okCounts[index]) +
                              " errors=" + std::to_string(errorCounts[index]));
        }
        results.push_back("SUMMARY jobs=" + std::to_string(jobCount) + " ok=" + std::to_string(ok) +
            " errors=" + std::to_string(jobCount - ok) + " messages=" + std::to_string(messages.size()));
        std::filesystem::create_directories("output");
        const std::array<std::pair<std::string, const Lines*>, 3> files{{
            {"results.txt", &results}, {"candidates.txt", &candidates}, {"analysis.txt", &analysis}
        }};
        for (const auto& [name, lines] : files) {
            std::ofstream output("output/" + name, std::ios::binary);
            for (const std::string& line : *lines) {
                output << line << '\n';
            }
        }
    }
};

Messages readMessages(const std::string& path) {
    std::ifstream input(path);
    Messages messages;
    std::string line;
    std::string name;
    Lines body;
    while (std::getline(input, line)) {
        if (name.empty()) {
            if (!line.empty()) {
                name = line.substr(8);
                body.clear();
            }
        } else if (line == "END") {
            messages.emplace(name, std::move(body));
            name.clear();
        } else {
            body.push_back(line);
        }
    }
    return messages;
}

}

int main() {
    CipherDesk desk(readWeights("input/weights.txt"), readMessages("input/messages.txt"));
    std::ifstream jobs("input/jobs.txt");
    std::string line;
    while (std::getline(jobs, line)) {
        if (!line.empty() && line.front() != '#') {
            desk.run(line);
        }
    }
    desk.finish();
}
