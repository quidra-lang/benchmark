#include <iostream>
#include <array>

int main() {
    std::array<int, 16> a = {3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77};
    for (int t : std::array<int, 6>{42, 3, 77, 31, 50, 1}) {
        int lo = 0, hi = 15, found = -1;
        std::cout << t << ": probes";
        while (lo <= hi) {
            int mid = (lo + hi) / 2;
            std::cout << ' ' << mid;
            if (a[mid] == t) {
                found = mid;
                break;
            }
            if (a[mid] < t)
                lo = mid + 1;
            else
                hi = mid - 1;
        }
        if (found >= 0)
            std::cout << " -> index " << found << '\n';
        else
            std::cout << " -> not found\n";
    }
}
