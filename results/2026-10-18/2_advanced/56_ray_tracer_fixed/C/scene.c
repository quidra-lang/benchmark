#include "renderer.h"
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
void line(Lines *lines, const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *text = allocate((size_t)length + 1, 1);
    vsnprintf(text, (size_t)length + 1, pattern, args);
    va_end(args);
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? lines->capacity * 2 : 32;
        char **values = allocate(capacity, sizeof(char *));
        if (lines->count)
            memcpy(values, lines->data, lines->count * sizeof(char *));
        lines->data = values;
        lines->capacity = capacity;
    }
    lines->data[lines->count++] = text;
}
static char *read_line(FILE *input) {
    int capacity = 128, count = 0;
    char *data = allocate(capacity, 1);
    int ch;
    while ((ch = fgetc(input)) != EOF && ch != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            char *replacement = allocate(capacity, 1);
            memcpy(replacement, data, count);
            data = replacement;
        }
        data[count++] = (char)ch;
    }
    return ch == EOF && count == 0 ? NULL : data;
}
Lines read_lines(const char *name) {
    FILE *input = fopen(name, "r");
    Lines out = {0};
    char *text;
    while ((text = read_line(input)) != NULL)
        line(&out, "%s", text);
    fclose(input);
    return out;
}
Tokens split_words(const char *text) {
    char *copy = format("%s", text);
    Tokens out = {.data = allocate(strlen(text) + 1, sizeof(char *))};
    for (char *word = strtok(copy, " "); word; word = strtok(NULL, " "))
        out.data[out.count++] = word;
    return out;
}
Vec parse_vec(Tokens tokens, int start) {
    Vec out;
    for (int i = 0; i < 3; ++i)
        out.data[i] = strtoll(tokens.data[start + i], NULL, 10);
    return out;
}
static int find_material(const Scene *scene, const char *name) {
    for (int i = 0; i < scene->material_count; ++i)
        if (!strcmp(scene->materials[i].name, name))
            return i;
    return -1;
}
const char *object_kind(ObjectKind kind) {
    static const char *names[] = {"sphere", "plane", "box"};
    return names[kind];
}
const char *light_kind(LightKind kind) {
    static const char *names[] = {"point", "spot", "sun", "area"};
    return names[kind];
}
Scene load_scene(void) {
    Scene scene = {0};
    Lines lines = read_lines("input/scene.txt");
    for (int row = 0; row < lines.count; ++row) {
        const char *text = lines.data[row];
        if (!text[0] || text[0] == '#')
            continue;
        Tokens fields = split_words(text);
        const char *kind = fields.data[0];
        if (!strcmp(kind, "eye"))
            scene.eye = parse_vec(fields, 1);
        else if (!strcmp(kind, "forward"))
            scene.forward = parse_vec(fields, 1);
        else if (!strcmp(kind, "right"))
            scene.right = parse_vec(fields, 1);
        else if (!strcmp(kind, "up"))
            scene.up = parse_vec(fields, 1);
        else if (!strcmp(kind, "view")) {
            scene.half_width = strtoll(fields.data[1], NULL, 10);
            scene.half_height = strtoll(fields.data[2], NULL, 10);
        } else if (!strcmp(kind, "background"))
            scene.background = parse_vec(fields, 1);
        else if (!strcmp(kind, "ambient"))
            scene.ambient = strtoll(fields.data[1], NULL, 10);
        else if (!strcmp(kind, "fog")) {
            scene.fog = true;
            scene.fog_color = parse_vec(fields, 1);
            scene.fog_start = strtoll(fields.data[4], NULL, 10);
            scene.fog_end = strtoll(fields.data[5], NULL, 10);
        } else if (!strcmp(kind, "material")) {
            Material *value = &scene.materials[scene.material_count++];
            value->name = fields.data[1];
            value->color = parse_vec(fields, 2);
            value->kd = strtoll(fields.data[5], NULL, 10);
            value->ks = strtoll(fields.data[6], NULL, 10);
            value->exponent = strtoll(fields.data[7], NULL, 10);
            value->kr = strtoll(fields.data[8], NULL, 10);
            value->kt = strtoll(fields.data[9], NULL, 10);
            value->ior = strtoll(fields.data[10], NULL, 10);
        } else if (!strcmp(kind, "checker")) {
            Material *value = &scene.materials[find_material(&scene, fields.data[1])];
            value->second = parse_vec(fields, 2);
            value->checker_size = strtoll(fields.data[5], NULL, 10);
        } else if (!strcmp(kind, "point") || !strcmp(kind, "spot") || !strcmp(kind, "sun") ||
                   !strcmp(kind, "area")) {
            Light light = {.divisions = 1};
            light.kind = !strcmp(kind, "point")  ? POINT
                         : !strcmp(kind, "spot") ? SPOT
                         : !strcmp(kind, "sun")  ? SUN
                                                 : AREA;
            if (light.kind == SUN) {
                light.direction = norm(negate(parse_vec(fields, 1)));
                light.intensity = strtoll(fields.data[4], NULL, 10);
            } else {
                light.position = parse_vec(fields, 1);
                if (light.kind == POINT)
                    light.intensity = strtoll(fields.data[4], NULL, 10);
                else if (light.kind == SPOT) {
                    light.direction = norm(parse_vec(fields, 4));
                    light.outer = strtoll(fields.data[7], NULL, 10);
                    light.inner = strtoll(fields.data[8], NULL, 10);
                    light.intensity = strtoll(fields.data[9], NULL, 10);
                } else {
                    light.u = parse_vec(fields, 4);
                    light.v = parse_vec(fields, 7);
                    light.divisions = atoi(fields.data[10]);
                    light.intensity = strtoll(fields.data[11], NULL, 10);
                }
            }
            scene.lights[scene.light_count++] = light;
        } else {
            Object object = {.label = fields.data[1][0], .material = find_material(&scene, fields.data[2])};
            object.kind = !strcmp(kind, "sphere") ? SPHERE : !strcmp(kind, "plane") ? PLANE : BOX;
            object.first = parse_vec(fields, 3);
            if (object.kind == SPHERE)
                object.radius = strtoll(fields.data[6], NULL, 10);
            else {
                object.second = parse_vec(fields, 6);
                if (object.kind == PLANE)
                    object.second = norm(object.second);
            }
            scene.objects[scene.object_count++] = object;
        }
    }
    return scene;
}
