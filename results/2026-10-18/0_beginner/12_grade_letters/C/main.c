#include <stdio.h>

int main(void) {
    int scores[] = {78, 90, 100, 59, 80, 85, 89, 70, 45, 93}, counts[5] = {0};
    const char *grades = "ABCDF";
    for (int i = 0; i < 10; i++) {
        int s = scores[i], g = s >= 90 ? 0 : s >= 80 ? 1 : s >= 70 ? 2 : s >= 60 ? 3 : 4;
        counts[g]++;
        printf("%d: %c\n", s, grades[g]);
    }
    for (int i = 0; i < 5; i++)
        printf("%c: %d\n", grades[i], counts[i]);
    return 0;
}
