#include <stdio.h>

int main(void) {
    int games[5][21] = {{8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2}, {3, 4, 5, 2, 7,
        1, 0, 6, 8, 1, 4, 4, 2, 3, 6, 2, 9, 0, 1, 5}, {5, 5, 0, 10, 7, 3, 9, 1, 6, 4, 8, 2, 3, 7, 4, 6,
        1, 9, 7, 3, 5}, {10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10}, {10, 9, 1, 10, 10, 7, 2, 0, 0,
        10, 8, 1, 10, 6, 4, 10}};
    for (int g = 0; g < 5; g++) {
        int index = 0, total = 0;
        printf("game %d:", g + 1);
        for (int frame = 0; frame < 10; frame++) {
            int score;
            if (frame == 9) {
                score = games[g][index] + games[g][index + 1];
                if (games[g][index] == 10 || score == 10)
                    score += games[g][index + 2];
            } else if (games[g][index] == 10) {
                score = 10 + games[g][index + 1] + games[g][index + 2];
                index++;
            } else {
                score = games[g][index] + games[g][index + 1];
                if (score == 10)
                    score += games[g][index + 2];
                index += 2;
            }
            total += score;
            printf(" %d", total);
        }
        putchar('\n');
    }
    return 0;
}
