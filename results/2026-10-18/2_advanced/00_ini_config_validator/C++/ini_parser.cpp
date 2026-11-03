#include "ini_parser.hpp"

#include <map>
#include <optional>
#include <regex>
#include <sstream>

#include "lexer.hpp"

namespace {

const std::regex NAME_PATTERN("[a-z][a-z0-9_]*");
const std::regex SECTION_PATTERN(R"([a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*)");

std::vector<std::string> trimmed(std::vector<std::string> segments) {
    segments.front() = trim_left(segments.front());
    segments.back() = trim_right(segments.back());
    return segments;
}

std::optional<std::string> assigned_value(const std::vector<std::string>& segments) {
    if (segments.size() == 1) {
        return segments[0];
    }
    if (segments.size() == 3 && segments[0].empty() && segments[2].empty()) {
        return segments[1];
    }
    return std::nullopt;
}

std::vector<std::string> split_words(const std::string& text) {
    std::istringstream stream(text);
    std::vector<std::string> words;
    std::string word;
    while (stream >> word) {
        words.push_back(word);
    }
    return words;
}

class DocumentParser {
public:
    explicit DocumentParser(const std::string& name) { document_.name = name; }

    const Document& document() const { return document_; }

    void interpret(const LogicalLine& line) {
        if (line.error) {
            report(line.number, line.error->code, line.error->message);
            return;
        }
        std::vector<std::string> segments = trimmed(line.segments);
        const std::string& first = segments.front();
        if (segments.size() == 1 && first.empty()) {
            return;
        }
        if (!first.empty() && first.front() == '[') {
            header(line.number, segments);
        } else if (!first.empty() && first.front() == '@') {
            directive(line.number, segments);
        } else {
            assignment(line.number, segments);
        }
    }

private:
    Document document_;
    std::optional<std::string> section_;
    std::optional<std::string> base_;
    std::map<std::string, int> assigned_;

    void report(int line, const std::string& code, const std::string& message) {
        document_.diagnostics.push_back({document_.name, line, code, message});
    }

    void add(StatementKind kind, int line, const std::string& target,
             const std::string& value = "") {
        document_.statements.push_back({kind, line, target, value});
    }

    void fail_header(int number, const std::string& message) {
        report(number, "E_SECTION", message);
        section_.reset();
    }

    void header(int number, const std::vector<std::string>& segments) {
        const std::string& text = segments[0];
        if (segments.size() != 1 || text.back() != ']') {
            fail_header(number, "invalid section header");
            return;
        }
        std::string inner = text.substr(1, text.size() - 2);
        size_t colon = inner.find(':');
        bool has_parent = colon != std::string::npos;
        std::string name = trim(inner.substr(0, colon));
        std::string parent = has_parent ? trim(inner.substr(colon + 1)) : "";
        bool relative = !name.empty() && name.front() == '.' && is_section_name(name.substr(1));
        if ((has_parent && !is_section_name(parent)) || (!relative && !is_section_name(name))) {
            fail_header(number, "invalid section header");
        } else if (relative && !base_) {
            fail_header(number, "relative section without base");
        } else {
            if (relative) {
                section_ = *base_ + name;
            } else {
                section_ = name;
                base_ = name;
            }
            if (has_parent) {
                add(StatementKind::Inherit, number, *section_, parent);
            }
        }
    }

    void directive(int number, const std::vector<std::string>& segments) {
        std::vector<std::string> words = split_words(segments[0]);
        if (segments.size() > 1 || words.size() != 2 ||
            (words[0] != "@include" && words[0] != "@unset") || !is_name(words[1])) {
            report(number, "E_SYNTAX", "invalid directive");
        } else if (words[0] == "@include") {
            add(StatementKind::Include, number, words[1]);
        } else if (!section_) {
            report(number, "E_NO_SECTION", "no current section");
        } else {
            add(StatementKind::Unset, number, *section_ + "." + words[1]);
        }
    }

    void assignment(int number, const std::vector<std::string>& segments) {
        bool has_equals = false;
        for (size_t i = 0; i < segments.size(); i += 2) {
            if (segments[i].find('=') != std::string::npos) {
                has_equals = true;
            }
        }
        if (!has_equals) {
            report(number, "E_SYNTAX", "invalid line");
            return;
        }
        size_t equals = segments[0].find('=');
        if (equals == std::string::npos) {
            report(number, "E_SYNTAX", "invalid key");
            return;
        }
        std::string key = trim(segments[0].substr(0, equals));
        bool append = !key.empty() && key.back() == '+';
        if (append) {
            key = trim_right(key.substr(0, key.size() - 1));
        }
        if (!is_name(key)) {
            report(number, "E_SYNTAX", "invalid key");
            return;
        }
        std::vector<std::string> rest = segments;
        rest[0] = segments[0].substr(equals + 1);
        std::optional<std::string> value = assigned_value(trimmed(rest));
        if (!value) {
            report(number, "E_SYNTAX", "invalid value");
            return;
        }
        if (!section_) {
            report(number, "E_NO_SECTION", "no current section");
            return;
        }
        std::string full_key = *section_ + "." + key;
        if (!append) {
            auto previous = assigned_.find(full_key);
            if (previous != assigned_.end()) {
                report(number, "W_DUPLICATE",
                       full_key + " already set at line " + std::to_string(previous->second));
            }
            assigned_[full_key] = number;
        }
        add(append ? StatementKind::Append : StatementKind::Assign, number, full_key, *value);
    }
};

}  // namespace

bool is_name(const std::string& text) {
    return std::regex_match(text, NAME_PATTERN);
}

bool is_section_name(const std::string& text) {
    return std::regex_match(text, SECTION_PATTERN);
}

Document parse_document(const std::string& name, const std::vector<std::string>& physical_lines) {
    DocumentParser parser(name);
    for (const LogicalLine& line : logical_lines(physical_lines)) {
        parser.interpret(line);
    }
    return parser.document();
}
