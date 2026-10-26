#include <iostream>
#include <string>
#include <vector>
#include <sstream>

int main() {
    std::string paragraph = "Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week.";
    std::istringstream input(paragraph);
    std::vector<std::string> words;
    for (std::string word; input >> word;)
        words.push_back(word);
    for (std::size_t start = 0; start < words.size();) {
        std::size_t end = start, letters = 0;
        while (end < words.size() && letters + words[end].size() + end - start <= 30) {
            letters += words[end].size();
            end++;
        }
        std::size_t gaps = end - start - 1;
        bool last = end == words.size();
        std::string line;
        for (std::size_t i = start; i < end; i++) {
            line += words[i];
            if (i + 1 < end) {
                std::size_t spaces =
                    last || gaps == 0 ? 1 : (30 - letters) / gaps + (i - start < (30 - letters) % gaps);
                line += std::string(spaces, ' ');
            }
        }
        line.resize(30, ' ');
        std::cout << '|' << line << "|\n";
        start = end;
    }
}
