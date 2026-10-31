#include <algorithm>
#include <cctype>
#include <initializer_list>
#include <iomanip>
#include <iostream>
#include <map>
#include <optional>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Lines = std::vector<std::string>;

const Lines kDataCommands = {"FILE", "PATCH", "EDIT"};
const Lines kFormatsWithArgument = {"IFDEF", "UNIFIED", "CONTEXT", "SIDE"};
const std::vector<int> kOffsets = {0, 1, -1, 2, -2, 3, -3};
constexpr int kGraphWidth = 20;
const std::regex kNumberPair("([0-9]{1,4})(?:,([0-9]{1,4}))?");
const std::string kSeparator = "=======";

class CommandError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

template <typename... Parts>
std::string concat(const Parts&... parts) {
    std::ostringstream stream;
    (stream << ... << parts);
    return stream.str();
}

int length(const Lines& lines) { return static_cast<int>(lines.size()); }

bool contains(const Lines& words, const std::string& word) {
    return std::find(words.begin(), words.end(), word) != words.end();
}

Lines slice(const Lines& lines, int start, int end) {
    return Lines(lines.begin() + start, lines.begin() + end);
}

void append(Lines& target, const Lines& items) {
    target.insert(target.end(), items.begin(), items.end());
}

void appendPrefixed(Lines& target, const std::string& prefix, const Lines& items) {
    for (const std::string& item : items) {
        target.push_back(prefix + item);
    }
}

std::string join(const Lines& parts, const std::string& separator) {
    std::string result;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i > 0) result += separator;
        result += parts[i];
    }
    return result;
}

Lines split(const std::string& text, char delimiter) {
    Lines parts;
    std::size_t start = 0;
    while (true) {
        const std::size_t end = text.find(delimiter, start);
        parts.push_back(text.substr(start, end - start));
        if (end == std::string::npos) return parts;
        start = end + 1;
    }
}

std::string rangeR(int start, int count) {
    if (count >= 2) return concat(start + 1, ",", start + count);
    if (count == 1) return std::to_string(start + 1);
    return std::to_string(start);
}

std::string rangeU(int start, int count) {
    if (count >= 2) return concat(start + 1, ",", count);
    if (count == 1) return std::to_string(start + 1);
    return concat(start, ",0");
}

std::string rangeM(int start, int count) { return concat(start + 1, ",", count); }

