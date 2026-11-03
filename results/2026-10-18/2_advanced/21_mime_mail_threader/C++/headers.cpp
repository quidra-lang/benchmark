#include "mail.hpp"

bool whitespace(char character) { return character == ' ' || character == '\t'; }
std::string lower(std::string value) { for (char& character : value) if (character >= 'A' && character <= 'Z') character += 'a' - 'A'; return value; }
std::string stripTrailing(std::string value) { while (!value.empty() && whitespace(value.back())) value.pop_back(); return value; }
std::string strip(std::string value) { value = stripTrailing(value); std::size_t start = 0; while (start < value.size() && whitespace(value[start])) ++start; return value.substr(start); }
Lines split(const std::string& value, char separator) { Lines result; std::size_t start = 0; for (std::size_t i = 0; i < value.size(); ++i) if (value[i] == separator) { result.push_back(value.substr(start, i - start)); start = i + 1; } result.push_back(value.substr(start)); return result; }
Lines words(const std::string& value) { Lines result; std::size_t start = 0; while (start < value.size()) { while (start < value.size() && whitespace(value[start])) ++start; if (start == value.size()) break; std::size_t end = start; while (end < value.size() && !whitespace(value[end])) ++end; result.push_back(value.substr(start, end - start)); start = end; } return result; }
std::string join(const Lines& lines, const std::string& separator) { std::string result; for (std::size_t i = 0; i < lines.size(); ++i) { if (i) result += separator; result += lines[i]; } return result; }
std::string collapse(const std::string& value) { return join(words(value), " "); }
std::optional<std::string> Header::value(const std::string& name) const { std::string key = lower(name); for (const std::pair<std::string, std::string>& field : fields) if (field.first == key) return field.second; return std::nullopt; }
int Header::count(const std::string& name) const { std::string key = lower(name); int result = 0; for (const std::pair<std::string, std::string>& field : fields) result += field.first == key; return result; }
Header parseFields(const SourceLines& lines) {
    Header header; bool inField = false;
    for (const SourceLine& line : lines) {
        if (!line.text.empty() && whitespace(line.text[0])) { if (inField) header.fields.back().second += line.text; else header.invalid.push_back(line.number); continue; }
        std::size_t colon = line.text.find(':');
        inField = colon != std::string::npos && colon > 0;
        if (inField) for (std::size_t i = 0; i < colon; ++i) if (line.text[i] < 33 || line.text[i] > 126) inField = false;
        if (inField) header.fields.push_back({lower(line.text.substr(0, colon)), line.text.substr(colon + 1)}); else header.invalid.push_back(line.number);
    }
    for (std::pair<std::string, std::string>& field : header.fields) field.second = strip(field.second);
    return header;
}
std::optional<std::string> removeComments(const std::string& value) {
    std::string result; int depth = 0;
    for (std::size_t i = 0; i < value.size(); ++i) {
        char character = value[i];
        if (!depth) { if (character == '(') { depth = 1; result += ' '; } else result += character; }
        else if (character == '\\') ++i;
        else if (character == '(') ++depth;
        else if (character == ')') --depth;
    }
    if (depth) return std::nullopt;
    return result;
}
std::optional<Tokens> tokenize(const std::string& value, bool mime) {
    const std::string specials = mime ? "/;=" : "<>:;@,.";
    const std::string addressWords = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-/=?^_`{|}~";
    const std::string excluded = "()<>@,;:\\\"/[]?=";
    Tokens tokens; std::size_t position = 0; bool spaced = false;
    while (position < value.size()) {
        char character = value[position];
        if (whitespace(character)) { spaced = true; ++position; continue; }
        if (character == '(') {
            int depth = 1; ++position;
            while (position < value.size() && depth) { char current = value[position++]; if (current == '\\') { if (position < value.size()) ++position; } else if (current == '(') ++depth; else if (current == ')') --depth; }
            if (depth) return std::nullopt;
            spaced = true; continue;
        }
        if (character == '"') {
            std::string quoted; bool closed = false; ++position;
            while (position < value.size()) { char current = value[position++]; if (current == '"') { closed = true; break; } if (current == '\\') { if (position == value.size()) return std::nullopt; current = value[position++]; } quoted += current; }
            if (!closed) return std::nullopt;
            tokens.push_back({"quoted", quoted, spaced});
        } else if (specials.find(character) != std::string::npos) { tokens.push_back({std::string(1, character), std::string(1, character), spaced}); ++position; }
        else {
            std::size_t end = position;
            while (end < value.size()) { char current = value[end]; bool word = mime ? current >= 33 && current <= 126 && excluded.find(current) == std::string::npos : addressWords.find(current) != std::string::npos; if (!word) break; ++end; }
            if (end == position) return std::nullopt;
            tokens.push_back({"word", value.substr(position, end - position), spaced}); position = end;
        }
        spaced = false;
    }
    return tokens;
}
DecodedWord decodeWord(const std::string& value) {
    if (value.size() < 4 || value.substr(0, 2) != "=?" || value.substr(value.size() - 2) != "?=") return {value, false, false};
    Lines pieces = split(value.substr(2, value.size() - 4), '?');
    if (pieces.size() != 3 || pieces[0].empty() || pieces[1].empty() || pieces[2].empty()) return {value, false, false};
    if (lower(pieces[0]) != "us-ascii") return {value, false, true};
    std::optional<std::string> decoded;
    if (pieces[1] == "B" || pieces[1] == "b") decoded = strictBase64(pieces[2]);
    else if (pieces[1] == "Q" || pieces[1] == "q") {
        std::string result; const std::string& encoded = pieces[2]; bool valid = true;
        for (std::size_t i = 0; i < encoded.size(); ++i) {
            if (encoded[i] == '_') result += ' ';
            else if (encoded[i] == '=') { if (i + 2 >= encoded.size() || hexValue(encoded[i + 1]) < 0 || hexValue(encoded[i + 2]) < 0) { valid = false; break; } result += static_cast<char>(16 * hexValue(encoded[i + 1]) + hexValue(encoded[i + 2])); i += 2; }
            else result += encoded[i];
        }
        if (valid) decoded = result;
    }
    if (!decoded) return {value, false, true};
    for (unsigned char character : *decoded) if (character < 32 || character > 126) return {value, false, true};
    return {*decoded, true, false};
}
std::pair<std::string, bool> decodeUnstructured(const std::string& value) {
    std::string result; bool previous = false, first = true, error = false;
    for (const std::string& word : words(value)) { DecodedWord decoded = decodeWord(word); if (!first && !(previous && decoded.decoded)) result += ' '; result += decoded.text; first = false; previous = decoded.decoded; error = error || decoded.error; }
    return {collapse(result), error};
}
std::optional<Parameters> parseParameters(const std::string& value, bool subtype) {
    std::optional<Tokens> parsed = tokenize(value, true);
    if (!parsed || parsed->empty() || (*parsed)[0].kind != "word") return std::nullopt;
    const Tokens& tokens = *parsed; Parameters result; result.type = lower(tokens[0].text); std::size_t position = 1;
    if (subtype) { if (tokens.size() < 3 || tokens[1].kind != "/" || tokens[2].kind != "word") return std::nullopt; result.subtype = lower(tokens[2].text); position = 3; }
    while (position < tokens.size()) {
        if (position + 3 >= tokens.size() || tokens[position].kind != ";" || tokens[position + 1].kind != "word" || tokens[position + 2].kind != "=" || (tokens[position + 3].kind != "word" && tokens[position + 3].kind != "quoted")) return std::nullopt;
        result.values.emplace(lower(tokens[position + 1].text), tokens[position + 3].text); position += 4;
    }
    return result;
}
