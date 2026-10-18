#include <iostream>
#include <iomanip>
#include <string>
#include <sstream>

int main() {
    std::string sentence = "we planted beans and carrots in the garden behind our old house";
    std::istringstream input(sentence);
    std::string longest, shortest;
    int count = 0, total = 0;
    for (std::string w; input >> w;) {
        ++count;
        total += static_cast<int>(w.size());
        if (longest.empty() || w.size() > longest.size())
            longest = w;
        if (shortest.empty() || w.size() < shortest.size())
            shortest = w;
    }
    std::cout << "words: " << count << "\nlongest: " << longest << "\nshortest: " << shortest
              << "\naverage length: " << std::fixed << std::setprecision(2)
              << static_cast<double>(total) / count << '\n';
}
