#include "preprocessor.hpp"
std::string directive_name(const Tokens &tokens) {
    return tokens.size() >= 2 && tokens[0].spelling == "#" && tokens[1].kind == "identifier"
               ? tokens[1].spelling
               : "";
}
static std::string detect_guard(const std::vector<LogicalLine> &logical) {
    std::vector<const Tokens *> lines;
    for (const LogicalLine &line : logical)
        if (!line.tokens.empty())
            lines.push_back(&line.tokens);
    if (lines.empty())
        return "";
    const Tokens &first = *lines.front();
    const Tokens &last = *lines.back();
    if (first.size() != 3 || first[0].spelling != "#" || first[1].spelling != "ifndef" ||
        first[1].kind != "identifier" || first[2].kind != "identifier" || last.size() != 2 ||
        last[0].spelling != "#" || last[1].spelling != "endif" || last[1].kind != "identifier")
        return "";
    int depth = 0;
    for (size_t i = 0; i < lines.size(); ++i) {
        std::string name = directive_name(*lines[i]);
        if (word_in("elif elifdef elifndef else", name) && depth == 1)
            return "";
        if (word_in("if ifdef ifndef", name))
            ++depth;
        else if (name == "endif")
            --depth;
        if (depth == 0 && i + 1 < lines.size())
            return "";
    }
    return depth == 0 ? first[2].spelling : "";
}
std::string IncludeManager::search(const std::string &name, bool quoted) const {
    std::vector<std::string> paths;
    if (quoted)
        paths.push_back(name);
    paths.push_back("include/" + name);
    for (const std::string &path : paths)
        if (std::filesystem::is_regular_file("input/" + path))
            return path;
    return "";
}
FileData *IncludeManager::load(const std::string &path) {
    auto found = files.find(path);
    if (found != files.end())
        return found->second.get();
    std::ifstream input("input/" + path);
    std::string source((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    auto file = std::make_unique<FileData>();
    file->path = path;
    file->lines = lex_source(source);
    file->physical_lines = static_cast<int>(std::count(source.begin(), source.end(), '\n'));
    file->guard = detect_guard(file->lines);
    FileData *result = file.get();
    files[path] = std::move(file);
    order.push_back(path);
    return result;
}
