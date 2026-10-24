#include "emitter.hpp"

#include <filesystem>
#include <fstream>

#include "lexer.hpp"

namespace {

using Block = std::vector<std::string>;

const std::map<char, std::string> ESCAPED = {
    {'\\', "\\\\"}, {'"', "\\\""}, {'\n', "\\n"}, {'\t', "\\t"}};

Block normalized_block(const ProfileResult& profile) {
    Block lines{"profile " + profile.name};
    std::map<std::string, std::map<std::string, const OutputKey*>> sections;
    for (const auto& [key, output] : profile.outputs) {
        size_t dot = key.rfind('.');
        sections[key.substr(0, dot)][key.substr(dot + 1)] = &output;
    }
    for (const auto& [section, keys] : sections) {
        lines.push_back("[" + section + "]");
        for (const auto& [name, output] : keys) {
            lines.push_back(name + " = " + shown(*output));
        }
    }
    return lines;
}

Block diagnostics_block(const ProfileResult& profile) {
    Block lines{"profile " + profile.name + " errors " + std::to_string(profile.errors) +
                " warnings " + std::to_string(profile.warnings)};
    for (const Diagnostic& diagnostic : profile.diagnostics) {
        lines.push_back(diagnostic.document + ":" + std::to_string(diagnostic.line) + " " +
                        diagnostic.code + " " + diagnostic.message);
    }
    return lines;
}

Block diff_block(const ProfileDiff& diff) {
    Block lines{"diff " + diff.first + " -> " + diff.second + ": " + std::to_string(diff.added) +
                " added, " + std::to_string(diff.removed) + " removed, " +
                std::to_string(diff.changed) + " changed"};
    for (const DiffEntry& entry : diff.entries) {
        if (entry.sign == '+') {
            lines.push_back("+ " + entry.key + " = " + shown(*entry.after));
        } else if (entry.sign == '-') {
            lines.push_back("- " + entry.key + " = " + shown(*entry.before));
        } else {
            lines.push_back("~ " + entry.key + ": " + shown(*entry.before) + " -> " +
                            shown(*entry.after));
        }
    }
    return lines;
}

Block report_block(const ProfileResult& profile) {
    Block lines{"profile " + profile.name, "includes"};
    for (const TreeLine& line : profile.tree) {
        lines.push_back("  " + std::string(2 * line.depth, ' ') + line.text);
    }
    lines.push_back("overridden");
    for (const auto& [key, history] : profile.overridden) {
        std::vector<std::string> origins;
        for (const Origin& origin : history) {
            origins.push_back(origin_text(origin));
        }
        lines.push_back("  " + key + ": " + join(origins, " -> "));
    }
    if (profile.overridden.empty()) {
        lines.push_back("  (none)");
    }
    lines.push_back("keys " + std::to_string(profile.outputs.size()) + " documents " +
                    std::to_string(profile.document_keys) + " manifest " +
                    std::to_string(profile.manifest_keys) + " defaults " +
                    std::to_string(profile.default_keys));
    lines.push_back("dropped " + std::to_string(profile.dropped));
    lines.push_back("errors " + std::to_string(profile.errors) + " warnings " +
                    std::to_string(profile.warnings));
    return lines;
}

void write_file(const std::string& path, const std::vector<Block>& blocks) {
    std::vector<std::string> texts;
    for (const Block& block : blocks) {
        texts.push_back(join(block, "\n"));
    }
    std::ofstream file(path);
    file << join(texts, "\n\n") << "\n";
}

}  // namespace

OutputKey::OutputKey(Definition definition, const Spec* spec, Value value)
    : definition(std::move(definition)), spec(spec), value(std::move(value)) {
    if (spec == nullptr) {
        kind = "string";
        notation = string_notation(this->value.text);
    } else {
        kind = spec->kind;
        secret = spec->secret;
        notation = value_notation(spec->kind, spec->item, this->value);
    }
}

std::string string_notation(const std::string& text) {
    std::string result = "\"";
    for (char character : text) {
        auto escaped = ESCAPED.find(character);
        if (escaped != ESCAPED.end()) {
            result += escaped->second;
        } else {
            result += character;
        }
    }
    return result + "\"";
}

std::string value_notation(const std::string& kind, const std::string& item_kind,
                           const Value& value) {
    if (kind == "list") {
        std::vector<std::string> items;
        for (const Value& item : value.items) {
            items.push_back(value_notation(item_kind, "", item));
        }
        return "[" + join(items, ", ") + "]";
    }
    if (kind == "string") {
        return string_notation(value.text);
    }
    if (kind == "bool") {
        return value.flag ? "true" : "false";
    }
    if (kind == "int" || kind == "size" || kind == "duration") {
        return std::to_string(value.number);
    }
    return value.text;
}

std::string shown(const OutputKey& output) {
    return output.secret ? MASK : output.notation;
}

std::string origin_text(const Origin& origin) {
    return origin.document + ":" + std::to_string(origin.line);
}

void write_outputs(const std::string& directory, const std::vector<ProfileResult>& profiles,
                   const std::vector<ProfileDiff>& diffs) {
    std::filesystem::create_directories(directory);
    std::vector<Block> normalized;
    std::vector<Block> diagnostics;
    std::vector<Block> reports;
    for (const ProfileResult& profile : profiles) {
        normalized.push_back(normalized_block(profile));
        diagnostics.push_back(diagnostics_block(profile));
        reports.push_back(report_block(profile));
    }
    std::vector<Block> differences;
    for (const ProfileDiff& diff : diffs) {
        differences.push_back(diff_block(diff));
    }
    write_file(directory + "/normalized.txt", normalized);
    write_file(directory + "/diagnostics.txt", diagnostics);
    write_file(directory + "/diff.txt", differences);
    write_file(directory + "/report.txt", reports);
}