std::string comparisonKey(std::string line, const Lines& options) {
    if (contains(options, "ICASE")) {
        std::transform(line.begin(), line.end(), line.begin(),
                       [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    }
    if (contains(options, "IWHITE")) {
        line.erase(std::remove(line.begin(), line.end(), ' '), line.end());
    }
    if (contains(options, "ISPACE")) {
        static const std::regex spaces(" {2,}");
        line = std::regex_replace(line, spaces, " ");
    }
    return line;
}

Lines comparisonKeys(const Lines& lines, const Lines& options) {
    Lines keys;
    for (const std::string& line : lines) {
        keys.push_back(comparisonKey(line, options));
    }
    return keys;
}

std::vector<std::pair<int, int>> matchedPairs(const Lines& first, const Lines& second) {
    const int rows = length(first);
    const int columns = length(second);
    std::vector<std::vector<int>> table(rows + 1, std::vector<int>(columns + 1, 0));
    for (int i = 1; i <= rows; ++i) {
        for (int j = 1; j <= columns; ++j) {
            if (first[i - 1] == second[j - 1]) {
                table[i][j] = table[i - 1][j - 1] + 1;
            } else {
                table[i][j] = std::max(table[i - 1][j], table[i][j - 1]);
            }
        }
    }
    std::vector<std::pair<int, int>> pairs = {{rows + 1, columns + 1}};
    int i = rows;
    int j = columns;
    while (i >= 1 && j >= 1) {
        if (first[i - 1] == second[j - 1]) {
            pairs.emplace_back(i, j);
            --i;
            --j;
        } else if (table[i - 1][j] >= table[i][j - 1]) {
            --i;
        } else {
            --j;
        }
    }
    pairs.emplace_back(0, 0);
    std::reverse(pairs.begin(), pairs.end());
    return pairs;
}

struct ChangeBlock {
    int p;
    int q;
    int x;
    int y;

    char letter() const {
        if (x >= 1 && y >= 1) return 'c';
        return y == 0 ? 'd' : 'a';
    }
};

std::vector<ChangeBlock> changeBlocks(const Lines& first, const Lines& second) {
    const std::vector<std::pair<int, int>> pairs = matchedPairs(first, second);
    std::vector<ChangeBlock> blocks;
    for (std::size_t k = 0; k + 1 < pairs.size(); ++k) {
        const auto [i, j] = pairs[k];
        const auto [nextI, nextJ] = pairs[k + 1];
        if (nextI - i > 1 || nextJ - j > 1) {
            blocks.push_back({i, j, nextI - i - 1, nextJ - j - 1});
        }
    }
    return blocks;
}

struct Step {
    int oldIndex;
    int newIndex;
    const ChangeBlock* block;
};

std::vector<Step> walk(const std::vector<ChangeBlock>& blocks, int oldStart, int newStart,
                       int oldEnd) {
    std::vector<Step> steps;
    int oldIndex = oldStart;
    int newIndex = newStart;
    for (const ChangeBlock& block : blocks) {
        while (oldIndex < block.p) {
            steps.push_back({oldIndex++, newIndex++, nullptr});
        }
        steps.push_back({oldIndex, newIndex, &block});
        oldIndex = block.p + block.x;
        newIndex = block.q + block.y;
    }
    while (oldIndex < oldEnd) {
        steps.push_back({oldIndex++, newIndex++, nullptr});
    }
    return steps;
}

std::string sideRow(const std::string& left, char symbol, const std::string& right, int width) {
    std::string row = left.substr(0, width);
    row.resize(width, ' ');
    row += concat(' ', symbol, ' ', right.substr(0, width));
    row.erase(row.find_last_not_of(' ') + 1);
    return row;
}

std::string statGraph(int inserted, int deleted) {
    const int total = inserted + deleted;
    int plus = inserted;
    int minus = deleted;
    if (total > kGraphWidth) {
        plus = kGraphWidth * inserted / total;
        minus = kGraphWidth * deleted / total;
        if (inserted >= 1 && plus == 0) plus = 1;
        if (deleted >= 1 && minus == 0) minus = 1;
    }
    return std::string(plus, '+') + std::string(minus, '-');
}

struct Hunk {
    std::vector<ChangeBlock> blocks;
    int oldStart;
    int oldCount;
    int newStart;
    int newCount;

    Hunk(std::vector<ChangeBlock> group, int context, int oldTotal) : blocks(std::move(group)) {
        const ChangeBlock& first = blocks.front();
        const ChangeBlock& last = blocks.back();
        const int before = std::min(context, first.p);
        const int after = std::min(context, oldTotal - last.p - last.x);
        oldStart = first.p - before;
        oldCount = last.p + last.x + after - oldStart;
        newStart = first.q - before;
        newCount = last.q + last.y + after - newStart;
    }

    std::vector<Step> steps() const {
        return walk(blocks, oldStart, newStart, oldStart + oldCount);
    }
};

class LineDiff {
public:
    const Lines oldLines;
    const Lines newLines;
    const std::vector<ChangeBlock> blocks;

    LineDiff(const Lines& oldLines, const Lines& newLines, const Lines& options = {})
        : oldLines(oldLines),
          newLines(newLines),
          blocks(
              changeBlocks(comparisonKeys(oldLines, options), comparisonKeys(newLines, options))) {}

    Lines deleted(const ChangeBlock& block) const {
        return slice(oldLines, block.p, block.p + block.x);
    }

    Lines inserted(const ChangeBlock& block) const {
        return slice(newLines, block.q, block.q + block.y);
    }

    std::vector<Hunk> hunks(int context) const {
        std::vector<std::vector<ChangeBlock>> groups;
        for (const ChangeBlock& block : blocks) {
            if (!groups.empty()) {
                const ChangeBlock& previous = groups.back().back();
                if (block.p - (previous.p + previous.x) <= 2 * context) {
                    groups.back().push_back(block);
                    continue;
                }
            }
            groups.push_back({block});
        }
        std::vector<Hunk> result;
        for (std::vector<ChangeBlock>& group : groups) {
            result.emplace_back(std::move(group), context, length(oldLines));
        }
        return result;
    }

    Lines normal() const {
        Lines lines;
        for (const ChangeBlock& block : blocks) {
            const char letter = block.letter();
            lines.push_back(rangeR(block.p, block.x) + letter + rangeR(block.q, block.y));
            appendPrefixed(lines, "< ", deleted(block));
            if (letter == 'c') lines.push_back("---");
            appendPrefixed(lines, "> ", inserted(block));
        }
        return lines;
    }

    Lines ed() const {
        Lines lines;
        for (auto block = blocks.rbegin(); block != blocks.rend(); ++block) {
            const char letter = block->letter();
            lines.push_back(rangeR(block->p, block->x) + letter);
            if (letter != 'd') {
                append(lines, inserted(*block));
                lines.push_back(".");
            }
        }
        return lines;
    }

    Lines rcs() const {
        Lines lines;
        for (const ChangeBlock& block : blocks) {
            if (block.x >= 1) lines.push_back(concat('d', block.p + 1, ' ', block.x));
            if (block.y >= 1) {
                lines.push_back(concat('a', block.p + block.x, ' ', block.y));
                append(lines, inserted(block));
            }
        }
        return lines;
    }

    Lines ifdef(const std::string& macro) const {
        Lines lines;
        for (const Step& step : walk(blocks, 0, 0, length(oldLines))) {
            if (step.block == nullptr) {
                lines.push_back(oldLines[step.oldIndex]);
                continue;
            }
            const ChangeBlock& block = *step.block;
            if (block.x >= 1 && block.y >= 1) {
                lines.push_back("#ifndef " + macro);
                append(lines, deleted(block));
                lines.push_back("#else /* " + macro + " */");
                append(lines, inserted(block));
                lines.push_back("#endif /* " + macro + " */");
            } else if (block.y == 0) {
                lines.push_back("#ifndef " + macro);
                append(lines, deleted(block));
                lines.push_back("#endif /* ! " + macro + " */");
            } else {
                lines.push_back("#ifdef " + macro);
                append(lines, inserted(block));
                lines.push_back("#endif /* " + macro + " */");
            }
        }
        return lines;
    }

    Lines unified(int context, const std::string& oldName, const std::string& newName) const {
        Lines lines = {"--- " + oldName, "+++ " + newName};
        for (const Hunk& hunk : hunks(context)) {
            const std::string oldRange = rangeU(hunk.oldStart, hunk.oldCount);
            const std::string newRange = rangeU(hunk.newStart, hunk.newCount);
            lines.push_back("@@ -" + oldRange + " +" + newRange + " @@");
            for (const Step& step : hunk.steps()) {
                if (step.block == nullptr) {
                    lines.push_back(" " + oldLines[step.oldIndex]);
                } else {
                    appendPrefixed(lines, "-", deleted(*step.block));
                    appendPrefixed(lines, "+", inserted(*step.block));
                }
            }
        }
        return lines;
    }

    Lines context(int context, const std::string& oldName, const std::string& newName) const {
        Lines lines = {"*** " + oldName, "--- " + newName};
        for (const Hunk& hunk : hunks(context)) {
            lines.push_back(std::string(15, '*'));
            lines.push_back("*** " + rangeR(hunk.oldStart, hunk.oldCount) + " ****");
            const bool anyDeleted =
                std::any_of(hunk.blocks.begin(), hunk.blocks.end(),
                            [](const ChangeBlock& block) { return block.x >= 1; });
            if (anyDeleted) {
                for (const Step& step : hunk.steps()) {
                    if (step.block == nullptr) {
                        lines.push_back("  " + oldLines[step.oldIndex]);
                    } else {
                        appendPrefixed(lines, step.block->y >= 1 ? "! " : "- ",
                                       deleted(*step.block));
                    }
                }
            }
            lines.push_back("--- " + rangeR(hunk.newStart, hunk.newCount) + " ----");
            const bool anyInserted =
                std::any_of(hunk.blocks.begin(), hunk.blocks.end(),
                            [](const ChangeBlock& block) { return block.y >= 1; });
            if (anyInserted) {
                for (const Step& step : hunk.steps()) {
                    if (step.block == nullptr) {
                        lines.push_back("  " + newLines[step.newIndex]);
                    } else {
                        appendPrefixed(lines, step.block->x >= 1 ? "! " : "+ ",
                                       inserted(*step.block));
                    }
                }
            }
        }
        return lines;
    }

    Lines sideBySide(int width) const {
        Lines lines;
        for (const Step& step : walk(blocks, 0, 0, length(oldLines))) {
            if (step.block == nullptr) {
                lines.push_back(
                    sideRow(oldLines[step.oldIndex], ' ', newLines[step.newIndex], width));
                continue;
            }
            const ChangeBlock& block = *step.block;
            for (int row = 0; row < std::max(block.x, block.y); ++row) {
                if (row < block.x && row < block.y) {
                    lines.push_back(
                        sideRow(oldLines[block.p + row], '|', newLines[block.q + row], width));
                } else if (row < block.x) {
                    lines.push_back(sideRow(oldLines[block.p + row], '<', "", width));
                } else {
                    lines.push_back(sideRow("", '>', newLines[block.q + row], width));
                }
            }
        }
        return lines;
    }
};

struct TokenTotals {
    int deleted = 0;
    int inserted = 0;
    int common = 0;
};

Lines splitTokens(const std::string& line, bool byWord) {
    Lines tokens;
    if (byWord) {
        std::istringstream stream(line);
        std::string word;
        while (stream >> word) {
            tokens.push_back(word);
        }
    } else {
        for (char ch : line) {
            tokens.emplace_back(1, ch);
        }
    }
    return tokens;
}

std::string deletion(const Lines& tokens, const std::string& separator) {
    return "[-" + join(tokens, separator) + "-]";
}

std::string insertion(const Lines& tokens, const std::string& separator) {
    return "{+" + join(tokens, separator) + "+}";
}

std::string compareTokens(const Lines& oldTokens, const Lines& newTokens,
                          const std::string& separator, TokenTotals& totals) {
    const std::vector<ChangeBlock> blocks = changeBlocks(oldTokens, newTokens);
    Lines parts;
    for (const Step& step : walk(blocks, 0, 0, length(oldTokens))) {
        if (step.block == nullptr) {
            parts.push_back(oldTokens[step.oldIndex]);
            ++totals.common;
            continue;
        }
        const ChangeBlock& block = *step.block;
        if (block.x >= 1)
            parts.push_back(deletion(slice(oldTokens, block.p, block.p + block.x), separator));
        if (block.y >= 1)
            parts.push_back(insertion(slice(newTokens, block.q, block.q + block.y), separator));
        totals.deleted += block.x;
        totals.inserted += block.y;
    }
    return join(parts, separator);
}

struct BodyLine {
    char kind;
    std::string text;
};

struct PatchHunk {
    int lineNumber;
    int oldStart;
    int oldCount;
    int newStart;
    int newCount;
    std::vector<BodyLine> body;

    std::pair<Lines, Lines> sequences(bool reverse) const {
        const char oldKind = reverse ? '+' : '-';
        const char newKind = reverse ? '-' : '+';
        Lines oldLines;
        Lines newLines;
        for (const BodyLine& line : body) {
            if (line.kind == ' ' || line.kind == oldKind) oldLines.push_back(line.text);
            if (line.kind == ' ' || line.kind == newKind) newLines.push_back(line.text);
        }
        return {oldLines, newLines};
    }

    int start(bool reverse) const { return reverse ? newStart : oldStart; }

    int leadingContext() const {
        int count = 0;
        while (count < static_cast<int>(body.size()) && body[count].kind == ' ') {
            ++count;
        }
        return count;
    }

    int trailingContext() const {
        int count = 0;
        while (count < static_cast<int>(body.size()) && body[body.size() - 1 - count].kind == ' ') {
            ++count;
        }
        return count;
    }
};

struct HunkMatch {
    int fuzz;
    int delta;
    int position;
    Lines lines;

    std::string report(int number) const {
        std::string text = concat("Hunk #", number, " succeeded at ", position + 1);
        if (fuzz >= 1) text += concat(" with fuzz ", fuzz);
        if (delta == 1 || delta == -1) {
            text += concat(" (offset ", delta, " line)");
        } else if (delta != 0) {
            text += concat(" (offset ", delta, " lines)");
        }
        return text;
    }
};

std::optional<std::pair<int, int>> parseRange(const std::string& text, char sign) {
    if (text.empty() || text[0] != sign) return std::nullopt;
    const std::string numbers = text.substr(1);
    std::smatch match;
    if (!std::regex_match(numbers, match, kNumberPair)) return std::nullopt;
    const int start = std::stoi(match[1].str());
    const int count = match[2].matched ? std::stoi(match[2].str()) : 1;
    if (start == 0 && count != 0) return std::nullopt;
    return std::make_pair(start, count);
}

PatchHunk parseHunkHeader(const std::string& line, int lineNumber) {
    const Lines parts = split(line, ' ');
    std::optional<std::pair<int, int>> oldRange;
    std::optional<std::pair<int, int>> newRange;
    if (parts.size() == 4 && parts[0] == "@@" && parts[3] == "@@") {
        oldRange = parseRange(parts[1], '-');
        newRange = parseRange(parts[2], '+');
    }
    if (!oldRange || !newRange)
        throw CommandError(concat("PATCH ERROR line ", lineNumber, ": bad hunk header"));
    return {lineNumber, oldRange->first, oldRange->second, newRange->first, newRange->second, {}};
}

std::vector<PatchHunk> parsePatch(const Lines& patchLines) {
    int index = 0;
    while (index < length(patchLines) && patchLines[index].rfind("@@", 0) != 0) {
        ++index;
    }
    if (index == length(patchLines)) throw CommandError("PATCH ERROR no hunks");
    std::vector<PatchHunk> hunks;
    while (index < length(patchLines)) {
        PatchHunk hunk = parseHunkHeader(patchLines[index], index + 1);
        ++index;
        int oldSeen = 0;
        int newSeen = 0;
        while (oldSeen < hunk.oldCount || newSeen < hunk.newCount) {
            if (index == length(patchLines)) {
                throw CommandError(
                    concat("PATCH ERROR line ", hunk.lineNumber, ": truncated hunk"));
            }
            const std::string& line = patchLines[index];
            const char kind = line[0];
            const bool inOld = kind == ' ' || kind == '-';
            const bool inNew = kind == ' ' || kind == '+';
            if (line.size() < 2 || !(inOld || inNew) || (inOld && oldSeen == hunk.oldCount) ||
                (inNew && newSeen == hunk.newCount)) {
                throw CommandError(concat("PATCH ERROR line ", index + 1, ": bad hunk line"));
            }
            hunk.body.push_back({kind, line.substr(1)});
            if (inOld) ++oldSeen;
            if (inNew) ++newSeen;
            ++index;
        }
        const bool onlyContext = std::all_of(hunk.body.begin(), hunk.body.end(),
                                             [](const BodyLine& line) { return line.kind == ' '; });
        if (onlyContext)
            throw CommandError(concat("PATCH ERROR line ", hunk.lineNumber, ": no changes"));
        hunks.push_back(std::move(hunk));
    }
    return hunks;
}

std::optional<HunkMatch> searchHunk(const PatchHunk& hunk, const Lines& lines, int adjustment,
                                    bool reverse, int maxFuzz) {
    const auto [oldLines, newLines] = hunk.sequences(reverse);
    const int start = hunk.start(reverse);
    const int expected = oldLines.empty() ? start + adjustment : start - 1 + adjustment;
    const int leading = hunk.leadingContext();
    const int trailing = hunk.trailingContext();
    for (int fuzz = 0; fuzz <= maxFuzz; ++fuzz) {
        const int head = std::min(fuzz, leading);
        const int tail = std::min(fuzz, trailing);
        const Lines oldPart = slice(oldLines, head, length(oldLines) - tail);
        const Lines newPart = slice(newLines, head, length(newLines) - tail);
        for (int delta : kOffsets) {
            const int position = expected + head + delta;
            const int end = position + length(oldPart);
            if (position < 0 || end > length(lines)) continue;
            if (std::equal(oldPart.begin(), oldPart.end(), lines.begin() + position)) {
                Lines result = slice(lines, 0, position);
                append(result, newPart);
                append(result, slice(lines, end, length(lines)));
                return HunkMatch{fuzz, delta, position, result};
            }
        }
    }
    return std::nullopt;
}

struct EditCommand {
    char instruction;
    int first;
    int last;
};

std::optional<EditCommand> parseEditCommand(const std::string& line) {
    const char instruction = line.back();
    const std::string address = line.substr(0, line.size() - 1);
    std::smatch match;
    if ((instruction != 'a' && instruction != 'c' && instruction != 'd') ||
        !std::regex_match(address, match, kNumberPair)) {
        return std::nullopt;
    }
    if (instruction == 'a' && match[2].matched) return std::nullopt;
    const int first = std::stoi(match[1].str());
    const int last = match[2].matched ? std::stoi(match[2].str()) : first;
    return EditCommand{instruction, first, last};
}

std::pair<Lines, int> runEditScript(Lines lines, const Lines& script) {
    int executed = 0;
    int index = 0;
    while (index < length(script)) {
        const int lineNumber = index + 1;
        const std::optional<EditCommand> command = parseEditCommand(script[index]);
        if (!command) throw CommandError(concat("EDIT ERROR line ", lineNumber, ": bad command"));
        const auto [instruction, first, last] = *command;
        const bool valid = instruction == 'a'
                               ? first <= length(lines)
                               : 1 <= first && first <= last && last <= length(lines);
        if (!valid) throw CommandError(concat("EDIT ERROR line ", lineNumber, ": bad range"));
        ++index;
        Lines text;
        if (instruction == 'a' || instruction == 'c') {
            int end = index;
            while (end < length(script) && script[end] != ".") {
                ++end;
            }
            if (end == length(script)) {
                throw CommandError(concat("EDIT ERROR line ", lineNumber, ": missing terminator"));
            }
            text = slice(script, index, end);
            index = end + 1;
        }
        if (instruction == 'a') {
            lines.insert(lines.begin() + first, text.begin(), text.end());
        } else {
            lines.erase(lines.begin() + first - 1, lines.begin() + last);
            lines.insert(lines.begin() + first - 1, text.begin(), text.end());
        }
        ++executed;
    }
    return {lines, executed};
}

enum class ChunkKind { Stable, A, B, Both, Conflict };

std::string kindName(ChunkKind kind) {
    switch (kind) {
        case ChunkKind::A:
            return "a";
        case ChunkKind::B:
            return "b";
        case ChunkKind::Both:
            return "both";
        case ChunkKind::Conflict:
            return "conflict";
        default:
            return "stable";
    }
}

struct Chunk {
    ChunkKind kind;
    int baseStart;
    int oursStart;
    int theirsStart;
    Lines base;
    Lines ours;
    Lines theirs;

    std::string location() const {
        return "base " + rangeM(baseStart, length(base)) + " a " + rangeM(oursStart, length(ours)) +
               " b " + rangeM(theirsStart, length(theirs));
    }
};

ChunkKind chunkKind(const Lines& base, const Lines& ours, const Lines& theirs) {
    if (ours == base) return ChunkKind::B;
    if (theirs == base) return ChunkKind::A;
    if (ours == theirs) return ChunkKind::Both;
    return ChunkKind::Conflict;
}

std::vector<int> matchTable(const Lines& first, const Lines& second) {
    std::vector<int> matches(first.size() + 2, 0);
    const std::vector<std::pair<int, int>> pairs = matchedPairs(first, second);
    for (std::size_t k = 1; k + 1 < pairs.size(); ++k) {
        matches[pairs[k].first] = pairs[k].second;
    }
    return matches;
}

std::vector<Chunk> threeWayChunks(const Lines& base, const Lines& ours, const Lines& theirs) {
    const std::vector<int> oursMatch = matchTable(base, ours);
    const std::vector<int> theirsMatch = matchTable(base, theirs);
    std::vector<Chunk> chunks;
    int x = 0;
    int y = 0;
    int z = 0;
    while (x < length(base) || y < length(ours) || z < length(theirs)) {
        if (x < length(base) && oursMatch[x + 1] == y + 1 && theirsMatch[x + 1] == z + 1) {
            chunks.push_back({ChunkKind::Stable, x, y, z, slice(base, x, x + 1),
                              slice(ours, y, y + 1), slice(theirs, z, z + 1)});
            ++x;
            ++y;
            ++z;
            continue;
        }
        int anchor = x + 1;
        while (anchor <= length(base) && (oursMatch[anchor] == 0 || theirsMatch[anchor] == 0)) {
            ++anchor;
        }
        int nextX = length(base);
        int nextY = length(ours);
        int nextZ = length(theirs);
        if (anchor <= length(base)) {
            nextX = anchor - 1;
            nextY = oursMatch[anchor] - 1;
            nextZ = theirsMatch[anchor] - 1;
        }
        Lines basePart = slice(base, x, nextX);
        Lines oursPart = slice(ours, y, nextY);
        Lines theirsPart = slice(theirs, z, nextZ);
        const ChunkKind kind = chunkKind(basePart, oursPart, theirsPart);
        chunks.push_back(
            {kind, x, y, z, std::move(basePart), std::move(oursPart), std::move(theirsPart)});
        x = nextX;
        y = nextY;
        z = nextZ;
    }
    return chunks;
}

std::string kindCounts(const std::vector<Chunk>& chunks) {
    std::map<ChunkKind, int> counts;
    for (const Chunk& chunk : chunks) {
        ++counts[chunk.kind];
    }
    return concat("a=", counts[ChunkKind::A], " b=", counts[ChunkKind::B],
                  " both=", counts[ChunkKind::Both], " conflicts=", counts[ChunkKind::Conflict]);
}

int commonPrefixLength(const Lines& first, const Lines& second) {
    int size = 0;
    while (size < length(first) && size < length(second) && first[size] == second[size]) {
        ++size;
    }
    return size;
}

int commonSuffixLength(const Lines& first, const Lines& second, int limit) {
    int size = 0;
    while (size < limit && first[first.size() - 1 - size] == second[second.size() - 1 - size]) {
        ++size;
    }
    return size;
}

Lines conflictLines(const Chunk& chunk, const std::string& mode, const std::string& baseName,
                    const std::string& oursName, const std::string& theirsName) {
    if (mode == "OURS") return chunk.ours;
    if (mode == "THEIRS") return chunk.theirs;
    Lines lines;
    if (mode == "DIFF3") {
        lines.push_back("<<<<<<< " + oursName);
        append(lines, chunk.ours);
        lines.push_back("||||||| " + baseName);
        append(lines, chunk.base);
        lines.push_back(kSeparator);
        append(lines, chunk.theirs);
        lines.push_back(">>>>>>> " + theirsName);
        return lines;
    }
    const Lines& ours = chunk.ours;
    const Lines& theirs = chunk.theirs;
    const int head = commonPrefixLength(ours, theirs);
    const int tail =
        commonSuffixLength(ours, theirs, std::min(length(ours), length(theirs)) - head);
    const Lines oursMiddle = slice(ours, head, length(ours) - tail);
    const Lines theirsMiddle = slice(theirs, head, length(theirs) - tail);
    lines = slice(ours, 0, head);
    if (mode == "UNION") {
        append(lines, oursMiddle);
        append(lines, theirsMiddle);
    } else {
        lines.push_back("<<<<<<< " + oursName);
        append(lines, oursMiddle);
        lines.push_back(kSeparator);
        append(lines, theirsMiddle);
        lines.push_back(">>>>>>> " + theirsName);
    }
    append(lines, slice(ours, length(ours) - tail, length(ours)));
    return lines;
}

enum class Marker { None, Start, Base, Separator, End };

Marker markerKind(const std::string& line) {
    static const std::map<std::string, Marker> prefixes = {
        {"<<<<<<<", Marker::Start}, {"|||||||", Marker::Base}, {">>>>>>>", Marker::End}};
    if (line == kSeparator) return Marker::Separator;
    const auto found = prefixes.find(line.substr(0, 7));
    if (found != prefixes.end() && (line.size() == 7 || line[7] == ' ')) return found->second;
    return Marker::None;
}

int nextMarker(const Lines& lines, int index) {
    ++index;
    while (index < length(lines) && markerKind(lines[index]) == Marker::None) {
        ++index;
    }
    return index;
}

struct ConflictRegion {
    int start;
    int end;
    Lines ours;
    std::optional<Lines> base;
    Lines theirs;

    Lines part(const std::string& side) const {
        if (side == "OURS") return ours;
        if (side == "THEIRS") return theirs;
        if (side == "BASE") return *base;
        Lines both = ours;
        append(both, theirs);
        return both;
    }
};

std::optional<ConflictRegion> regionAt(const Lines& lines, int start) {
    if (markerKind(lines[start]) != Marker::Start) return std::nullopt;
    int middle = nextMarker(lines, start);
    std::optional<int> baseMarker;
    if (middle < length(lines) && markerKind(lines[middle]) == Marker::Base) {
        baseMarker = middle;
        middle = nextMarker(lines, middle);
    }
    if (middle == length(lines) || markerKind(lines[middle]) != Marker::Separator)
        return std::nullopt;
    const int end = nextMarker(lines, middle);
    if (end == length(lines) || markerKind(lines[end]) != Marker::End) return std::nullopt;
    ConflictRegion region{start + 1, end + 1, {}, std::nullopt, slice(lines, middle + 1, end)};
    if (baseMarker) {
        region.ours = slice(lines, start + 1, *baseMarker);
        region.base = slice(lines, *baseMarker + 1, middle);
    } else {
        region.ours = slice(lines, start + 1, middle);
    }
    return region;
}

std::vector<ConflictRegion> conflictRegions(const Lines& lines) {
    std::vector<ConflictRegion> regions;
    int index = 0;
    while (index < length(lines)) {
        std::optional<ConflictRegion> region = regionAt(lines, index);
        if (region) {
            index = region->end;
            regions.push_back(std::move(*region));
        } else {
            ++index;
        }
    }
    return regions;
}

class Workspace {
public:
    void execute(const Lines& words, const Lines& data) {
        const std::string& command = words[0];
        const Lines arguments(words.begin() + 1, words.end());
        try {
            if (command == "FILE") {
                loadFile(arguments, data);
            } else if (command == "COPY") {
                copy(arguments);
            } else if (command == "PRINT") {
                printFile(arguments);
            } else if (command == "FILES") {
                listFiles();
            } else if (command == "DIFF") {
                diff(arguments);
            } else if (command == "WORDDIFF") {
                tokenDiff(arguments, true);
            } else if (command == "CHARDIFF") {
                tokenDiff(arguments, false);
            } else if (command == "STAT") {
                stat(arguments);
            } else if (command == "PATCH") {
                patch(arguments, data);
            } else if (command == "EDIT") {
                edit(arguments, data);
            } else if (command == "DIFF3") {
                diff3(arguments);
            } else if (command == "MERGE") {
                merge(arguments);
            } else if (command == "CONFLICTS") {
                conflicts(arguments);
            } else if (command == "RESOLVE") {
                resolve(arguments);
            } else if (command == "UNDO") {
                undo(arguments);
            }
        } catch (const CommandError& error) {
            emit(error.what());
        }
    }

private:
    std::map<std::string, Lines> files_;
    std::map<std::string, std::vector<std::optional<Lines>>> history_;

    template <typename... Parts>
    void emit(const Parts&... parts) {
        (std::cout << ... << parts) << '\n';
    }

    void emitAll(const Lines& lines) {
        for (const std::string& line : lines) {
            emit(line);
        }
    }

    void require(std::initializer_list<std::string> names) const {
        for (const std::string& name : names) {
            if (files_.count(name) == 0) throw CommandError("ERROR no such file " + name);
        }
    }

    void save(const std::string& name, const Lines& lines) {
        const auto found = files_.find(name);
        history_[name].push_back(found == files_.end() ? std::nullopt
                                                       : std::optional<Lines>(found->second));
        files_[name] = lines;
    }

    void loadFile(const Lines& arguments, const Lines& data) {
        const std::string& name = arguments[0];
        save(name, data);
        emit("FILE ", name, " lines=", data.size());
    }

    void copy(const Lines& arguments) {
        const std::string& source = arguments[0];
        const std::string& target = arguments[1];
        require({source});
        const Lines& lines = files_.at(source);
        save(target, lines);
        emit("COPY ", source, ' ', target, " lines=", lines.size());
    }

    void printFile(const Lines& arguments) {
        const std::string& name = arguments[0];
        require({name});
        const Lines& lines = files_.at(name);
        emit("PRINT ", name, " lines=", lines.size());
        for (std::size_t number = 1; number <= lines.size(); ++number) {
            std::cout << std::setw(3) << number << "| " << lines[number - 1] << '\n';
        }
    }

    void listFiles() {
        emit("FILES count=", files_.size());
        for (const auto& [name, lines] : files_) {
            emit(name, " lines=", lines.size(), " undo=", history_.at(name).size());
        }
    }

    void undo(const Lines& arguments) {
        const std::string& name = arguments[0];
        std::vector<std::optional<Lines>>& states = history_[name];
        if (states.empty()) throw CommandError("ERROR nothing to undo " + name);
        const std::optional<Lines> state = states.back();
        states.pop_back();
        if (state) {
            files_[name] = *state;
            emit("UNDO ", name, " lines=", state->size());
        } else {
            files_.erase(name);
            emit("UNDO ", name, " removed");
        }
    }

    void diff(const Lines& arguments) {
        const std::string& oldName = arguments[0];
        const std::string& newName = arguments[1];
        const std::string& form = arguments[2];
        require({oldName, newName});
        const bool hasParameter = contains(kFormatsWithArgument, form);
        const std::string parameter = hasParameter ? arguments[3] : "";
        const Lines options(arguments.begin() + (hasParameter ? 4 : 3), arguments.end());
        const LineDiff diff(files_.at(oldName), files_.at(newName), options);
        if (diff.blocks.empty()) {
            emit("Files ", oldName, " and ", newName, " are identical");
        } else if (form == "BRIEF") {
            emit("Files ", oldName, " and ", newName, " differ");
        } else if (form == "NORMAL") {
            emitAll(diff.normal());
        } else if (form == "ED") {
            emitAll(diff.ed());
        } else if (form == "RCS") {
            emitAll(diff.rcs());
        } else if (form == "IFDEF") {
            emitAll(diff.ifdef(parameter));
        } else if (form == "UNIFIED") {
            emitAll(diff.unified(std::stoi(parameter), oldName, newName));
        } else if (form == "CONTEXT") {
            emitAll(diff.context(std::stoi(parameter), oldName, newName));
        } else {
            emitAll(diff.sideBySide(std::stoi(parameter)));
        }
    }

    void tokenDiff(const Lines& arguments, bool byWord) {
        const std::string& oldName = arguments[0];
        const std::string& newName = arguments[1];
        require({oldName, newName});
        const Lines& oldLines = files_.at(oldName);
        const Lines& newLines = files_.at(newName);
        const LineDiff diff(oldLines, newLines);
        if (diff.blocks.empty()) {
            emit("Files ", oldName, " and ", newName, " are identical");
            return;
        }
        const std::string separator = byWord ? " " : "";
        TokenTotals totals;
        for (const ChangeBlock& block : diff.blocks) {
            for (int row = 0; row < std::max(block.x, block.y); ++row) {
                const int oldNumber = block.p + row + 1;
                const int newNumber = block.q + row + 1;
                if (row < block.x && row < block.y) {
                    const Lines oldTokens = splitTokens(oldLines[oldNumber - 1], byWord);
                    const Lines newTokens = splitTokens(newLines[newNumber - 1], byWord);
                    const std::string text = compareTokens(oldTokens, newTokens, separator, totals);
                    emit('a', oldNumber, " b", newNumber, ": ", text);
                } else if (row < block.x) {
                    const Lines oldTokens = splitTokens(oldLines[oldNumber - 1], byWord);
                    totals.deleted += length(oldTokens);
                    emit('a', oldNumber, ": ", deletion(oldTokens, separator));
                } else {
                    const Lines newTokens = splitTokens(newLines[newNumber - 1], byWord);
                    totals.inserted += length(newTokens);
                    emit('b', newNumber, ": ", insertion(newTokens, separator));
                }
            }
        }
        emit(byWord ? "WORDS" : "CHARS", " deleted=", totals.deleted, " inserted=", totals.inserted,
             " common=", totals.common);
    }

    void stat(const Lines& arguments) {
        const std::string& oldName = arguments[0];
        const std::string& newName = arguments[1];
        require({oldName, newName});
        const Lines& oldLines = files_.at(oldName);
        const Lines& newLines = files_.at(newName);
        const LineDiff diff(oldLines, newLines, Lines(arguments.begin() + 2, arguments.end()));
        int deleted = 0;
        int inserted = 0;
        for (const ChangeBlock& block : diff.blocks) {
            deleted += block.x;
            inserted += block.y;
        }
        const int total = deleted + inserted;
        const int unchanged = length(oldLines) - deleted;
        std::string summary = concat(oldName, " -> ", newName, " | ", total);
        if (total > 0) summary += " " + statGraph(inserted, deleted);
        emit(summary);
        const int lineTotal = length(oldLines) + length(newLines);
        const int similarity = lineTotal > 0 ? 200 * unchanged / lineTotal : 100;
        emit("changes=", diff.blocks.size(), " insertions=", inserted, " deletions=", deleted,
             " unchanged=", unchanged, " similarity=", similarity, '%');
    }

    void patch(const Lines& arguments, const Lines& data) {
        const std::string& name = arguments[0];
        require({name});
        const Lines options(arguments.begin() + 2, arguments.end());
        const bool reverse = contains(options, "REVERSE");
        const bool dryRun = contains(options, "DRYRUN");
        const auto fuzzOption = std::find(options.begin(), options.end(), "FUZZ");
        const int maxFuzz = fuzzOption == options.end() ? 0 : std::stoi(*(fuzzOption + 1));
        const std::vector<PatchHunk> hunks = parsePatch(data);
        emit(dryRun ? "checking file " : "patching file ", name);
        Lines lines = files_.at(name);
        const PatchHunk& first = hunks.front();
        if (!searchHunk(first, lines, 0, reverse, maxFuzz) &&
            searchHunk(first, lines, 0, !reverse, maxFuzz)) {
            emit("Reversed (or previously applied) patch detected! Skipping patch.");
            emit("RESULT applied=0 failed=0 ignored=", hunks.size(), " lines=", lines.size());
            return;
        }
        int adjustment = 0;
        int applied = 0;
        int failed = 0;
        for (std::size_t index = 0; index < hunks.size(); ++index) {
            const PatchHunk& hunk = hunks[index];
            const std::optional<HunkMatch> match =
                searchHunk(hunk, lines, adjustment, reverse, maxFuzz);
            if (!match) {
                ++failed;
                emit("Hunk #", index + 1, " FAILED at ", hunk.start(reverse));
                continue;
            }
            const auto [oldLines, newLines] = hunk.sequences(reverse);
            lines = match->lines;
            adjustment += match->delta + length(newLines) - length(oldLines);
            ++applied;
            emit(match->report(static_cast<int>(index) + 1));
        }
        emit("RESULT applied=", applied, " failed=", failed, " ignored=0 lines=", lines.size());
        if (!dryRun && applied >= 1) save(name, lines);
    }

    void edit(const Lines& arguments, const Lines& data) {
        const std::string& name = arguments[0];
        require({name});
        const auto [lines, executed] = runEditScript(files_.at(name), data);
        emit("EDIT ", name, " commands=", executed, " lines=", lines.size());
        save(name, lines);
    }

    std::vector<Chunk> threeWay(const std::string& baseName, const std::string& oursName,
                                const std::string& theirsName) const {
        require({baseName, oursName, theirsName});
        return threeWayChunks(files_.at(baseName), files_.at(oursName), files_.at(theirsName));
    }

    void diff3(const Lines& arguments) {
        const std::vector<Chunk> chunks = threeWay(arguments[0], arguments[1], arguments[2]);
        int changes = 0;
        for (const Chunk& chunk : chunks) {
            if (chunk.kind == ChunkKind::Stable) continue;
            ++changes;
            emit("==== ", kindName(chunk.kind), ' ', chunk.location());
            for (const std::string& line : chunk.base) {
                emit("O ", line);
            }
            if (chunk.kind != ChunkKind::B) {
                for (const std::string& line : chunk.ours) {
                    emit("A ", line);
                }
            }
            if (chunk.kind == ChunkKind::B || chunk.kind == ChunkKind::Conflict) {
                for (const std::string& line : chunk.theirs) {
                    emit("B ", line);
                }
            }
        }
        emit("DIFF3 chunks=", changes, ' ', kindCounts(chunks));
    }

    void merge(const Lines& arguments) {
        const std::string& baseName = arguments[0];
        const std::string& oursName = arguments[1];
        const std::string& theirsName = arguments[2];
        const std::string& target = arguments[3];
        const std::string mode = arguments.size() == 5 ? arguments[4] : "MARKERS";
        const std::vector<Chunk> chunks = threeWay(baseName, oursName, theirsName);
        Lines result;
        std::vector<const Chunk*> conflicts;
        for (const Chunk& chunk : chunks) {
            if (chunk.kind == ChunkKind::B) {
                append(result, chunk.theirs);
            } else if (chunk.kind == ChunkKind::Conflict) {
                append(result, conflictLines(chunk, mode, baseName, oursName, theirsName));
                conflicts.push_back(&chunk);
            } else {
                append(result, chunk.ours);
            }
        }
        emit("MERGE ", target, " lines=", result.size(), ' ', kindCounts(chunks));
        for (std::size_t index = 0; index < conflicts.size(); ++index) {
            emit("CONFLICT ", index + 1, ' ', conflicts[index]->location());
        }
        save(target, result);
    }

    void conflicts(const Lines& arguments) {
        const std::string& name = arguments[0];
        require({name});
        const std::vector<ConflictRegion> regions = conflictRegions(files_.at(name));
        emit("CONFLICTS ", name, " count=", regions.size());
        for (std::size_t index = 0; index < regions.size(); ++index) {
            const ConflictRegion& region = regions[index];
            const std::string base = region.base ? std::to_string(region.base->size()) : "none";
            emit(index + 1, ": lines ", region.start, '-', region.end, " ours=", region.ours.size(),
                 " base=", base, " theirs=", region.theirs.size());
        }
    }

    void resolve(const Lines& arguments) {
        const std::string& name = arguments[0];
        const std::string& side = arguments[2];
        require({name});
        const int number = std::stoi(arguments[1]);
        const Lines& lines = files_.at(name);
        const std::vector<ConflictRegion> regions = conflictRegions(lines);
        if (static_cast<int>(regions.size()) < number) {
            throw CommandError(concat("ERROR no conflict ", number, " in ", name));
        }
        const ConflictRegion& region = regions[number - 1];
        if (side == "BASE" && !region.base) {
            throw CommandError(concat("ERROR no base section in conflict ", number));
        }
        Lines content = slice(lines, 0, region.start - 1);
        append(content, region.part(side));
        append(content, slice(lines, region.end, length(lines)));
        const std::size_t remaining = conflictRegions(content).size();
        emit("RESOLVE ", name, ' ', number, ' ', side, " lines=", content.size(),
             " remaining=", remaining);
        save(name, content);
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    Lines input;
    std::string line;
    while (std::getline(std::cin, line)) {
        input.push_back(line);
    }
    Workspace workspace;
    std::size_t position = 1;
    const int commandCount = std::stoi(input[0]);
    for (int command = 0; command < commandCount; ++command) {
        const Lines words = split(input[position++], ' ');
        Lines data;
        if (contains(kDataCommands, words[0])) {
            const int count = std::stoi(words[2]);
            data.assign(input.begin() + position, input.begin() + position + count);
            position += count;
        }
        workspace.execute(words, data);
    }
    return 0;
}
