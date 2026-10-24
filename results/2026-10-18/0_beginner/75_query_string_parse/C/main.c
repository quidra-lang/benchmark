#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char key[128], value[256];
    int order;
} Entry;
int compare(const void *a, const void *b) {
    const Entry *x = a, *y = b;
    int c = strcmp(x->key, y->key);
    return c ? c: x->order - y->order;
}

void decode(const char *s, char *out) {
    while (*s) {
        if (*s == '+') {
            *out++ = ' ';
            s++;
        } else if (*s == '%') {
            unsigned byte;
            sscanf(s + 1, "%2x", &byte);
            *out++ = (char)byte;
            s += 3;
        } else
            *out++ = *s++;
    }
    *out = 0;
}

int main(void) {
    const char *queries[] = {"name=Alice+Smith&age=30&city=New%20York", "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
        "msg=50%25+off%21&debug&lang=en&ref=&lang=ja", "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips"};
    for (int k = 0; k < 4; k++) {
        char query[256];
        strcpy(query, queries[k]);
        Entry entries[16];
        int count = 0;
        for (char *item = strtok(query, "&"); item; item = strtok(NULL, "&")) {
            char *equal = strchr(item, '=');
            if (equal)
                *equal++ = 0;
            decode(item, entries[count].key);
            decode(equal ? equal: "", entries[count].value);
            entries[count].order = count;
            count++;
        }
        qsort(entries, count, sizeof(Entry), compare);
        printf("query %d:\n", k + 1);
        for (int i = 0; i < count; i++) {
            if (i == 0 || strcmp(entries[i].key, entries[i - 1].key)) {
                if (i)
                    putchar('\n');
                printf("  %s: ", entries[i].key);
            } else
                printf(", ");
            printf("\"%s\"", entries[i].value);
        }
        putchar('\n');
    }
    return 0;
}
