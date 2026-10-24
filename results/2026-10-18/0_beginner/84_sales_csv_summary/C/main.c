#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char name[32];
    int total;
} Entry;
void add(Entry *entries, int *count, const char *name, int amount) {
    int i = 0;
    while (i < * count && strcmp(entries[i].name, name))
        i++;
    if (i == * count) {
        strcpy(entries[i].name, name);
        entries[i].total = 0;
        (*count)++;
    }
    entries[i].total += amount;
}

int by_total(const void *a, const void *b) {
    const Entry *x = a, *y = b;
    return x->total != y->total ? y->total - x->total: strcmp(x->name, y->name);
}

int by_name(const void *a, const void *b) {
    return strcmp(((const Entry *) a)->name, ((const Entry *) b)->name);
}

int main(void) {
    const char *lines[] = {"date,region,product,quantity,unit_price", "2026-04-01,north,notebook,10,200",
        "2026-04-01,east,marker,6,150", "2026-04-01,south,eraser,25,80", "2026-04-02,west,stapler,4,600",
        "2026-04-02,north,marker,8,150", "2026-04-02,east,notebook,9,200", "2026-04-03,south,stapler,3,600",
        "2026-04-03,west,eraser,15,80", "2026-04-03,north,eraser,20,80", "2026-04-04,east,stapler,5,600",
        "2026-04-04,south,notebook,6,200", "2026-04-04,west,marker,8,150"};
    Entry regions[12], products[12], days[12];
    int nr = 0, np = 0, nd = 0, total = 0;
    for (int i = 1; i < 13; i++) {
        char line[128];
        strcpy(line, lines[i]);
        char *fields[5];
        int f = 0;
        for (char *part = strtok(line, ","); part; part = strtok(NULL, ","))
            fields[f++] = part;
        int quantity = atoi(fields[3]), price = atoi(fields[4]), amount = quantity * price;
        total += amount;
        add(regions, &nr, fields[1], amount);
        add(products, &np, fields[2], quantity);
        add(days, &nd, fields[0], amount);
    }
    qsort(regions, nr, sizeof(Entry), by_total);
    qsort(products, np, sizeof(Entry), by_name);
    qsort(days, nd, sizeof(Entry), by_total);
    printf("total: %d\n", total);
    for (int i = 0; i < nr; i++)
        printf("%s: %d\n", regions[i].name, regions[i].total);
    for (int i = 0; i < np; i++)
        printf("%s: %d\n", products[i].name, products[i].total);
    printf("best day: %s (%d)\n", days[0].name, days[0].total);
    return 0;
}
