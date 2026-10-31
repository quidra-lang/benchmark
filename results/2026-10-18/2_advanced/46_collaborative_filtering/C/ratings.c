#include "recommender.h"
char *copy_string(const char *text) {
    const size_t n = strlen(text) + 1;
    char *out = malloc(n);
    memcpy(out, text, n);
    return out;
}
void strings_add(Strings *values, const char *value) {
    values->v = realloc(values->v, (size_t)(values->n + 1) * sizeof *values->v);
    values->v[values->n++] = copy_string(value);
}
bool strings_has(Strings values, const char *value) {
    for (int i = 0; i < values.n; ++i)
        if (strcmp(values.v[i], value) == 0)
            return true;
    return false;
}
static int compare_strings(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}
void strings_sort(Strings values) {
    qsort(values.v, (size_t)values.n, sizeof *values.v, compare_strings);
}
Strings split(const char *text, char delimiter) {
    Strings out = {0};
    const char *start = text;
    for (const char *p = text;; ++p)
        if (*p == delimiter || !*p) {
            const size_t n = (size_t)(p - start);
            char *field = malloc(n + 1);
            memcpy(field, start, n);
            field[n] = 0;
            out.v = realloc(out.v, (size_t)(out.n + 1) * sizeof *out.v);
            out.v[out.n++] = field;
            if (!*p)
                break;
            start = p + 1;
        }
    return out;
}
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
static int integer_compare(const void *a, const void *b) {
    const int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}
static int user_index(const Data *d, int id) {
    for (int u = 0; u < d->nu; ++u)
        if (d->users[u] == id)
            return u;
    return -1;
}
static int item_index(const Data *d, int id) {
    for (int i = 0; i < d->ni; ++i)
        if (d->items[i].id == id)
            return i;
    return -1;
}
static void read_ratings(Data *d, const char *path, bool times) {
    FILE *file = fopen(path, "r");
    char *text = read_line(file);
    free(text);
    while ((text = read_line(file))) {
        Strings fields = split(text, ',');
        Rating *r = times ? &d->train[d->nt++] : &d->test[d->nm++];
        r->user = atoi(fields.v[0]);
        r->item = atoi(fields.v[1]);
        r->rating = atoi(fields.v[2]);
        r->time = times ? strtoll(fields.v[3], NULL, 10) : 0;
        for (int j = 0; j < fields.n; ++j)
            free(fields.v[j]);
        free(fields.v);
        free(text);
    }
    fclose(file);
}
Data *read_input(void) {
    Data *d = calloc(1, sizeof *d);
    read_ratings(d, "input/ratings.csv", true);
    read_ratings(d, "input/test.csv", false);
    FILE *file = fopen("input/items.csv", "r");
    char *text = read_line(file);
    free(text);
    while ((text = read_line(file))) {
        Strings fields = split(text, ',');
        Item *item = &d->catalog[d->nc++];
        item->id = atoi(fields.v[0]);
        item->title = copy_string(fields.v[1]);
        item->genre_list = copy_string(fields.v[2]);
        item->genres = split(fields.v[2], '|');
        for (int j = 0; j < fields.n; ++j)
            free(fields.v[j]);
        free(fields.v);
        free(text);
    }
    fclose(file);
    int ids[300], ni = 0;
    for (int t = 0; t < d->nt; ++t) {
        const Rating *r = &d->train[t];
        if (user_index(d, r->user) < 0)
            d->users[d->nu++] = r->user;
        bool found = false;
        for (int i = 0; i < ni; ++i)
            if (ids[i] == r->item)
                found = true;
        if (!found)
            ids[ni++] = r->item;
    }
    qsort(d->users, (size_t)d->nu, sizeof *d->users, integer_compare);
    qsort(ids, (size_t)ni, sizeof *ids, integer_compare);
    for (int i = 0; i < ni; ++i)
        for (int j = 0; j < d->nc; ++j)
            if (d->catalog[j].id == ids[i])
                d->items[d->ni++] = d->catalog[j];
    int total = 0;
    for (int t = 0; t < d->nt; ++t) {
        Rating *r = &d->train[t];
        r->user = user_index(d, r->user);
        r->item = item_index(d, r->item);
        d->ratings[r->user][r->item] = r->rating;
        ++d->user_count[r->user];
        ++d->item_count[r->item];
        d->user_sum[r->user] += r->rating;
        d->item_sum[r->item] += r->rating;
        total += r->rating;
    }
    for (int t = 0; t < d->nm; ++t) {
        Rating *r = &d->test[t];
        r->user = user_index(d, r->user);
        r->item = item_index(d, r->item);
    }
    d->mean = (double)total / d->nt;
    for (int u = 0; u < d->nu; ++u)
        d->user_mean[u] = (double)d->user_sum[u] / d->user_count[u];
    for (int i = 0; i < d->ni; ++i)
        d->item_mean[i] = (double)d->item_sum[i] / d->item_count[i];
    file = fopen("input/params.txt", "r");
    Params *p = &d->params;
    while ((text = read_line(file))) {
        Strings fields = split(text, ' ');
        const char *key = fields.v[0];
        const double value = strtod(fields.v[1], NULL);
        if (strcmp(key, "NEIGHBORS") == 0)
            p->neighbors = (int)value;
        else if (strcmp(key, "SHRINKAGE") == 0)
            p->shrinkage = (int)value;
        else if (strcmp(key, "MIN_SIMILARITY") == 0)
            p->minimum = value;
        else if (strcmp(key, "BIAS_REG") == 0) {
            p->item_reg = value;
            p->user_reg = strtod(fields.v[2], NULL);
        } else if (strcmp(key, "FACTORS") == 0)
            p->factors = (int)value;
        else if (strcmp(key, "LEARNING_RATE") == 0)
            p->rate = value;
        else if (strcmp(key, "REGULARIZATION") == 0)
            p->regularization = value;
        else if (strcmp(key, "EPOCHS") == 0)
            p->epochs = (int)value;
        else if (strcmp(key, "ALS_REG") == 0)
            p->als_reg = value;
        else if (strcmp(key, "ALS_ITERATIONS") == 0)
            p->iterations = (int)value;
        else if (strcmp(key, "SEED") == 0)
            p->seed = strtoll(fields.v[1], NULL, 10);
        else if (strcmp(key, "TOP_N") == 0)
            p->top = (int)value;
        else if (strcmp(key, "TIME_BUCKETS") == 0)
            p->buckets = (int)value;
        else if (strcmp(key, "LIST_SIZE") == 0)
            p->list = (int)value;
        else {
            Ints *values = strcmp(key, "CUTOFFS") == 0           ? &p->cutoffs
                           : strcmp(key, "NEIGHBOR_GRID") == 0   ? &p->grid
                           : strcmp(key, "USER_GROUPS") == 0     ? &p->user_groups
                           : strcmp(key, "ITEM_GROUPS") == 0     ? &p->item_groups
                           : strcmp(key, "RECOMMEND_USERS") == 0 ? &p->users
                                                                 : &p->items;
            for (int j = 1; j < fields.n; ++j)
                values->v[values->n++] = atoi(fields.v[j]);
        }
        for (int j = 0; j < fields.n; ++j)
            free(fields.v[j]);
        free(fields.v);
        free(text);
    }
    fclose(file);
    return d;
}
