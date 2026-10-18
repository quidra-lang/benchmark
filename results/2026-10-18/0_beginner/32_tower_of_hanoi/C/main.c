#include <stdio.h>

int hanoi(int n, char source, char target, char auxiliary) {
    if (n == 0)
        return 0;
    int count = hanoi(n - 1, source, auxiliary, target);
    printf("move disk %d from %c to %c\n", n, source, target);
    return count + 1 + hanoi(n - 1, auxiliary, target, source);
}

int main(void) {
    int count = hanoi(4, 'A', 'C', 'B');
    printf("total moves: %d\n", count);
    return 0;
}
