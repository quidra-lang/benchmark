#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *name;
    int scores[3];
    int total;
} Student;
int compare(const void *a, const void *b) {
    const Student *x = a, *y = b;
    if (x -> total != y -> total)
        return y -> total - x -> total;
    return strcmp(x -> name, y -> name);
}

int main(void) {
    Student students[] = {{"Tanaka", {78, 85, 94}, 0}, {"Suzuki", {88, 74, 82}, 0}, {"Yamada", {65,
        90, 71}, 0}, {"Ito", {80, 79, 85}, 0}, {"Kato", {92, 88, 95}, 0}, {"Mori", {70, 62, 78}, 0}};
    for (int i = 0; i < 6; i++)
        for (int j = 0; j < 3; j++)
            students[i].total += students[i].scores[j];
    qsort(students, 6, sizeof(Student), compare);
    int rank = 0;
    for (int i = 0; i < 6; i++) {
        if (i == 0 || students[i].total != students[i - 1].total)
            rank = i + 1;
        printf("%d. %s total=%d average=%.2f\n",
               rank, students[i].name, students[i].total, students[i].total / 3.0);
    }
    return 0;
}
