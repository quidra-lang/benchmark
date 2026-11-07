#include <iostream>
#include <array>

int main() {
    std::array<int, 10> scores = {78, 90, 100, 59, 80, 85, 89, 70, 45, 93};
    std::array<int, 5> counts{};
    const char *grades = "ABCDF";
    for (int s : scores) {
        int g = s >= 90 ? 0 : s >= 80 ? 1 : s >= 70 ? 2 : s >= 60 ? 3 : 4;
        ++counts[g];
        std::cout << s << ": " << grades[g] << '\n';
    }
    for (int i = 0; i < 5; i++)
        std::cout << grades[i] << ": " << counts[i] << '\n';
}
