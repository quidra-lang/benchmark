#include "detector.h"
typedef struct Allocation {
    void *value;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
void *allocate(size_t count, size_t size) {
    void *value = calloc(count ? count : 1, size);
    Allocation *record = malloc(sizeof(*record));
    if (!value || !record)
        exit(1);
    *record = (Allocation){value, allocations};
    allocations = record;
    return value;
}
void release_all(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->value);
        free(allocations);
        allocations = next;
    }
}
char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = allocate((size_t)length + 1, 1);
    vsnprintf(result, (size_t)length + 1, pattern, args);
    va_end(args);
    return result;
}
void release_one(void *value) {
    Allocation **current = &allocations;
    while (*current && (*current)->value != value)
        current = &(*current)->next;
    if (*current) {
        Allocation *record = *current;
        *current = record->next;
        free(record->value);
        free(record);
    }
}
void point_push(Points *list, Point value) {
    if (list->count == list->capacity) {
        int capacity = list->capacity ? list->capacity * 2 : 16;
        Point *data = allocate(capacity, sizeof(Point));
        if (list->count)
            memcpy(data, list->data, list->count * sizeof(Point));
        list->data = data;
        list->capacity = capacity;
    }
    list->data[list->count++] = value;
}
void id_push(Ids *list, int value) {
    if (list->count == list->capacity) {
        int capacity = list->capacity ? list->capacity * 2 : 8;
        int *data = allocate(capacity, sizeof(int));
        if (list->count)
            memcpy(data, list->data, list->count * sizeof(int));
        list->data = data;
        list->capacity = capacity;
    }
    list->data[list->count++] = value;
}
Image image_new(int width, int height) {
    return (Image){width, height, allocate((size_t)width * height, sizeof(I))};
}
I image_at(Image image, Point point) {
    return image.data[point.y * image.width + point.x];
}
void image_set(Image image, Point point, I value) {
    image.data[point.y * image.width + point.x] = value;
}
bool image_inside(Image image, Point point) {
    return point.x >= 0 && point.x < image.width && point.y >= 0 && point.y < image.height;
}
Input load(void) {
    Input out = {0};
    FILE *input = fopen("input/image.pgm", "r");
    char key[64];
    int width, height, maximum;
    fscanf(input, "%63s %d %d %d", key, &width, &height, &maximum);
    out.image = image_new(width, height);
    for (int i = 0; i < width * height; ++i)
        fscanf(input, "%" SCNd64, &out.image.data[i]);
    fclose(input);
    input = fopen("input/trig.txt", "r");
    for (int i = 0; i < 180; ++i) {
        int angle;
        fscanf(input, "%d %" SCNd64 " %" SCNd64, &angle, &out.trig.data[i][0], &out.trig.data[i][1]);
    }
    fclose(input);
    input = fopen("input/params.txt", "r");
    Params *p = &out.params;
    fscanf(input, "%63s %" SCNd64 " %63s", key, &p->ks, key);
    p->kernel = allocate(p->ks * p->ks, sizeof(I));
    for (I i = 0; i < p->ks * p->ks; ++i)
        fscanf(input, "%" SCNd64, &p->kernel[i]);
    I *fields[] = {&p->divisor,
                   &p->low,
                   &p->high,
                   &p->r_min,
                   &p->r_max,
                   &p->circle_percent,
                   &p->circle_count,
                   &p->rho_step,
                   &p->vote_threshold,
                   &p->line_count,
                   &p->tolerance,
                   &p->max_gap,
                   &p->min_length,
                   &p->junction_distance,
                   &p->junction_angle,
                   &p->angle_tolerance,
                   &p->square_tolerance,
                   &p->margin,
                   &p->harris_window,
                   &p->harris_threshold,
                   &p->corner_count,
                   &p->match_distance,
                   &p->overlay_divisor};
    for (int i = 0; i < 23; ++i)
        fscanf(input, "%63s %" SCNd64, key, fields[i]);
    fclose(input);
    return out;
}
void write_pgm(const char *name, Image image) {
    FILE *out = fopen(format("output/%s", name), "w");
    fprintf(out, "P2\n%d %d\n255\n", image.width, image.height);
    for (int y = 0; y < image.height; ++y) {
        for (int x = 0; x < image.width; ++x)
            fprintf(out, "%s%" PRId64, x ? " " : "", image_at(image, (Point){x, y}));
        fputc('\n', out);
    }
    fclose(out);
}
