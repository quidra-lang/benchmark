#include <iostream>
#include <string>
#include <array>
#include <map>
#include <sstream>

int main() {
    std::map<std::string, int> balances = {{"Nina", 12000}, {"Leo", 3500}, {"Emma", 800}};
    std::array<std::string, 10> transactions = {"deposit Emma 1200", "withdraw Leo 4000",
        "transfer Nina Leo 5000", "withdraw Leo 4000", "transfer Emma Nina 2500", "transfer Emma Nina 2000",
        "withdraw Emma 300", "deposit Nina 750", "transfer Leo Emma 3200", "withdraw Nina 9800"};
    for (int k = 0; k < 10; k++) {
        std::istringstream input(transactions[k]);
        std::string op, from, to;
        int amount;
        input >> op >> from;
        if (op == "transfer")
            input >> to >> amount;
        else
            input >> amount;
        bool ok = op == "deposit" || balances[from] >= amount;
        if (ok) {
            if (op == "deposit") {
                balances[from] += amount;
            } else {
                balances[from] -= amount;
                if (op == "transfer")
                    balances[to] += amount;
            }
        }
        std::cout << "op " << k + 1 << ": " << transactions[k] << ' ' << (ok ? "ok" : "failed (insufficient funds)")
            << '\n';
    }
    for (const auto &[name, balance] : balances)
        std::cout << name << ": " << balance << '\n';
}
