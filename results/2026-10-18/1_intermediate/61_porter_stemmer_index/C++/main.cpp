#include <algorithm>
#include <cctype>
#include <cstddef>
#include <iostream>
#include <iterator>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr std::size_t kwicWidth = 30;
constexpr std::size_t maxWordLength = 30;
constexpr std::size_t maxNumberLength = 7;
constexpr int maxCount = 100;
constexpr int maxDocumentNumber = 999;
constexpr int maxLineNumber = 999;
const std::vector<std::string> stepNames = {"1a", "1b", "1c", "2", "3", "4", "5a", "5b"};
const std::vector<std::string> step4Suffixes = {
    "al",  "ance", "ence", "er", "ic",  "able", "ible", "ant", "ement", "ment",
    "ent", "ion",  "ou",   "ism", "ate", "iti", "ous",  "ive", "ize",
};

class CommandError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

bool isLetter(char character) {
    return std::isalpha(static_cast<unsigned char>(character)) != 0;
}

bool isDigit(char character) {
    return std::isdigit(static_cast<unsigned char>(character)) != 0;
}

bool isWord(const std::string& text) {
    return !text.empty() && text.size() <= maxWordLength &&
           std::all_of(text.begin(), text.end(), isLetter);
}

std::string toLower(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return text;
}

bool startsWith(const std::string& text, const std::string& prefix) {
    return text.compare(0, prefix.size(), prefix) == 0;
}

