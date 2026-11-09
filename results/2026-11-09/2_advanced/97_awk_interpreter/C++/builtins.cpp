#include "awk.hpp"
namespace awk {
    Value arithmetic(const std::string& op, const Value& first, const Value& second, Position position) {
        Integer a = first.to_number(), b = second.to_number(), value = 0;
        if (op == "/" || op == "%") {
            if (b == 0) throw Issue {position, "division by zero", 2};
            value = op == "/" ? a/b : a%b;
        } else if (op == "^") {
            if (b < 0) throw Issue {position, "negative exponent", 2};
            value = 1;
            while (b) {
                if (b & 1) value *= a;
                b /= 2;
                if (b) a *= a;
            }
        } else if (op == "+") value = a + b;
        else if (op == "-") value = a - b;
        else value = a * b;
        return Value::number(value);
    }
    std::string format_output(const std::vector<Value>& values, Position position) {
        std::string fmt = values[0].to_string(), result;
        std::size_t i = 0, argument = 1;
        while (i < fmt.size()) {
            if (fmt[i] != '%') {
                result.push_back(fmt[i++]);
                continue;
            }
            ++i;
            if (i < fmt.size() && fmt[i] == '%') {
                result.push_back('%');
                ++i;
                continue;
            }
            bool left = false, zero = false;
            while (i < fmt.size() &&(fmt[i] == '-' || fmt[i] == '0')) {
                left = left || fmt[i] == '-';
                zero = zero || fmt[i] == '0';
                ++i;
            }
            int width = 0;
            while (i < fmt.size() && digit(fmt[i])) width = width * 10 + fmt[i++] - '0';
            std::optional<int> precision;
            if (i < fmt.size() && fmt[i] == '.') {
                ++i;
                precision = 0;
                while (i < fmt.size() && digit(fmt[i])) * precision = *precision * 10 + fmt[i++] - '0';
            }
            if (i == fmt.size() || std::string("discxo").find(fmt[i]) == std::string::npos) throw Issue {position, "invalid format", 2};
            char conversion = fmt[i++];
            if (argument == values.size()) throw Issue {position, "not enough arguments", 2};
            const Value& value = values[argument++];
            std::string body;
            bool numeric = std::string("dixo").find(conversion) != std::string::npos;
            if (numeric) {
                Integer n = value.to_number(), m = n < 0 ? -n : n;
                int base = conversion == 'x' ? 16 : conversion == 'o' ? 8 : 10;
                std::string digits;
                do {
                    digits.push_back("0123456789abcdef"[m%base]);
                    m /= base;
                } while (m);
                std::reverse(digits.begin(), digits.end());
                if (precision) {
                    if (*precision == 0 && n == 0) digits.clear();
                    else if (digits.size() < static_cast<std::size_t>(*precision)) digits.insert(0, *precision - digits.size(), '0');
                }
                body =(n < 0 ? "-" : "") + digits;
            } else if (conversion == 's') {
                body = value.to_string();
                if (precision && body.size() > static_cast<std::size_t>(*precision)) body.resize(*precision);
            } else if (value.kind == Value::Kind::Number || value.kind == Value::Kind::NumericString) {
                Integer code = value.to_number();
                if (code != 10 &&(code < 32 || code > 126)) throw Issue {position, "invalid character code", 2};
                body.push_back(static_cast<char>(code));
            } else {
                body = value.to_string().substr(0, 1);
            }
            if (width > static_cast<int>(body.size())) {
                std::size_t missing = width - body.size();
                if (left) body.append(missing, ' ');
                else if (numeric && zero && !precision) body.insert(!body.empty() && body[0] == '-' ? 1 : 0, missing, '0');
                else body.insert(0, missing, ' ');
            }
            result += body;
        }
        return result;
    }
    Value invoke(const std::string& name, const std::vector<Value>& v, Position position) {
        if (name == "sprintf") return Value::string(format_output(v, position));
        if (name == "int") return Value::number(v[0].to_number());
        std::string s = v[0].to_string();
        if (name == "substr") {
            Integer start = v[1].to_number(), end = v.size() == 3 ? start + v[2].to_number() : static_cast<Integer>(s.size()) + 1;
            start = std::max < Integer >(1, start);
            end = std::min < Integer >(end, static_cast<Integer>(s.size()) + 1);
            return Value::string(end > start ? s.substr(static_cast<std::size_t>(start - 1), static_cast<std::size_t>(end - start)) : "");
        }
        if (name == "index") {
            std::string sought = v[1].to_string();
            std::size_t at = s.find(sought);
            return Value::number(sought.empty() || at == std::string::npos ? 0 : static_cast<Integer>(at + 1));
        }
        for (char& c : s) {
            if (name == "toupper" && c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
            else if (name == "tolower" && c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
        }
        return Value::string(s);
    }
}
