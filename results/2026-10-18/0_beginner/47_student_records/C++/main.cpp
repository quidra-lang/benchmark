#include <iostream>
#include <iomanip>
#include <string>
#include <vector>
#include <array>
#include <algorithm>
#include <numeric>

struct Student {
    std::string name;
    std::array<int, 3> scores;
    int total = 0;
};
int main() {
    std::vector<Student> students = {{"Tanaka", {78, 85, 94}}, {"Suzuki", {88, 74, 82}}, {"Yamada",
        {65, 90, 71}}, {"Ito", {80, 79, 85}}, {"Kato", {92, 88, 95}}, {"Mori", {70, 62, 78}}};
    for (Student &s : students)
        s.total = std::accumulate(s.scores.begin(), s.scores.end(), 0);
    std::sort(students.begin(), students.end(), [](const Student &a, const Student &b) {
        return a.total != b.total ? a.total > b.total : a.name < b.name;
    });
    std::cout << std::fixed << std::setprecision(2);
    int rank = 0;
    for (int i = 0; i < 6; i++) {
        const Student &s = students[i];
        if (i == 0 || s.total != students[i - 1].total)
            rank = i + 1;
        std::cout << rank << ". " << s.name << " total=" << s.total
                  << " average=" << s.total / 3.0 << '\n';
    }
}
