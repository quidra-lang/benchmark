#include "awk.hpp"
namespace awk {
    static bool whitespace(char c) {
        return c == ' ' || c == '\t' || c == '\n';
    }
    static Integer numeric_prefix(const std::string& s) {
        std::size_t i = 0;
        while (i < s.size() && whitespace(s[i]))++i;
        int sign = 1;
        if (i < s.size() &&(s[i] == '+' || s[i] == '-')) {
            if (s[i] == '-') sign = -1;
            ++i;
        }
        Integer value = 0;
        while (i < s.size() && digit(s[i])) value = value * 10 + s[i++] - '0';
        return sign * value;
    }
    Value Value::number(Integer n) {
        Value result;
        result.kind = Kind::Number;
        result.numeric = n;
        return result;
    }
    Value Value::string(const std::string& s) {
        Value result;
        result.kind = Kind::String;
        result.text = s;
        return result;
    }
    Value Value::input(const std::string& s) {
        Value result = string(s);
        std::size_t first = 0, last = s.size();
        while (first < last && whitespace(s[first]))++first;
        while (last > first && whitespace(s[last - 1]))--last;
        if (first < last &&(s[first] == '+' || s[first] == '-'))++first;
        bool numeric = first < last;
        for (std::size_t i = first;i < last;++i) if (!digit(s[i])) numeric = false;
        if (numeric) {
            result.kind = Kind::NumericString;
            result.numeric = numeric_prefix(s);
        }
        return result;
    }
    Integer Value::to_number() const {return kind == Kind::String ? numeric_prefix(text) : numeric;
    } std::string Value::to_string() const {return kind == Kind::Number ? std::to_string(numeric) : kind == Kind::Uninitialized ? "" : text;
    } bool Value::truth() const {return kind == Kind::String ? !text.empty() : numeric != 0;
    } std::string Value::describe() const {if (kind == Kind::Number) return std::to_string(numeric);
    if (kind == Kind::Uninitialized) return "(uninitialized)";
    std::ostringstream out;
    out << '"';
    for (unsigned char c : text) {
        if (c == '"') out << "\\\"";
        else if (c == '\\') out << "\\\\";
        else if (c == '\n') out << "\\n";
        else if (c == '\t') out << "\\t";
        else if (c >= 32 && c <= 126) out << c;
        else out << '\\' << std::oct << std::setw(3) << std::setfill('0') << static_cast<int>(c) << std::dec;
    }
    out << '"';
    if (kind == Kind::NumericString) out << " (strnum)";
    return out.str();
    } int compare(const Value& a, const Value& b) {
        if (a.kind != Value::Kind::String && b.kind != Value::Kind::String) {
            Integer x = a.to_number(), y = b.to_number();
            return(x > y) -(x < y);
        }
        std::string x = a.to_string(), y = b.to_string();
        return(x > y) -(x < y);
    }
    static bool integer_subscript(const std::string& s) {
        if (s == "0") return true;
        std::size_t i = !s.empty() && s[0] == '-' ? 1 : 0;
        if (i == s.size() || s[i] < '1' || s[i] > '9') return false;
        for (++i;i < s.size();++i) if (!digit(s[i])) return false;
        return true;
    }
    bool subscript_less(const std::string& a, const std::string& b) {
        bool ai = integer_subscript(a), bi = integer_subscript(b);
        if (ai != bi) return ai;
        if (ai) return std::stoll(a) < std::stoll(b);
        return a < b;
    }
    std::vector<std::string> split_pieces(const std::string& text, const std::string& separator) {
        std::vector<std::string> result;
        if (text.empty()) return result;
        if (separator.empty()) {
            for (char c : text) result.emplace_back(1, c);
            return result;
        }
        if (separator == " ") {
            std::size_t i = 0;
            while (i < text.size()) {
                while (i < text.size() && whitespace(text[i]))++i;
                std::size_t start = i;
                while (i < text.size() && !whitespace(text[i]))++i;
                if (i > start) result.push_back(text.substr(start, i - start));
            }
            return result;
        }
        std::size_t start = 0;
        while (true) {
            std::size_t next = text.find(separator, start);
            if (next == std::string::npos) {
                result.push_back(text.substr(start));
                break;
            }
            result.push_back(text.substr(start, next - start));
            start = next + separator.size();
        }
        return result;
    }
    void Record::set(const std::string& text) {
        zero = Value::input(text);
        fields.clear();
        for (const std::string& piece : split_pieces(text, special("FS").to_string())) fields.push_back(Value::input(piece));
    }
    Value Record::read(Integer index) const {return index == 0 ? zero : index <= static_cast<Integer>(fields.size()) ? fields[static_cast<std::size_t>(index - 1)] : Value {};
    } void Record::rebuild() {
        std::string text, separator = special("OFS").to_string();
        for (std::size_t i = 0;i < fields.size();++i) {
            if (i) text += separator;
            text += fields[i].to_string();
        }
        zero = Value::input(text);
    }
    void Record::write(Integer index, const Value& value) {
        if (index == 0) {
            set(value.to_string());
            return;
        }
        if (index > static_cast<Integer>(fields.size())) fields.resize(static_cast<std::size_t>(index), Value::string(""));
        fields[static_cast<std::size_t>(index - 1)] = value;
        rebuild();
    }
    void Record::resize(Integer size) {
        fields.resize(static_cast<std::size_t>(size), Value::string(""));
        rebuild();
    }
}
