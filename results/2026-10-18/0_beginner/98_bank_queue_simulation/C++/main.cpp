#include <iostream>
#include <iomanip>
#include <array>
#include <algorithm>

int main() {
    long long x = 42;
    std::array<int, 2> free_time {};
    int arrival = 0, total_wait = 0, maximum = 0;
    for (int k = 1; k <= 20; k++) {
        x = x * 48271 % 2147483647;
        arrival += static_cast<int>(x % 5) + 1;
        x = x * 48271 % 2147483647;
        int service = static_cast<int>(x % 7) + 2, teller = free_time[0] <= free_time[1] ? 0 : 1, start = std::max(arrival,
            free_time[teller]), end = start + service, wait = start - arrival;
        free_time[teller] = end;
        total_wait += wait;
        maximum = std::max(maximum, wait);
        std::cout << "customer " << k << ": arrive=" << arrival << " start=" << start << " end=" << end
            << " teller=" << teller + 1 << " wait=" << wait << '\n';
    }
    double average = total_wait / 20.0;
    int q = static_cast<int>(average * 100 + 0.5);
    std::cout << "average wait: " << q / 100 << '.' << std::setfill('0') << std::setw(2) << q % 100
        << "\nmax wait: " << maximum << "\nlast departure: " << std::max(free_time[0], free_time[1])
        << '\n';
}
