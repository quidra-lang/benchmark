#include "prolog.hpp"
namespace prolog {
    const std::string symbols = "+-*/\\^<>=~:.?@#&$";
    const std::map<std::string, Operator> infix =[] {
        std::map<std::string, Operator> table;
        const std::vector<std::tuple<int, std::string, std::vector<std::string>>> rows = { {1200, "xfx", {":-"} }, {1100, "xfy", {";"} }, {1050, "xfy", {"->"} }, {1000, "xfy", {","} }, {700, "xfx", {"=", "\\=", "==", "\\==", "is", "=:=", "=\\=", "<", ">", "=<", ">=", "=.."} }, {500, "yfx", {"+", "-"} }, {400, "yfx", {"*", "/", "//", "mod", "rem"} } };
        for (const auto& row : rows) {
            int p = std::get < 0 >(row);
            const std::string& kind = std::get < 1 >(row);
            for (const std::string& name : std::get < 2 >(row)) table[name] = {p, kind == "yfx" ? p : p - 1, kind == "xfy" ? p : p - 1};
        }
        return table;
    }();
    const std::map<std::string, int> prefix = { {"\\+", 900}, {"-", 200} };
    static bool lower(char c) {
        return c >= 'a' && c <= 'z';
    }
    static bool upper(char c) {
        return c >= 'A' && c <= 'Z';
    }
    static bool digit(char c) {
        return c >= '0' && c <= '9';
    }
    static bool alnum(char c) {
        return lower(c) || upper(c) || digit(c) || c == '_';
    }
    SyntaxError::SyntaxError(const Token& value, const std::string& text) : token(value), message(text) {
        if (!message.empty()) return;
        if (token.kind == "invalid") message = token.value;
        else if (token.kind == "eof") message = "unexpected end of file";
        else if (token.kind == "end") message = "unexpected end of clause";
        else if (token.kind == "name" && infix.count(token.value)) message = "operator priority clash";
        else message = "unexpected \"" + token.spelling + "\"";
    }
    std::vector<Token> tokenize(const std::string& source, int column) {
        std::vector<Token> result;
        std::size_t position = 0;
        int line = 1;
        bool space = true;
        while (position < source.size()) {
            char c = source[position];
            if (c == ' ' || c == '\n') {
                if (c == '\n') {
                    ++line;
                    column = 1;
                } else ++column;
                ++position;
                space = true;
                continue;
            }
            if (c == '%') {
                while (position < source.size() && source[position] != '\n') {
                    ++position;
                    ++column;
                }
                space = true;
                continue;
            }
            std::size_t start = position;
            Token token;
            token.line = line;
            token.column = column;
            token.space = space;
            token.index = result.size();
            if (digit(c)) {
                while (position < source.size() && digit(source[position]))++position;
                std::string digits = source.substr(start, position - start);
                std::size_t significant = digits.find_first_not_of('0');
                std::string canonical = significant == std::string::npos ? "0" : digits.substr(significant);
                if (canonical.size() > 10 ||(canonical.size() == 10 && canonical > "2147483647")) {
                    token.kind = "invalid";
                    token.value = "integer too large";
                } else {
                    token.kind = "integer";
                    token.integer = std::stoll(canonical);
                }
            } else if (lower(c) || upper(c) || c == '_') {
                while (position < source.size() && alnum(source[position]))++position;
                token.kind = lower(c) ? "name" : "variable";
                token.value = source.substr(start, position - start);
            } else if (symbols.find(c) != std::string::npos) {
                while (position < source.size() && symbols.find(source[position]) != std::string::npos)++position;
                token.value = source.substr(start, position - start);
                token.kind = token.value == "." &&(position == source.size() || source[position] == ' ' || source[position] == '\n' || source[position] == '%') ? "end" : "name";
            } else if (c == '!' || c == ';') {
                ++position;
                token.kind = "name";
                token.value = std::string(1, c);
            } else if (std::string(",|()[]").find(c) != std::string::npos) {
                ++position;
                token.kind = "punct";
                token.value = std::string(1, c);
            } else if (c == '\'') {
                ++position;
                std::string represented;
                bool incorrect = false;
                while (true) {
                    if (position == source.size() || source[position] == '\n') {
                        token.kind = "invalid";
                        token.value = "unterminated quoted atom";
                        break;
                    }
                    char current = source[position];
                    if (current == '\'') {
                        if (position + 1 < source.size() && source[position + 1] == '\'') {
                            represented.push_back('\'');
                            position += 2;
                        } else {
                            ++position;
                            token.kind = incorrect ? "invalid" : "quoted";
                            token.value = incorrect ? "undefined escape sequence" : represented;
                            break;
                        }
                    } else if (current == '\\') {
                        ++position;
                        if (position < source.size() && source[position] != '\n') {
                            char escape = source[position++];
                            if (escape == 'n') represented.push_back('\n');
                            else if (escape == 't') represented.push_back('\t');
                            else if (escape == '\\' || escape == '\'') represented.push_back(escape);
                            else {
                                incorrect = true;
                                represented.push_back(escape);
                            }
                        }
                    } else {
                        represented.push_back(current);
                        ++position;
                    }
                }
            } else {
                ++position;
                token.kind = "invalid";
                token.value = "illegal character '" + std::string(1, c) + "'";
            }
            token.spelling = source.substr(start, position - start);
            result.push_back(token);
            column += static_cast<int>(position - start);
            space = false;
        }
        Token eof;
        eof.kind = "eof";
        eof.line = line;
        eof.column = column;
        eof.space = space;
        eof.index = result.size();
        result.push_back(eof);
        return result;
    }
    Token Reader::take() {
        Token token = peek();
        if (token.kind != "eof")++position;
        return token;
    }
    bool Reader::punctuation(const std::string& spelling) const {return peek().kind == "punct" && peek().value == spelling;
    } void Reader::expect(const std::string& spelling) {
        Token token = take();
        if (token.kind != "punct" || token.value != spelling) throw SyntaxError(token);
    }
    Term Reader::clause(bool query) {
        names.clear();
        counts.clear();
        name_order.clear();
        count_order.clear();
        Term result = term(1200).first;
        Token token = take();
        if (token.kind != "end") throw SyntaxError(token);
        if (query && peek().kind != "eof") throw SyntaxError(peek());
        return result;
    }
    std::pair<Term, int> Reader::term(int limit) {
        std::pair<Term, int> value = primary(limit);
        while (true) {
            const Token token = peek();
            bool op =(token.kind == "name" && infix.count(token.value)) ||(token.kind == "punct" && token.value == ",");
            if (!op) break;
            Operator operation = infix.at(token.value);
            if (operation.priority > limit || value.second > operation.left) break;
            take();
            Term right = term(operation.right).first;
            value = {compound(token.value, {value.first, right}), operation.priority};
        }
        return value;
    }
    bool Reader::can_start() const {const Token& token = peek();
    return token.kind == "integer" || token.kind == "variable" || token.kind == "quoted" ||(token.kind == "punct" &&(token.value == "(" || token.value == "[")) ||(token.kind == "name" &&(!infix.count(token.value) || prefix.count(token.value)));
    } std::pair<Term, int> Reader::primary(int limit) {
        Token token = take();
        if (token.kind == "integer") return {integer(token.integer), 0};
        if (token.kind == "variable") {
            if (!counts.count(token.value)) count_order.push_back(token.value);
            ++counts[token.value];
            if (token.value == "_") return {variable(), 0};
            if (!names.count(token.value)) {
                name_order.push_back(token.value);
                names[token.value] = variable();
            }
            return {names[token.value], 0};
        }
        if (token.kind == "punct" && token.value == "(") {
            Term result = term(1200).first;
            expect(")");
            return {result, 0};
        }
        if (token.kind == "punct" && token.value == "[") {
            if (punctuation("]")) {
                take();
                return {atom("[]"), 0};
            }
            std::vector<Term> elements = {term(999).first};
            while (punctuation(",")) {
                take();
                elements.push_back(term(999).first);
            }
            Term tail = atom("[]");
            if (punctuation("|")) {
                take();
                tail = term(999).first;
            }
            expect("]");
            return {make_list(elements, tail), 0};
        }
        if (token.kind == "name" || token.kind == "quoted") {
            if (punctuation("(") && !peek().space) {
                take();
                std::vector<Term> args = {term(999).first};
                while (punctuation(",")) {
                    take();
                    args.push_back(term(999).first);
                }
                expect(")");
                return {compound(token.value, std::move(args)), 0};
            }
            if (token.kind == "name" && token.value == "-" && peek().kind == "integer" && !peek().space) return {integer(-take().integer), 0};
            if (token.kind == "name" && prefix.count(token.value) && can_start()) {
                int priority = prefix.at(token.value);
                if (priority > limit) throw SyntaxError(token, "operator priority clash");
                Term arg = term(priority).first;
                return {compound(token.value, {arg}), priority};
            }
            return {atom(token.value), 0};
        }
        throw SyntaxError(token);
    }
}
