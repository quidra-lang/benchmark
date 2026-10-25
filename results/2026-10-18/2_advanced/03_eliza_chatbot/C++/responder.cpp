#include "eliza.hpp"

Words reflect(const Words& values, const Substitutions& substitutions) {
    Words result;
    for (const std::string& value : values) {
        auto found = substitutions.find(value);
        if (found == substitutions.end()) result.push_back(value);
        else result.insert(result.end(), found->second.begin(), found->second.end());
    }
    return result;
}
std::string buildReply(const std::string& text, const Clauses& bindings, const Substitutions& post) {
    std::string result;
    for (std::size_t i = 0; i < text.size();) {
        if (reference(text.substr(i, 3))) {
            int n = text[i + 1] - '0';
            if (n > 0 && n <= static_cast<int>(bindings.size())) result += join(reflect(bindings[n - 1], post));
            i += 3;
        } else result += text[i++];
    }
    result = join(words(result));
    if (!result.empty() && result[0] >= 'a' && result[0] <= 'z') result[0] = static_cast<char>(result[0] - 'a' + 'A');
    return result;
}
Words restate(const Words& arguments, const Clauses& bindings) {
    Words result;
    for (const std::string& a : arguments) {
        if (!reference(a)) result.push_back(a);
        else {
            int n = a[1] - '0';
            if (n > 0 && n <= static_cast<int>(bindings.size())) result.insert(result.end(), bindings[n - 1].begin(), bindings[n - 1].end());
        }
    }
    return result;
}
Words elizaLines(const std::string& text) {
    Words result;
    for (const std::string& value : words(text)) {
        if (result.empty()) result.push_back("ELIZA: " + value);
        else if (result.back().size() + 1 + value.size() <= 72) result.back() += " " + value;
        else result.push_back(std::string(7, ' ') + value);
    }
    return result;
}
