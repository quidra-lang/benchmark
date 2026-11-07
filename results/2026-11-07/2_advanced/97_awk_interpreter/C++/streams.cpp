#include "awk.hpp"
namespace awk {
    std::string read_file(const std::string& path) {
        std::ifstream input(path);
        return std::string(std::istreambuf_iterator < char >(input), std::istreambuf_iterator < char >());
    }
    static bool valid_name(const std::string& name) {
        if (name.empty() || !letter(name[0])) return false;
        for (char c : name) if (!letter(c) && !digit(c)) return false;
        return true;
    }
    bool valid_filename(const std::string& name) {
        if (name.empty() || name[0] == '.') return false;
        for (char c : name) if (!letter(c) && !digit(c) && c != '.' && c != '-') return false;
        return true;
    }
    Arguments parse_arguments(const std::string& text) {
        Arguments args;
        std::istringstream input(text);
        std::string line;
        while (std::getline(input, line)) {
            if (line.compare(0, 3, "-F ") == 0) args.options.emplace_back("FS", line.substr(3));
            else if (line.compare(0, 3, "-v ") == 0) {
                std::size_t at = line.find('=', 3);
                args.options.emplace_back(line.substr(3, at - 3), line.substr(at + 1));
            } else {
                std::size_t at = line.find('=');
                if (at != std::string::npos && valid_name(line.substr(0, at))) args.operands.push_back({false, line.substr(0, at), line.substr(at + 1), 0});
                else args.operands.push_back({true, line, "", 0});
            }
        }
        return args;
    }
    std::vector<std::string> read_records(const std::string& name) {
        std::ifstream input("input/" + name);
        std::vector<std::string> result;
        std::string line;
        while (std::getline(input, line)) result.push_back(line);
        return result;
    }
    void Streams::write(const std::string& text, const std::optional<std::string>& name, const std::string& mode, Position position) {
        if (!name) {
            standard.content += text;
            ++standard.writes;
            return;
        }
        if (!valid_filename(*name) || *name == "stdout.txt" || *name == "stats.txt") throw Issue {position, "invalid output file name", 2};
        if (!outputs.count(*name)) output_order.push_back(*name);
        Output& out = outputs[*name];
        if (!out.open) {
            out.open = true;
            if (mode == ">") out.content.clear();
        }
        out.content += text;
        ++out.writes;
    }
    std::pair<int, std::string> Streams::getline(const std::string& name) {
        if (!inputs.count(name)) input_order.push_back(name);
        GetlineInput& source = inputs[name];
        if (!source.open) {
            if (!valid_filename(name)) return {-1, ""};
            std::ifstream input("input/" + name);
            if (!input) return {-1, ""};
            source.lines = read_records(name);
            source.position = 0;
            source.open = source.ever = true;
        }
        if (source.position == source.lines.size()) return {0, ""};
        ++source.reads;
        return {1, source.lines[source.position++]};
    }
    int Streams::close(const std::string& name) {
        bool closed = false;
        std::map<std::string, Output>::iterator out = outputs.find(name);
        if (out != outputs.end() && out->second.open) {
            out->second.open = false;
            closed = true;
        }
        std::map<std::string, GetlineInput>::iterator in = inputs.find(name);
        if (in != inputs.end() && in->second.open) {
            in->second.open = false;
            closed = true;
        }
        return closed ? 0 : -1;
    }
    void Streams::save() const {std::ofstream standard_file("output/stdout.txt");
    standard_file << standard.content;
    for (const auto& entry : outputs) {
        std::ofstream out("output/" + entry.first);
        out << entry.second.content;
    }
    }
}
