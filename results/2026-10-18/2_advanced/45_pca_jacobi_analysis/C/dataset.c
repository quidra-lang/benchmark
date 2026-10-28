#include "analysis.h"
static void read_data(const char *path, Input *input, bool supplementary) {
    FILE *file = fopen(path, "r");
    char line[2048];
    fgets(line, sizeof line, file);
    if (!supplementary) {
        char *field = strtok(line, ",\n");
        while ((field = strtok(NULL, ",\n")))
            strcpy(input->names[input->p++], field);
    }
    while (fgets(line, sizeof line, file)) {
        Sample *row = supplementary ? &input->supplementary[input->ns++] : &input->data[input->n++];
        char *field = strtok(line, ",\n");
        strcpy(row->id, field);
        for (int j = 0; j < input->p; ++j) {
            field = strtok(NULL, ",\n");
            row->missing[j] = strcmp(field, "NA") == 0;
            if (!row->missing[j])
                row->values[j] = strtod(field, NULL);
        }
    }
    fclose(file);
}
Input read_input(void) {
    Input out = {0};
    read_data("input/data.csv", &out, false);
    read_data("input/supplementary.csv", &out, true);
    FILE *file = fopen("input/params.txt", "r");
    char key[32];
    Params *p = &out.params;
    fscanf(file, "%31s %15s", key, p->missing);
    fscanf(file, "%31s %15s", key, p->scaling);
    fscanf(file, "%31s %15s", key, p->components);
    fscanf(file, "%31s %lf", key, &p->cumulative);
    long long seed;
    fscanf(file, "%31s %d %lld", key, &p->repetitions, &seed);
    p->seed = seed;
    fscanf(file, "%31s %lf", key, &p->t2);
    fscanf(file, "%31s %lf", key, &p->spe);
    fscanf(file, "%31s %d", key, &p->cycles);
    fscanf(file, "%31s %d", key, &p->top);
    fscanf(file, "%31s %d", key, &p->scree);
    fscanf(file, "%31s %d %d", key, &p->bw, &p->bh);
    fscanf(file, "%31s %d", key, &p->radius);
    fscanf(file, "%31s %d %d", key, &p->dw, &p->dh);
    fclose(file);
    return out;
}
