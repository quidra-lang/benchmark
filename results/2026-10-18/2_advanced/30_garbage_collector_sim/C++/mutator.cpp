#include "collector.hpp"
static std::vector<std::string> split(const std::string &line) {
    std::vector<std::string> result;
    std::size_t first = 0;
    while (true) {
        const std::size_t end = line.find(' ', first);
        result.push_back(line.substr(first, end == std::string::npos ? end : end - first));
        if (end == std::string::npos)
            break;
        first = end + 1;
    }
    return result;
}
Config read_config() {
    Config config;
    std::ifstream file("input/config.txt");
    std::string line;
    while (std::getline(file, line)) {
        const std::vector<std::string> fields = split(line);
        if (fields[0] == "HEAP")
            config.heap = std::stoi(fields[1]);
        else if (fields[0] == "COLLECTOR") {
            Collector collector{fields[1], fields[2]};
            if (collector.type == "GENERATIONAL") {
                collector.young = std::stoi(fields[3]);
                collector.promotion_age = std::stoi(fields[4]);
            }
            config.collectors.push_back(collector);
        } else if (fields[0] == "MAPS")
            config.maps.assign(fields.begin() + 1, fields.end());
        else if (fields[0] == "MMU")
            for (std::size_t i = 1; i < fields.size(); ++i)
                config.windows.push_back(std::stoi(fields[i]));
        else
            config.width = std::stoi(fields[1]);
    }
    return config;
}
static bool number_token(const std::string &token) {
    if (token.empty() || token.size() > 4 || (token.size() > 1 && token[0] == '0'))
        return false;
    return std::all_of(token.begin(), token.end(), [](char c) { return c >= '0' && c <= '9'; });
}
static bool label_token(const std::string &token) {
    if (token.empty() || token.size() > 16)
        return false;
    return std::all_of(token.begin(), token.end(),
                       [](char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'; });
}
std::vector<Command> read_commands() {
    std::ifstream file("input/mutator.txt");
    std::string line;
    std::vector<Command> commands;
    int line_number = 0;
    const std::map<std::string, std::string> forms = {{"ALLOC", "nn"},    {"PUSH", "r"},  {"LOAD", "nn"},
                                                      {"POP", "n"},       {"SET", "nnr"}, {"OVERWRITE", "nr"},
                                                      {"CHECKPOINT", "l"}};
    while (std::getline(file, line)) {
        Command command{++line_number};
        const std::vector<std::string> fields = split(line);
        command.kind = fields[0];
        const auto form = forms.find(command.kind);
        bool valid = form != forms.end() && fields.size() == form->second.size() + 1;
        if (valid)
            for (std::size_t i = 0; i < form->second.size(); ++i) {
                const char type = form->second[i];
                const std::string &token = fields[i + 1];
                const bool matches = type == 'l'   ? label_token(token)
                                     : type == 'r' ? (token == "-" || number_token(token))
                                                   : number_token(token);
                if (!matches) {
                    valid = false;
                    break;
                }
                if (type == 'l')
                    command.label = token;
                else
                    command.args.push_back(token == "-" ? -1 : std::stoi(token));
            }
        if (!valid)
            command.error = "syntax";
        else if ((command.kind == "ALLOC" && (command.args[0] > 6 || command.args[1] > 24)) ||
                 (command.kind == "POP" && command.args[0] == 0))
            command.error = "range";
        commands.push_back(std::move(command));
    }
    return commands;
}
