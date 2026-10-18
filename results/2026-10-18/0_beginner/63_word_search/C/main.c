#include <stdio.h>

int main(void) {
    const char *board[] = {"MMONKENBIR", "PMTIGERJPL", "TGREJEDUZI", "SPYUTEJDEC", "WKAPSIDLBN", "KUVNGSBPRO",
        "RIBSDACBAM", "YWVAUAPKAH", "KYCGTHHESR", "OCCALAOKKR"}, *words[] = {"TIGER", "ZEBRA", "MONKEY",
        "PANDA", "KOALA", "RABBIT"}, *names[] = {"E", "SE", "S", "SW", "W", "NW", "N", "NE"};
    int dr[] = {0, 1, 1, 1, 0, -1, -1, -1}, dc[] = {1, 1, 0, -1, -1, -1, 0, 1};
    for (int w = 0; w < 6; w++) {
        int found = 0;
        for (int r = 0; r < 10 && !found; r++)
            for (int c = 0; c < 10 && !found; c++)
                for (int d = 0; d < 8; d++) {
                    int match = 1;
                    for (int k = 0; words[w][k]; k++) {
                        int rr = r + dr[d] * k, cc = c + dc[d] * k;
                        if (rr < 0 || rr >= 10 || cc < 0 || cc >= 10 || board[rr][cc] != words[w][k]) {
                            match = 0;
                            break;
                        }
                    }
                    if (match) {
                        printf("%s: (%d, %d) %s\n", words[w], r, c, names[d]);
                        found = 1;
                        break;
                    }
                }
        if (!found)
            printf("%s: not found\n", words[w]);
    }
    return 0;
}
