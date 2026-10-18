#include <iostream>
#include <string>
#include <array>

int main() {
    const std::array<std::string, 6> names = {"milk", "notebook", "bread", "apple", "detergent", "eggs"};
    const std::array<int, 6> prices = {198, 165, 248, 128, 437, 268}, quantities = {2, 3, 1, 4, 1, 1}, category = {0,
        1, 0, 0, 1, 0};
    std::array<int, 2> totals {};
    for (int i = 0; i < 6; i++) {
        int subtotal = prices[i] * quantities[i];
        totals[category[i]] += subtotal;
        std::cout << names[i] << ' ' << prices[i] << " x " << quantities[i] << " = " << subtotal << '\n';
    }
    int food_tax = totals[0] * 8 / 100, general_tax = totals[1] * 10 / 100;
    std::cout << "food: " << totals[0] << " yen, tax " << food_tax << " yen\ngeneral: " << totals[1]
        << " yen, tax " << general_tax << " yen\ntotal: " << totals[0] + totals[1] + food_tax + general_tax
        << " yen\n";
}
