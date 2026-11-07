#pragma once

#include <string>
#include <tuple>
#include <vector>

struct Origin {
    std::string document;
    int line = 0;

    bool operator==(const Origin& other) const {
        return document == other.document && line == other.line;
    }
    bool operator!=(const Origin& other) const { return !(*this == other); }
};

struct Diagnostic {
    std::string document;
    int line = 0;
    std::string code;
    std::string message;

    bool operator<(const Diagnostic& other) const {
        return std::tie(document, line, code, message) <
               std::tie(other.document, other.line, other.code, other.message);
    }
};

enum class StatementKind { Assign, Append, Unset, Inherit, Include };

struct Statement {
    StatementKind kind;
    int line;
    std::string target;
    std::string value;
};

struct Document {
    std::string name;
    std::vector<Statement> statements;
    std::vector<Diagnostic> diagnostics;
};

bool is_name(const std::string& text);
bool is_section_name(const std::string& text);
Document parse_document(const std::string& name, const std::vector<std::string>& physical_lines);
