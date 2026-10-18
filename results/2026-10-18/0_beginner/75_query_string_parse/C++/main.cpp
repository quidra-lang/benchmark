#include <iostream>
#include <string>
#include <vector>
#include <array>
#include <map>
#include <sstream>

std::string decode(const std::string &s) {
    std::string out;
    for (std::size_t i = 0; i < s.size(); i++) {
        if (s[i] == '+')
            out += ' ';
        else if (s[i] == '%') {
            out += static_cast<char>(std::stoi(s.substr(i + 1, 2), nullptr, 16));
            i += 2;
        } else
            out += s[i];
    }
    return out;
}

int main() {
    std::array<std::string, 4> queries = {"name=Alice+Smith&age=30&city=New%20York", "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
        "msg=50%25+off%21&debug&lang=en&ref=&lang=ja", "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips"};
    for (int k = 0; k < 4; k++) {
        std::map<std::string, std::vector<std::string>> values;
        std::istringstream input(queries[k]);
        for (std::string item; std::getline(input, item, '&');) {
            std::size_t at = item.find('=');
            std::string key = decode(item.substr(0, at)), value = at == std::string::npos ? "" : decode(item.substr(at + 1));
            values[key].push_back(value);
        }
        std::cout << "query " << k + 1 << ":\n";
        for (const auto &[key, items] : values) {
            std::cout << "  " << key << ": ";
            for (std::size_t i = 0; i < items.size(); i++) {
                if (i)
                    std::cout << ", ";
                std::cout << '"' << items[i] << '"';
            }
            std::cout << '\n';
        }
    }
}
