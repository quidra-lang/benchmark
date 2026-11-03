#include "lexer.hpp"

#include <fstream>
#include <map>

namespace {

const std::map<char, char> ESCAPES = {
    {'\\', '\\'}, {'"', '"'}, {'n', '\n'}, {'t', '\t'}, {'$', LITERAL_DOLLAR}};

}  // namespace

void LogicalLine::fail(const std::string& code, const std::string& message) {
    if (!error) {
        error = LexError{code, message};
    }
}

std::vector<std::string> read_lines(const std::string& path) {
    std::ifstream file(path);
    std::vector<std::string> lines;
    std::string line;
    while (std::getline(file, line)) {
        lines.push_back(line);
    }
    return lines;
}

std::string trim_left(const std::string& text) {
    size_t start = text.find_first_not_of(' ');
    return start == std::string::npos ? "" : text.substr(start);
}

std::string trim_right(const std::string& text) {
    size_t end = text.find_last_not_of(' ');
    return end == std::string::npos ? "" : text.substr(0, end + 1);
}

std::string trim(const std::string& text) {
    return trim_left(trim_right(text));
}

std::vector<std::string> split(const std::string& text, char separator) {
    std::vector<std::string> parts;
    size_t start = 0;
    size_t end = text.find(separator);
    while (end != std::string::npos) {
        parts.push_back(text.substr(start, end - start));
        start = end + 1;
        end = text.find(separator, start);
    }
    parts.push_back(text.substr(start));
    return parts;
}

std::string join(const std::vector<std::string>& parts, const std::string& separator) {
    std::string result;
    for (size_t i = 0; i < parts.size(); i++) {
        if (i > 0) {
            result += separator;
        }
        result += parts[i];
    }
    return result;
}

std::vector<LogicalLine> logical_lines(const std::vector<std::string>& physical_lines) {
    std::vector<LogicalLine> lines;
    size_t index = 0;
    while (index < physical_lines.size()) {
        LogicalLine line{static_cast<int>(index + 1)};
        std::string source = physical_lines[index];
        index++;
        size_t position = 0;
        bool quoted = false;
        std::string current;
        while (position < source.size()) {
            char character = source[position];
            if (character == '\\' && position == source.size() - 1) {
                source = trim_left(physical_lines[index]);
                index++;
                position = 0;
            } else if (quoted && character == '\\') {
                char follower = source[position + 1];
                auto escape = ESCAPES.find(follower);
                if (escape != ESCAPES.end()) {
                    current += escape->second;
                } else {
                    line.fail("E_ESCAPE", std::string("invalid escape sequence \\") + follower);
                }
                position += 2;
            } else if (character == '"') {
                line.segments.push_back(current);
                current.clear();
                quoted = !quoted;
                position++;
            } else if (!quoted && (character == ';' || character == '#')) {
                break;
            } else {
                current += character;
                position++;
            }
        }
        if (quoted) {
            line.fail("E_UNTERMINATED", "unterminated string");
        }
        line.segments.push_back(current);
        lines.push_back(line);
    }
    return lines;
}
