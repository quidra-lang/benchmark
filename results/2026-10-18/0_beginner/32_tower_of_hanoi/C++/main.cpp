#include <iostream>

int hanoi(int n, char source, char target, char auxiliary) {
    if (n == 0)
        return 0;
    int count = hanoi(n - 1, source, auxiliary, target);
    std::cout << "move disk " << n << " from " << source << " to " << target << '\n';
    return count + 1 + hanoi(n - 1, auxiliary, target, source);
}

int main() {
    int count = hanoi(4, 'A', 'C', 'B');
    std::cout << "total moves: " << count << '\n';
}
