#include <iostream>
#include <string>
#include <vector>
#include <array>
#include <map>

std::vector<std::string> tokenize(const std::string &line) {
    std::vector<std::string> tokens;
    for (std::size_t i = 0; i < line.size();) {
        if (line[i] == ' ') {
            ++i;
            continue;
        }
        std::size_t start = i;
        if (line[i] >= '0' && line[i] <= '9')
            while (i < line.size() && line[i] >= '0' && line[i] <= '9')
                ++i;
        else if (line[i] >= 'a' && line[i] <= 'z')
            while (i < line.size() && line[i] >= 'a' && line[i] <= 'z')
                ++i;
        else
            ++i;
        tokens.push_back(line.substr(start, i - start));
    }
    return tokens;
}
struct Parser {
    std::vector<std::string> tokens;
    std::size_t position = 0;
    const std::map<std::string, long long> &variables;
    std::string error;
    long long unary() {
        std::string token = tokens[position++];
        if (token == "-")
            return -unary();
        if (token == "(") {
            long long value = sum();
            if (error.empty())
                ++position;
            return value;
        }
        if (token[0] >= '0' && token[0] <= '9')
            return std::stoll(token);
        std::map<std::string, long long>::const_iterator found = variables.find(token);
        if (found != variables.end())
            return found->second;
        error = "undefined variable " + token;
        return 0;
    }
    long long product() {
        long long value = unary();
        while (error.empty() && position < tokens.size() && (tokens[position] == "*" || tokens[position] == "/")) {
            std::string operation = tokens[position++];
            long long right = unary();
            if (!error.empty())
                return 0;
            if (operation == "/" && right == 0) {
                error = "division by zero";
                return 0;
            }
            value = operation == "*" ? value * right : value / right;
        }
        return value;
    }
    long long sum() {
        long long value = product();
        while (error.empty() && position < tokens.size() && (tokens[position] == "+" || tokens[position] == "-")) {
            std::string operation = tokens[position++];
            long long right = product();
            if (!error.empty())
                return 0;
            value = operation == "+" ? value + right : value - right;
        }
        return value;
    }
};
int main() {
    std::map<std::string, long long> variables;
    for (const std::string &line : std::array<std::string, 9>{"width = 12", "height = width - 5", "area = width * height",
        "(area + 6) / 4", "shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus", "volume = area * depth",
        "width = (width+3)*-(2-4)", "width * shift - height"}) {
        Parser parser{tokenize(line), 0, variables, {}};
        bool assignment = parser.tokens.size() > 1 && parser.tokens[1] == "=";
        if (assignment)
            parser.position = 2;
        long long value = parser.sum();
        if (!parser.error.empty())
            std::cout << "error: " << parser.error << '\n';
        else if (assignment) {
            variables[parser.tokens[0]] = value;
            std::cout << parser.tokens[0] << " = " << value << '\n';
        } else
            std::cout << value << '\n';
    }
}
