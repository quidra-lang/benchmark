#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    const char *commands[] = {"undo", "type hello world", "delete 5", "type there", "undo", "undo",
        "redo", "type friend", "redo", "delete 20", "undo", "redo", "redo", "type see you"};
    char buffer[256] = "", undo[32][256], redo[32][256];
    int u = 0, r = 0;
    for (int i = 0; i < 14; i++) {
        const char *command = commands[i];
        if (strcmp(command, "undo") == 0) {
            if (!u) {
                puts("undo => nothing to undo");
                continue;
            }
            strcpy(redo[r++], buffer);
            strcpy(buffer, undo[--u]);
        } else if (strcmp(command, "redo") == 0) {
            if (!r) {
                puts("redo => nothing to redo");
                continue;
            }
            strcpy(undo[u++], buffer);
            strcpy(buffer, redo[--r]);
        } else {
            strcpy(undo[u++], buffer);
            r = 0;
            if (strncmp(command, "type ", 5) == 0)
                strcat(buffer, command + 5);
            else {
                int count = atoi(command + 7), len = (int) strlen(buffer);
                buffer[count > len ? 0: len - count] = 0;
            }
        }
        printf("%s => \"%s\"\n", command, buffer);
    }
    return 0;
}
