#include <iostream>
#include <iomanip>
#include <string>
#include <sstream>

int main() {
    const std::string sentence = "we planted beans and carrots in the garden behind our old house";
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
    double avg = static_cast<double>(total) / count;
    int q = static_cast<int>(avg * 100 + 0.5);
    std::cout << "words: " << count << "\nlongest: " << longest << "\nshortest: " << shortest << "\naverage length: "
        << q / 100 << '.' << std::setfill('0') << std::setw(2) << q % 100 << '\n';
}
