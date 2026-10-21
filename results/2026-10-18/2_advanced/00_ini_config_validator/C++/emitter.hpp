#pragma once

#include <map>
#include <string>
#include <utility>
#include <vector>

#include "ini_parser.hpp"
#include "schema.hpp"

inline const std::string MASK = "********";

struct Value {
    long long number = 0;
    bool flag = false;
    std::string text;
    std::vector<Value> items;
};

struct Definition {
    std::string value;
    Origin origin;
    int number = 0;
    std::vector<Origin> history;
};

struct OutputKey {
    Definition definition;
    const Spec* spec;
    Value value;
    std::string kind;
    bool secret = false;
    std::string notation;

    OutputKey(Definition definition, const Spec* spec, Value value);
};

struct TreeLine {
    int depth;
    std::string text;
};

struct ProfileResult {
    std::string name;
    std::map<std::string, OutputKey> outputs;
    std::vector<TreeLine> tree;
    std::vector<Diagnostic> diagnostics;
    int errors = 0;
    int warnings = 0;
    std::vector<std::pair<std::string, std::vector<Origin>>> overridden;
    int document_keys = 0;
    int manifest_keys = 0;
    int default_keys = 0;
    int dropped = 0;
};

struct DiffEntry {
    char sign;
    std::string key;
    const OutputKey* before;
    const OutputKey* after;
};

struct ProfileDiff {
    std::string first;
    std::string second;
    std::vector<DiffEntry> entries;
    int added = 0;
    int removed = 0;
    int changed = 0;
};

std::string string_notation(const std::string& text);
std::string value_notation(const std::string& kind, const std::string& item_kind,
                           const Value& value);
std::string shown(const OutputKey& output);
std::string origin_text(const Origin& origin);
void write_outputs(const std::string& directory, const std::vector<ProfileResult>& profiles,
                   const std::vector<ProfileDiff>& diffs);
