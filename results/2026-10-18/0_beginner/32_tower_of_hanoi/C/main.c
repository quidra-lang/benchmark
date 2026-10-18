#include <stdio.h>

int hanoi(int n, char source, char target, char auxiliary) {
    if (n == 0)
        return 0;
    int count = hanoi(n - 1, source, auxiliary, target);
    printf("move disk %d from %c to %c\n", n, source, target);
    return count + 1 + hanoi(n - 1, auxiliary, target, source);
}

int main(void) {
    printf("total moves: %d\n", hanoi(4, 'A', 'C', 'B'));
    return 0;
}
