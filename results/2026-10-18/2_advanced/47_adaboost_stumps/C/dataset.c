#include "boosting.h"
static char *read_line(FILE *file) {
    Text out = {0};
    int ch;
    while ((ch = fgetc(file)) != EOF && ch != '\n') {
        if (out.size + 1 >= out.capacity) {
            out.capacity = out.capacity ? out.capacity * 2 : 128;
            out.data = realloc(out.data, out.capacity);
        }
        out.data[out.size++] = (char)ch;
    }
    if (ch == EOF && out.size == 0) {
        free(out.data);
        return NULL;
    }
    if (!out.data)
        out.data = malloc(1);
    out.data[out.size] = 0;
    return out.data;
}
static void read_rows(const char *path, Rows *out, char names[10][17]) {
    FILE *file = fopen(path, "r");
    char *text = read_line(file);
    char *field = strtok(text, ",");
    while ((field = strtok(NULL, ","))) {
        if (strcmp(field, "label") == 0)
            break;
        if (names)
            strcpy(names[out->d], field);
        ++out->d;
    }
    free(text);
    while ((text = read_line(file))) {
        Row *row = &out->rows[out->n++];
        field = strtok(text, ",");
        strcpy(row->id, field);
        for (int j = 0; j < out->d; ++j)
            row->values[j] = strtod(strtok(NULL, ","), NULL);
        row->label = atoi(strtok(NULL, ","));
        free(text);
    }
    fclose(file);
}
Input *read_input(void) {
    Input *out = calloc(1, sizeof *out);
    read_rows("input/train.csv", &out->train, out->names);
    read_rows("input/test.csv", &out->test, NULL);
    FILE *file = fopen("input/multiclass.csv", "r");
    char *text = read_line(file);
    char *field = strtok(text, ",");
    int d = 0;
    while ((field = strtok(NULL, ","))) {
        if (strcmp(field, "class") == 0)
            break;
        strcpy(out->multi_names[d++], field);
    }
    out->multi_train.d = out->multi_test.d = d;
    free(text);
    while ((text = read_line(file))) {
        Row row = {0};
        strcpy(row.id, strtok(text, ","));
        for (int j = 0; j < d; ++j)
            row.values[j] = strtod(strtok(NULL, ","), NULL);
        row.label = atoi(strtok(NULL, ","));
        const char *role = strtok(NULL, ",");
        Rows *rows = strcmp(role, "train") == 0 ? &out->multi_train : &out->multi_test;
        rows->rows[rows->n++] = row;
        free(text);
    }
    fclose(file);
    file = fopen("input/params.txt", "r");
    Params *p = &out->params;
    while ((text = read_line(file))) {
        char *key = strtok(text, " ");
        field = strtok(NULL, " ");
        if (strcmp(key, "ROUNDS") == 0)
            p->rounds = atoi(field);
        else if (strcmp(key, "VARIANTS") == 0) {
            do {
                strcpy(p->variants[p->nvariants++], field);
            } while ((field = strtok(NULL, " ")));
        } else if (strcmp(key, "BINS") == 0)
            p->bins = atoi(field);
        else if (strcmp(key, "SMOOTHING") == 0)
            p->smoothing = strtod(field, NULL);
        else if (strcmp(key, "CONVERGENCE") == 0)
            p->convergence = strtod(field, NULL);
        else if (strcmp(key, "CLIP") == 0)
            p->clip = strtod(field, NULL);
        else if (strcmp(key, "FOLDS") == 0)
            p->folds = atoi(field);
        else if (strcmp(key, "CLASSES") == 0)
            p->classes = atoi(field);
        else if (strcmp(key, "SAMME_ROUNDS") == 0)
            p->samme_rounds = atoi(field);
        else if (strcmp(key, "PERMUTATION") == 0) {
            p->permutations = atoi(field);
            p->permutation_seed = strtoll(strtok(NULL, " "), NULL, 10);
        } else if (strcmp(key, "BOOTSTRAP") == 0) {
            p->bootstrap = atoi(field);
            p->bootstrap_seed = strtoll(strtok(NULL, " "), NULL, 10);
        } else if (strcmp(key, "NOISE") == 0) {
            p->noise_seed = strtoll(field, NULL, 10);
            while ((field = strtok(NULL, " ")))
                p->noise.v[p->noise.n++] = atoi(field);
        } else if (strcmp(key, "SIZES") == 0) {
            do {
                p->sizes.v[p->sizes.n++] = atoi(field);
            } while ((field = strtok(NULL, " ")));
        } else {
            Vector *values = strcmp(key, "MARGINS") == 0 ? &p->margins : &p->shrinkage;
            do {
                values->v[values->n++] = strtod(field, NULL);
            } while ((field = strtok(NULL, " ")));
        }
        free(text);
    }
    fclose(file);
    return out;
}
