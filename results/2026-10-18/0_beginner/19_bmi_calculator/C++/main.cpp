#include <iostream>
#include <string>
#include <array>

int main() {
    const std::array<std::string, 5> names = {"Aiko", "Kenji", "Mika", "Ryo", "Yuki"};
    const std::array<int, 5> heights = {158, 172, 165, 180, 150}, weights = {45, 68, 70, 101, 52};
    for (int i = 0; i < 5; i++) {
        int numerator = weights[i] * 10000, denominator = heights[i] * heights[i];
        double bmi = static_cast<double>(numerator) / denominator;
        std::string category = bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese";
        int q = static_cast<int>(bmi * 10 + 0.5);
        std::cout << names[i] << ": BMI " << q / 10 << '.' << q % 10 << " (" << category << ")\n";
    }
}