bool endsWith(const std::string& text, const std::string& suffix) {
    return text.size() >= suffix.size() &&
           text.compare(text.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool contains(const std::string& characters, char character) {
    return characters.find(character) != std::string::npos;
}

std::string join(const std::vector<std::string>& parts, const std::string& separator) {
    std::string result;
    for (std::size_t index = 0; index < parts.size(); ++index) {
        if (index > 0) {
            result += separator;
        }
        result += parts[index];
    }
    return result;
}

std::string letterPattern(const std::string& word) {
    std::string kinds;
    for (std::size_t index = 0; index < word.size(); ++index) {
        char letter = word[index];
        bool vowel =
            contains("aeiou", letter) || (letter == 'y' && index > 0 && kinds.back() == 'C');
        kinds += vowel ? 'V' : 'C';
    }
    return kinds;
}

int measure(const std::string& word) {
    std::string pattern = letterPattern(word);
    int count = 0;
    for (std::size_t index = 1; index < pattern.size(); ++index) {
        if (pattern[index - 1] == 'V' && pattern[index] == 'C') {
            ++count;
        }
    }
    return count;
}

bool hasVowel(const std::string& word) {
    return contains(letterPattern(word), 'V');
}

bool endsDouble(const std::string& word) {
    return endsWith(letterPattern(word), "CC") && word.back() == word[word.size() - 2];
}

bool endsCvc(const std::string& word) {
    return endsWith(letterPattern(word), "CVC") && !contains("wxy", word.back());
}

bool always(const std::string&) {
    return true;
}

bool measureAboveZero(const std::string& remainder) {
    return measure(remainder) > 0;
}

bool measureAboveOne(const std::string& remainder) {
    return measure(remainder) > 1;
}

bool ionCondition(const std::string& remainder) {
    return measure(remainder) > 1 && (endsWith(remainder, "s") || endsWith(remainder, "t"));
}

bool finalECondition(const std::string& remainder) {
    int value = measure(remainder);
    return value > 1 || (value == 1 && !endsCvc(remainder));
}

using Condition = bool (*)(const std::string&);

struct Rule {
    std::string suffix;
    std::string replacement;
    Condition condition;
};

std::vector<Rule> rulesWith(Condition condition,
                            const std::vector<std::pair<std::string, std::string>>& replacements) {
    std::vector<Rule> rules;
    for (const auto& [suffix, replacement] : replacements) {
        rules.push_back({suffix, replacement, condition});
    }
    return rules;
}

std::vector<Rule> step4Rules() {
    std::vector<Rule> rules;
    for (const std::string& suffix : step4Suffixes) {
        Condition condition = suffix == "ion" ? ionCondition : measureAboveOne;
        rules.push_back({suffix, "", condition});
    }
    return rules;
}

const std::map<std::string, std::vector<Rule>> ruleTables = {
    {"1a", rulesWith(always, {{"sses", "ss"}, {"ies", "i"}, {"ss", "ss"}, {"s", ""}})},
    {"1b", {{"eed", "ee", measureAboveZero}, {"ed", "", hasVowel}, {"ing", "", hasVowel}}},
    {"1c", {{"y", "i", hasVowel}}},
    {"2", rulesWith(measureAboveZero,
                    {{"ational", "ate"}, {"tional", "tion"}, {"enci", "ence"}, {"anci", "ance"},
                     {"izer", "ize"},    {"abli", "able"},   {"alli", "al"},   {"entli", "ent"},
                     {"eli", "e"},       {"ousli", "ous"},   {"ization", "ize"}, {"ation", "ate"},
                     {"ator", "ate"},    {"alism", "al"},    {"iveness", "ive"}, {"fulness", "ful"},
                     {"ousness", "ous"}, {"aliti", "al"},    {"iviti", "ive"}, {"biliti", "ble"}})},
    {"3", rulesWith(measureAboveZero,
                    {{"icate", "ic"}, {"ative", ""}, {"alize", "al"}, {"iciti", "ic"},
                     {"ical", "ic"}, {"ful", ""}, {"ness", ""}})},
    {"4", step4Rules()},
    {"5a", {{"e", "", finalECondition}}},
};

struct RuleOutcome {
    std::string word;
    std::optional<std::string> suffix;
};

RuleOutcome applyRules(const std::string& word, const std::vector<Rule>& rules) {
    const Rule* selected = nullptr;
    for (const Rule& rule : rules) {
        bool longer = selected == nullptr || rule.suffix.size() > selected->suffix.size();
        if (endsWith(word, rule.suffix) && longer) {
            selected = &rule;
        }
    }
    if (selected == nullptr) {
        return {word, std::nullopt};
    }
    std::string remainder = word.substr(0, word.size() - selected->suffix.size());
    if (!selected->condition(remainder)) {
        return {word, std::nullopt};
    }
    return {remainder + selected->replacement, selected->suffix};
}

std::string tidyStep1b(const std::string& word) {
    if (endsWith(word, "at") || endsWith(word, "bl") || endsWith(word, "iz")) {
        return word + "e";
    }
    if (endsDouble(word) && !contains("lsz", word.back())) {
        return word.substr(0, word.size() - 1);
    }
    if (measure(word) == 1 && endsCvc(word)) {
        return word + "e";
    }
    return word;
}

std::string applyStep(const std::string& name, const std::string& word) {
    if (name == "5b") {
        if (measure(word) > 1 && endsDouble(word) && endsWith(word, "l")) {
            return word.substr(0, word.size() - 1);
        }
        return word;
    }
    RuleOutcome outcome = applyRules(word, ruleTables.at(name));
    if (name == "1b" && (outcome.suffix == "ed" || outcome.suffix == "ing")) {
        return tidyStep1b(outcome.word);
    }
    return outcome.word;
}

struct StepChange {
    std::string step;
    std::string word;
};

struct Stemming {
    std::string stem;
    std::vector<StepChange> changes;
};

Stemming stemmingSteps(std::string word) {
    std::vector<StepChange> changes;
    if (word.size() > 2) {
        for (const std::string& name : stepNames) {
            std::string result = applyStep(name, word);
            if (result != word) {
                changes.push_back({name, result});
            }
            word = result;
        }
    }
    return {word, changes};
}

std::string porterStem(const std::string& word) {
    return stemmingSteps(word).stem;
}

std::string yesNo(bool flag) {
    return flag ? "YES" : "NO";
}

std::string wordArgument(const std::string& text) {
    if (!isWord(text)) {
        throw CommandError("BAD WORD " + text);
    }
    return toLower(text);
}

int numberArgument(const std::string& text, int minimum, int maximum) {
    if (text.empty() || text.size() > maxNumberLength ||
        !std::all_of(text.begin(), text.end(), isDigit)) {
        throw CommandError("BAD NUMBER " + text);
    }
    int value = std::stoi(text);
    if (value < minimum || value > maximum) {
        throw CommandError("BAD NUMBER " + text);
    }
    return value;
}

std::vector<std::string> splitArguments(const std::string& name, const std::string& rest) {
    if (name == "SEARCH") {
        return {rest};
    }
    if (name == "APPEND") {
        std::size_t space = rest.find(' ');
        if (space == std::string::npos) {
            return {rest};
        }
        return {rest.substr(0, space), rest.substr(space + 1)};
    }
    std::vector<std::string> parts;
    std::size_t start = 0;
    while (true) {
        std::size_t space = rest.find(' ', start);
        parts.push_back(rest.substr(start, space - start));
        if (space == std::string::npos) {
            return parts;
        }
        start = space + 1;
    }
}

using Counts = std::map<std::string, int>;
using StemCount = std::pair<std::string, int>;

std::vector<StemCount> rankedCounts(const Counts& counts) {
    std::vector<StemCount> ranked(counts.begin(), counts.end());
    std::sort(ranked.begin(), ranked.end(), [](const StemCount& left, const StemCount& right) {
        if (left.second != right.second) {
            return left.second > right.second;
        }
        return left.first < right.first;
    });
    return ranked;
}

int countOf(const Counts& counts, const std::string& stem) {
    auto found = counts.find(stem);
    return found == counts.end() ? 0 : found->second;
}

std::optional<int> closestDistance(const std::vector<int>& positions,
                                   const std::vector<int>& others, bool sameStem) {
    std::vector<int> gaps;
    if (sameStem) {
        for (std::size_t index = 1; index < positions.size(); ++index) {
            gaps.push_back(positions[index] - positions[index - 1]);
        }
    } else {
        // The closest pair of different stems is adjacent in the merged order.
        std::vector<std::pair<int, int>> merged;
        for (int position : positions) {
            merged.emplace_back(position, 0);
        }
        for (int other : others) {
            merged.emplace_back(other, 1);
        }
        std::sort(merged.begin(), merged.end());
        for (std::size_t index = 1; index < merged.size(); ++index) {
            if (merged[index - 1].second != merged[index].second) {
                gaps.push_back(merged[index].first - merged[index - 1].first);
            }
        }
    }
    if (gaps.empty()) {
        return std::nullopt;
    }
    return *std::min_element(gaps.begin(), gaps.end());
}

struct Fraction {
    int numerator;
    int denominator;
};

struct Similarity {
    int document;
    Fraction score;
};

struct RankEntry {
    int document;
    int matched;
    int total;
};

struct Token {
    std::string text;
    std::string form;
    std::string stem;
    int line;
    int position;
    std::size_t start;

    std::size_t end() const {
        return start + text.size();
    }
};

struct Document {
    int number;
    std::vector<std::string> lines;
    std::vector<Token> tokens;

    explicit Document(int number) : number(number) {}

    std::vector<Token> addLine(const std::string& text) {
        lines.push_back(text);
        std::vector<Token> added;
        std::size_t index = 0;
        while (index < text.size()) {
            if (!isLetter(text[index])) {
                ++index;
                continue;
            }
            std::size_t start = index;
            while (index < text.size() && isLetter(text[index])) {
                ++index;
            }
            std::string word = text.substr(start, index - start);
            std::string form = toLower(word);
            Token token{word,  form, porterStem(form), static_cast<int>(lines.size()),
                        static_cast<int>(tokens.size()) + 1, start};
            tokens.push_back(token);
            added.push_back(token);
        }
        return added;
    }

    std::vector<Token> lineTokens(int lineNumber) const {
        std::vector<Token> result;
        std::copy_if(tokens.begin(), tokens.end(), std::back_inserter(result),
                     [lineNumber](const Token& token) { return token.line == lineNumber; });
        return result;
    }

    std::string reference(const Token& token) const {
        return std::to_string(number) + ":" + std::to_string(token.line) + ":" +
               std::to_string(token.position);
    }
};

struct Occurrence {
    const Document* document;
    const Token* token;
};

std::size_t documentCount(const std::vector<Occurrence>& occurrences) {
    std::set<int> numbers;
    for (const Occurrence& occurrence : occurrences) {
        numbers.insert(occurrence.document->number);
    }
    return numbers.size();
}

enum class ItemKind { And, Or, Not, Open, Close, Term, Prefix };

struct QueryItem {
    ItemKind kind;
    std::string spelling;
};

const std::map<std::string, ItemKind> symbols = {
    {"AND", ItemKind::And},  {"OR", ItemKind::Or},     {"NOT", ItemKind::Not},
    {"(", ItemKind::Open}, {")", ItemKind::Close},
};

std::vector<std::string> lexemes(const std::string& expression) {
    std::vector<std::string> result;
    std::size_t index = 0;
    while (index < expression.size()) {
        char character = expression[index];
        if (character == ' ') {
            ++index;
        } else if (character == '(' || character == ')') {
            result.emplace_back(1, character);
            ++index;
        } else {
            std::size_t start = index;
            while (index < expression.size() && !contains(" ()", expression[index])) {
                ++index;
            }
            result.push_back(expression.substr(start, index - start));
        }
    }
    return result;
}

QueryItem classify(const std::string& lexeme) {
    auto symbol = symbols.find(lexeme);
    if (symbol != symbols.end()) {
        return {symbol->second, lexeme};
    }
    if (isWord(lexeme)) {
        return {ItemKind::Term, toLower(lexeme)};
    }
    std::string letters = lexeme.substr(0, lexeme.size() - 1);
    if (lexeme.back() == '*' && isWord(letters)) {
        return {ItemKind::Prefix, toLower(letters)};
    }
    throw CommandError("BAD TERM " + lexeme);
}

using StemSets = std::map<int, std::set<std::string>>;

struct QueryResult {
    std::string canonical;
    std::set<int> documents;
};

class QueryParser {
public:
    QueryParser(const std::vector<QueryItem>& items, const StemSets& stemSets)
        : items(items), stemSets(stemSets) {}

    QueryResult parse() {
        QueryResult result = expression();
        if (position < items.size()) {
            throw CommandError("SYNTAX");
        }
        return result;
    }

private:
    const std::vector<QueryItem>& items;
    const StemSets& stemSets;
    std::size_t position = 0;

    std::optional<ItemKind> peek() const {
        if (position < items.size()) {
            return items[position].kind;
        }
        return std::nullopt;
    }

    const QueryItem& take() {
        if (position >= items.size()) {
            throw CommandError("SYNTAX");
        }
        return items[position++];
    }

    bool continuesConjunction() const {
        std::optional<ItemKind> kind = peek();
        return kind == ItemKind::And || kind == ItemKind::Not || kind == ItemKind::Open ||
               kind == ItemKind::Term || kind == ItemKind::Prefix;
    }

    QueryResult expression() {
        QueryResult result = conjunction();
        while (peek() == ItemKind::Or) {
            ++position;
            QueryResult right = conjunction();
            result.canonical = "(" + result.canonical + " OR " + right.canonical + ")";
            result.documents.insert(right.documents.begin(), right.documents.end());
        }
        return result;
    }

    QueryResult conjunction() {
        QueryResult result = negation();
        while (continuesConjunction()) {
            if (peek() == ItemKind::And) {
                ++position;
            }
            QueryResult right = negation();
            std::set<int> common;
            std::set_intersection(result.documents.begin(), result.documents.end(),
                                  right.documents.begin(), right.documents.end(),
                                  std::inserter(common, common.end()));
            result.canonical = "(" + result.canonical + " AND " + right.canonical + ")";
            result.documents = common;
        }
        return result;
    }

    QueryResult negation() {
        if (peek() == ItemKind::Not) {
            ++position;
            QueryResult inner = negation();
            std::set<int> documents;
            for (const auto& [number, stems] : stemSets) {
                if (inner.documents.count(number) == 0) {
                    documents.insert(number);
                }
            }
            return {"(NOT " + inner.canonical + ")", documents};
        }
        return element();
    }

    QueryResult element() {
        const QueryItem& item = take();
        if (item.kind == ItemKind::Open) {
            QueryResult result = expression();
            if (take().kind != ItemKind::Close) {
                throw CommandError("SYNTAX");
            }
            return result;
        }
        if (item.kind == ItemKind::Term) {
            std::string stem = porterStem(item.spelling);
            std::set<int> documents;
            for (const auto& [number, stems] : stemSets) {
                if (stems.count(stem) > 0) {
                    documents.insert(number);
                }
            }
            return {stem, documents};
        }
        if (item.kind == ItemKind::Prefix) {
            std::set<int> documents;
            for (const auto& [number, stems] : stemSets) {
                bool found =
                    std::any_of(stems.begin(), stems.end(), [&item](const std::string& stem) {
                        return startsWith(stem, item.spelling);
                    });
                if (found) {
                    documents.insert(number);
                }
            }
            return {item.spelling + "*", documents};
        }
        throw CommandError("SYNTAX");
    }
};

class SearchEngine {
public:
    SearchEngine(std::set<std::string> stopwords, std::ostream& out)
        : stopwords(std::move(stopwords)), out(out) {}

    Document& addDocument(int number) {
        return documents.emplace(number, Document(number)).first->second;
    }

    void execute(const std::string& line) {
        std::size_t space = line.find(' ');
        std::string name = line.substr(0, space);
        try {
            auto found = commands().find(name);
            if (found == commands().end()) {
                throw CommandError("UNKNOWN COMMAND " + name);
            }
            const Command& command = found->second;
            Arguments arguments;
            if (space != std::string::npos) {
                arguments = splitArguments(name, line.substr(space + 1));
            }
            if (arguments.size() < command.minimum || arguments.size() > command.maximum) {
                throw CommandError("BAD ARGUMENTS " + name);
            }
            (this->*command.handler)(arguments);
        } catch (const CommandError& error) {
            emit("ERROR " + std::string(error.what()));
        }
    }

private:
    using Arguments = std::vector<std::string>;
    using Handler = void (SearchEngine::*)(const Arguments&);

    struct Command {
        std::size_t minimum;
        std::size_t maximum;
        Handler handler;
    };

    std::set<std::string> stopwords;
    std::map<int, Document> documents;
    std::ostream& out;

    static const std::map<std::string, Command>& commands() {
        static const std::map<std::string, Command> table = {
            {"STEM", {1, 10, &SearchEngine::stemWords}},
            {"STEPS", {1, 1, &SearchEngine::showSteps}},
            {"MEASURE", {1, 1, &SearchEngine::showMeasure}},
            {"INDEX", {0, 1, &SearchEngine::showIndex}},
            {"SEARCH", {1, 1, &SearchEngine::search}},
            {"PHRASE", {2, 10, &SearchEngine::phrase}},
            {"NEAR", {3, 3, &SearchEngine::near}},
            {"TOP", {1, 2, &SearchEngine::top}},
            {"KWIC", {1, 1, &SearchEngine::kwic}},
            {"TF", {2, 2, &SearchEngine::termFrequency}},
            {"DF", {1, 1, &SearchEngine::documentFrequency}},
            {"VARIANTS", {1, 1, &SearchEngine::variants}},
            {"SIMILAR", {2, 2, &SearchEngine::similar}},
            {"RANK", {2, 11, &SearchEngine::rank}},
            {"INFO", {1, 1, &SearchEngine::info}},
            {"LINE", {2, 2, &SearchEngine::showLine}},
            {"STATS", {0, 0, &SearchEngine::stats}},
            {"STOP", {1, 1, &SearchEngine::stop}},
            {"UNSTOP", {1, 1, &SearchEngine::unstop}},
            {"APPEND", {2, 2, &SearchEngine::append}},
            {"DELETE", {1, 1, &SearchEngine::deleteDocument}},
        };
        return table;
    }

    void emit(const std::string& head, const std::vector<std::string>& items = {}) {
        out << head;
        for (const std::string& item : items) {
            out << ' ' << item;
        }
        out << '\n';
    }

    bool isStopword(const std::string& word) const {
        return stopwords.count(word) > 0;
    }

    bool isIndexed(const Token& token) const {
        return !isStopword(token.form);
    }

    int indexedCount(const Document& document) const {
        return static_cast<int>(
            std::count_if(document.tokens.begin(), document.tokens.end(),
                          [this](const Token& token) { return isIndexed(token); }));
    }

    Counts termFrequencies(const Document& document) const {
        Counts counts;
        for (const Token& token : document.tokens) {
            if (isIndexed(token)) {
                ++counts[token.stem];
            }
        }
        return counts;
    }

    std::set<std::string> stemSet(const Document& document) const {
        std::set<std::string> stems;
        for (const Token& token : document.tokens) {
            if (isIndexed(token)) {
                stems.insert(token.stem);
            }
        }
        return stems;
    }

    Counts totalFrequencies() const {
        Counts totals;
        for (const auto& [number, document] : documents) {
            for (const auto& [stem, count] : termFrequencies(document)) {
                totals[stem] += count;
            }
        }
        return totals;
    }

    std::map<std::string, std::vector<Occurrence>> occurrenceMap() const {
        std::map<std::string, std::vector<Occurrence>> occurrences;
        for (const auto& [number, document] : documents) {
            for (const Token& token : document.tokens) {
                if (isIndexed(token)) {
                    occurrences[token.stem].push_back({&document, &token});
                }
            }
        }
        return occurrences;
    }

    std::vector<Occurrence> occurrencesOf(const std::string& stem) const {
        std::map<std::string, std::vector<Occurrence>> occurrences = occurrenceMap();
        auto found = occurrences.find(stem);
        return found == occurrences.end() ? std::vector<Occurrence>{} : found->second;
    }

    std::vector<int> stemPositions(const Document& document, const std::string& stem) const {
        std::vector<int> positions;
        for (const Token& token : document.tokens) {
            if (isIndexed(token) && token.stem == stem) {
                positions.push_back(token.position);
            }
        }
        return positions;
    }

    int formCount(const std::string& form) const {
        int count = 0;
        for (const auto& [number, document] : documents) {
            count += static_cast<int>(
                std::count_if(document.tokens.begin(), document.tokens.end(),
                              [&form](const Token& token) { return token.form == form; }));
        }
        return count;
    }

    bool tokenMatches(const Token& token, const std::string& target) const {
        return target == "?" || (isIndexed(token) && token.stem == target);
    }

    std::string describeToken(const Token& token) const {
        return token.form + "/" + (isIndexed(token) ? token.stem : "-");
    }

    std::string termArgument(const std::string& text) const {
        std::string word = wordArgument(text);
        if (isStopword(word)) {
            throw CommandError("STOPWORD " + word);
        }
        return porterStem(word);
    }

    const Document& documentArgument(const std::string& text) const {
        int number = numberArgument(text, 1, maxDocumentNumber);
        auto found = documents.find(number);
        if (found == documents.end()) {
            throw CommandError("NO DOC " + std::to_string(number));
        }
        return found->second;
    }

    void stemWords(const Arguments& arguments) {
        std::vector<std::string> items;
        for (const std::string& argument : arguments) {
            std::string word = wordArgument(argument);
            items.push_back(word + ":" + porterStem(word));
        }
        emit("STEM", items);
    }

    void showSteps(const Arguments& arguments) {
        std::string word = wordArgument(arguments[0]);
        std::vector<StepChange> changes = stemmingSteps(word).changes;
        if (changes.empty()) {
            emit("STEPS " + word + " NONE");
            return;
        }
        std::vector<std::string> items;
        for (const StepChange& change : changes) {
            items.push_back(change.step + ":" + change.word);
        }
        emit("STEPS " + word, items);
    }

    void showMeasure(const Arguments& arguments) {
        std::string word = wordArgument(arguments[0]);
        emit("MEASURE " + word + " " + letterPattern(word) + " m=" + std::to_string(measure(word)) +
             " vowel=" + yesNo(hasVowel(word)) + " double=" + yesNo(endsDouble(word)) +
             " cvc=" + yesNo(endsCvc(word)));
    }

    void showIndex(const Arguments& arguments) {
        std::string prefix = arguments.empty() ? "" : wordArgument(arguments[0]);
        std::map<std::string, std::vector<Occurrence>> occurrences = occurrenceMap();
        std::vector<std::string> stems;
        for (const auto& [stem, found] : occurrences) {
            if (startsWith(stem, prefix)) {
                stems.push_back(stem);
            }
        }
        emit("INDEX stems=" + std::to_string(stems.size()));
        for (const std::string& stem : stems) {
            const std::vector<Occurrence>& found = occurrences[stem];
            std::vector<std::string> references;
            for (const Occurrence& occurrence : found) {
                references.push_back(occurrence.document->reference(*occurrence.token));
            }
            emit(stem + " df=" + std::to_string(documentCount(found)), references);
        }
    }

    void search(const Arguments& arguments) {
        std::vector<QueryItem> items;
        for (const std::string& lexeme : lexemes(arguments[0])) {
            items.push_back(classify(lexeme));
        }
        StemSets stemSets;
        for (const auto& [number, document] : documents) {
            stemSets[number] = stemSet(document);
        }
        QueryResult result = QueryParser(items, stemSets).parse();
        for (const QueryItem& item : items) {
            if (item.kind == ItemKind::Term && isStopword(item.spelling)) {
                throw CommandError("STOPWORD " + item.spelling);
            }
        }
        std::vector<std::string> numbers;
        for (int number : result.documents) {
            numbers.push_back(std::to_string(number));
        }
        emit("SEARCH " + result.canonical + " count=" + std::to_string(result.documents.size()),
             numbers);
    }

    void phrase(const Arguments& arguments) {
        std::vector<std::string> words;
        for (const std::string& argument : arguments) {
            words.push_back(wordArgument(argument));
        }
        if (std::all_of(words.begin(), words.end(),
                        [this](const std::string& word) { return isStopword(word); })) {
            throw CommandError("STOPWORDS ONLY");
        }
        std::vector<std::string> targets;
        for (const std::string& word : words) {
            targets.push_back(isStopword(word) ? "?" : porterStem(word));
        }
        std::vector<std::string> matches;
        for (const auto& [number, document] : documents) {
            const std::vector<Token>& tokens = document.tokens;
            for (std::size_t start = 0; start + targets.size() <= tokens.size(); ++start) {
                bool matched = true;
                for (std::size_t offset = 0; offset < targets.size() && matched; ++offset) {
                    matched = tokenMatches(tokens[start + offset], targets[offset]);
                }
                if (matched) {
                    matches.push_back(document.reference(tokens[start]));
                }
            }
        }
        emit("PHRASE \"" + join(targets, " ") + "\" matches=" + std::to_string(matches.size()),
             matches);
    }

    void near(const Arguments& arguments) {
        std::string first = termArgument(arguments[0]);
        std::string second = termArgument(arguments[1]);
        int limit = numberArgument(arguments[2], 1, maxCount);
        std::vector<std::string> found;
        for (const auto& [number, document] : documents) {
            std::optional<int> distance = closestDistance(
                stemPositions(document, first), stemPositions(document, second), first == second);
            if (distance && *distance <= limit) {
                found.push_back(std::to_string(number) + ":" + std::to_string(*distance));
            }
        }
        emit("NEAR " + first + " " + second + " " + std::to_string(limit) +
                 " count=" + std::to_string(found.size()),
             found);
    }

    void top(const Arguments& arguments) {
        int limit = numberArgument(arguments[0], 1, maxCount);
        std::string header = "TOP " + std::to_string(limit);
        Counts counts;
        if (arguments.size() == 2) {
            const Document& document = documentArgument(arguments[1]);
            counts = termFrequencies(document);
            header += " doc=" + std::to_string(document.number);
        } else {
            counts = totalFrequencies();
        }
        std::vector<StemCount> ranked = rankedCounts(counts);
        ranked.resize(std::min(ranked.size(), static_cast<std::size_t>(limit)));
        std::vector<std::string> items;
        for (const auto& [stem, count] : ranked) {
            items.push_back(stem + ":" + std::to_string(count));
        }
        emit(header, items);
    }

    void kwic(const Arguments& arguments) {
        std::string stem = termArgument(arguments[0]);
        std::vector<Occurrence> found = occurrencesOf(stem);
        emit("KWIC " + stem + " count=" + std::to_string(found.size()));
        for (const Occurrence& occurrence : found) {
            const Token& token = *occurrence.token;
            const std::string& text = occurrence.document->lines[token.line - 1];
            std::size_t from = token.start > kwicWidth ? token.start - kwicWidth : 0;
            std::string before = text.substr(from, token.start - from);
            std::string after = text.substr(token.end(), kwicWidth);
            before.insert(0, kwicWidth - before.size(), ' ');
            after.append(kwicWidth - after.size(), ' ');
            emit("|" + before + "[" + token.text + "]" + after + "| " +
                 occurrence.document->reference(token));
        }
    }

    void termFrequency(const Arguments& arguments) {
        const Document& document = documentArgument(arguments[0]);
        std::string stem = termArgument(arguments[1]);
        emit("TF " + std::to_string(document.number) + " " + stem + " " +
             std::to_string(countOf(termFrequencies(document), stem)));
    }

    void documentFrequency(const Arguments& arguments) {
        std::string stem = termArgument(arguments[0]);
        emit("DF " + stem + " " + std::to_string(documentCount(occurrencesOf(stem))));
    }

    void variants(const Arguments& arguments) {
        std::string stem = termArgument(arguments[0]);
        Counts forms;
        for (const Occurrence& occurrence : occurrencesOf(stem)) {
            ++forms[occurrence.token->form];
        }
        std::vector<std::string> items;
        for (const auto& [form, count] : forms) {
            items.push_back(form + ":" + std::to_string(count));
        }
        emit("VARIANTS " + stem + " count=" + std::to_string(forms.size()), items);
    }

    void similar(const Arguments& arguments) {
        const Document& document = documentArgument(arguments[0]);
        int limit = numberArgument(arguments[1], 1, maxCount);
        std::set<std::string> stems = stemSet(document);
        std::vector<Similarity> scores;
        for (const auto& [number, other] : documents) {
            if (number == document.number) {
                continue;
            }
            std::set<std::string> otherStems = stemSet(other);
            int common = static_cast<int>(
                std::count_if(stems.begin(), stems.end(), [&otherStems](const std::string& stem) {
                    return otherStems.count(stem) > 0;
                }));
            int unionSize = static_cast<int>(stems.size() + otherStems.size()) - common;
            Fraction score{0, 1};
            if (unionSize > 0) {
                int divisor = std::gcd(common, unionSize);
                score = {common / divisor, unionSize / divisor};
            }
            scores.push_back({number, score});
        }
        auto byScore = [](const Similarity& left, const Similarity& right) {
            long long leftScore =
                static_cast<long long>(left.score.numerator) * right.score.denominator;
            long long rightScore =
                static_cast<long long>(right.score.numerator) * left.score.denominator;
            if (leftScore != rightScore) {
                return leftScore > rightScore;
            }
            return left.document < right.document;
        };
        std::sort(scores.begin(), scores.end(), byScore);
        scores.resize(std::min(scores.size(), static_cast<std::size_t>(limit)));
        std::vector<std::string> items;
        for (const Similarity& entry : scores) {
            items.push_back(std::to_string(entry.document) + ":" +
                            std::to_string(entry.score.numerator) + "/" +
                            std::to_string(entry.score.denominator));
        }
        emit("SIMILAR " + std::to_string(document.number), items);
    }

    void rank(const Arguments& arguments) {
        int limit = numberArgument(arguments[0], 1, maxCount);
        std::set<std::string> query;
        for (std::size_t index = 1; index < arguments.size(); ++index) {
            query.insert(termArgument(arguments[index]));
        }
        std::vector<RankEntry> ranked;
        for (const auto& [number, document] : documents) {
            Counts counts = termFrequencies(document);
            int matched = 0;
            int total = 0;
            for (const std::string& stem : query) {
                int count = countOf(counts, stem);
                if (count > 0) {
                    ++matched;
                }
                total += count;
            }
            if (matched > 0) {
                ranked.push_back({number, matched, total});
            }
        }
        std::sort(ranked.begin(), ranked.end(), [](const RankEntry& left, const RankEntry& right) {
            if (left.matched != right.matched) {
                return left.matched > right.matched;
            }
            if (left.total != right.total) {
                return left.total > right.total;
            }
            return left.document < right.document;
        });
        std::vector<std::string> items;
        std::size_t shown = std::min(ranked.size(), static_cast<std::size_t>(limit));
        for (std::size_t index = 0; index < shown; ++index) {
            const RankEntry& entry = ranked[index];
            items.push_back(std::to_string(entry.document) + ":" + std::to_string(entry.matched) +
                            ":" + std::to_string(entry.total));
        }
        emit("RANK count=" + std::to_string(ranked.size()), items);
    }

    void info(const Arguments& arguments) {
        const Document& document = documentArgument(arguments[0]);
        Counts counts = termFrequencies(document);
        std::string top = "-";
        if (!counts.empty()) {
            StemCount best = rankedCounts(counts).front();
            top = best.first + ":" + std::to_string(best.second);
        }
        emit("INFO " + std::to_string(document.number) +
             " lines=" + std::to_string(document.lines.size()) +
             " tokens=" + std::to_string(document.tokens.size()) +
             " indexed=" + std::to_string(indexedCount(document)) +
             " stems=" + std::to_string(counts.size()) + " top=" + top);
    }

    void showLine(const Arguments& arguments) {
        const Document& document = documentArgument(arguments[0]);
        int lineNumber = numberArgument(arguments[1], 1, maxLineNumber);
        std::string location = std::to_string(document.number) + ":" + std::to_string(lineNumber);
        if (lineNumber > static_cast<int>(document.lines.size())) {
            throw CommandError("NO LINE " + location);
        }
        std::vector<std::string> items;
        for (const Token& token : document.lineTokens(lineNumber)) {
            items.push_back(describeToken(token));
        }
        emit("LINE " + location + " tokens=" + std::to_string(items.size()), items);
    }

    void stats(const Arguments&) {
        std::size_t lines = 0;
        std::size_t tokens = 0;
        int indexed = 0;
        for (const auto& [number, document] : documents) {
            lines += document.lines.size();
            tokens += document.tokens.size();
            indexed += indexedCount(document);
        }
        emit("STATS docs=" + std::to_string(documents.size()) + " lines=" + std::to_string(lines) +
             " tokens=" + std::to_string(tokens) + " indexed=" + std::to_string(indexed) +
             " stems=" + std::to_string(totalFrequencies().size()) +
             " stopwords=" + std::to_string(stopwords.size()));
    }

    void stop(const Arguments& arguments) {
        std::string word = wordArgument(arguments[0]);
        if (isStopword(word)) {
            throw CommandError("ALREADY STOPWORD " + word);
        }
        stopwords.insert(word);
        emit("STOP " + word + " unindexed=" + std::to_string(formCount(word)));
    }

    void unstop(const Arguments& arguments) {
        std::string word = wordArgument(arguments[0]);
        if (!isStopword(word)) {
            throw CommandError("NOT STOPWORD " + word);
        }
        stopwords.erase(word);
        emit("UNSTOP " + word + " indexed=" + std::to_string(formCount(word)));
    }

    void append(const Arguments& arguments) {
        int number = numberArgument(arguments[0], 1, maxDocumentNumber);
        bool created = documents.count(number) == 0;
        Document& document = addDocument(number);
        std::vector<Token> tokens = document.addLine(arguments[1]);
        long indexed = std::count_if(tokens.begin(), tokens.end(),
                                     [this](const Token& token) { return isIndexed(token); });
        emit("APPEND " + std::to_string(number) + " line=" + std::to_string(document.lines.size()) +
             " tokens=" + std::to_string(tokens.size()) + " indexed=" + std::to_string(indexed) +
             " new=" + yesNo(created));
    }

    void deleteDocument(const Arguments& arguments) {
        const Document& document = documentArgument(arguments[0]);
        int number = document.number;
        std::string summary = "DELETE " + std::to_string(number) +
                              " lines=" + std::to_string(document.lines.size()) +
                              " tokens=" + std::to_string(document.tokens.size());
        documents.erase(number);
        emit(summary);
    }
};

}  // namespace

int main() {
    std::ios::sync_with_stdio(false);
    std::vector<std::string> lines;
    std::string line;
    while (std::getline(std::cin, line)) {
        lines.push_back(line);
    }
    std::istringstream header(lines[0]);
    std::vector<std::string> words{std::istream_iterator<std::string>(header), {}};
    SearchEngine engine(std::set<std::string>(words.begin() + 1, words.end()), std::cout);
    std::size_t index = 1;
    while (startsWith(lines[index], "DOC ")) {
        Document& document = engine.addDocument(std::stoi(lines[index].substr(4)));
        ++index;
        while (lines[index] != "ENDDOC") {
            document.addLine(lines[index]);
            ++index;
        }
        ++index;
    }
    for (; index < lines.size() && lines[index] != "END"; ++index) {
        engine.execute(lines[index]);
    }
    return 0;
}
