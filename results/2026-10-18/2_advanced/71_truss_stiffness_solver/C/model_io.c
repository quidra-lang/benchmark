#include "truss.h"
static int fields(char *line, char delimiter, char **out) {
    int n = 0;
    char separators[2] = {delimiter, 0};
    for (char *token = strtok(line, separators); token; token = strtok(NULL, separators))
        out[n++] = token;
    return n;
}
static int node_index(const Model *m, int id) {
    for (int i = 0; i < m->node_count; ++i)
        if (m->nodes[i].id == id)
            return i;
    return -1;
}
static int member_index(const Model *m, int id) {
    for (int i = 0; i < m->member_count; ++i)
        if (m->members[i].id == id)
            return i;
    return -1;
}
static int section_index(const Model *m, const char *name) {
    for (int i = 0; i < m->section_count; ++i)
        if (!strcmp(m->sections[i].name, name))
            return i;
    return -1;
}
static int material_index(const Model *m, const char *name) {
    for (int i = 0; i < m->material_count; ++i)
        if (!strcmp(m->materials[i].name, name))
            return i;
    return -1;
}
static int case_index(const Model *m, const char *name) {
    for (int i = 0; i < m->case_count; ++i)
        if (!strcmp(m->cases[i].name, name))
            return i;
    return -1;
}
static FILE *csv(const char *name, char *line) {
    char path[128];
    snprintf(path, sizeof path, "input/%s.csv", name);
    FILE *file = fopen(path, "r");
    fgets(line, 2048, file);
    return file;
}
static bool row(FILE *file, char *line, char **parts, int *count, char delimiter) {
    if (!fgets(line, 2048, file))
        return false;
    line[strcspn(line, "\n")] = 0;
    *count = fields(line, delimiter, parts);
    return true;
}
void read_model(Model *m) {
    memset(m, 0, sizeof *m);
    char text[2048], *p[1024];
    int n;
    FILE *file = csv("nodes", text);
    while (row(file, text, p, &n, ',')) {
        Node *v = &m->nodes[m->node_count++];
        *v = (Node){atoi(p[0]), atoi(p[1]), atoi(p[2])};
    }
    fclose(file);
    file = csv("sections", text);
    while (row(file, text, p, &n, ',')) {
        Section *v = &m->sections[m->section_count++];
        strcpy(v->name, p[0]);
        v->area = strtod(p[1], NULL);
        v->inertia = strtod(p[2], NULL);
    }
    fclose(file);
    file = csv("materials", text);
    while (row(file, text, p, &n, ',')) {
        Material *v = &m->materials[m->material_count++];
        strcpy(v->name, p[0]);
        v->young = strtod(p[1], NULL);
        v->yield_stress = strtod(p[2], NULL);
        v->density = strtod(p[3], NULL);
        v->expansion = strtod(p[4], NULL);
    }
    fclose(file);
    file = csv("members", text);
    while (row(file, text, p, &n, ',')) {
        Member *v = &m->members[m->member_count++];
        v->id = atoi(p[0]);
        v->start = node_index(m, atoi(p[1]));
        v->end = node_index(m, atoi(p[2]));
        v->section = section_index(m, p[3]);
        v->material = material_index(m, p[4]);
        strcpy(v->group, p[5]);
    }
    fclose(file);
    file = csv("supports", text);
    while (row(file, text, p, &n, ',')) {
        Support *v = &m->supports[m->support_count++];
        v->node = node_index(m, atoi(p[0]));
        for (int a = 0; a < 2; ++a) {
            v->fixed[a] = atoi(p[1 + a]) != 0;
            v->prescribed[a] = strtod(p[3 + a], NULL);
        }
    }
    fclose(file);
    file = fopen("input/loads.txt", "r");
    while (row(file, text, p, &n, ' ')) {
        if (!strcmp(p[0], "LOADCASE"))
            strcpy(m->cases[m->case_count++].name, p[1]);
        else if (!strcmp(p[0], "END"))
            continue;
        else if (!strcmp(p[0], "COMBINATION")) {
            Combination *v = &m->combinations[m->combination_count++];
            strcpy(v->name, p[1]);
            for (int i = 2; i < n; i += 2)
                v->terms[v->count++] = (Term){case_index(m, p[i]), strtod(p[i + 1], NULL)};
        } else {
            LoadCase *c = &m->cases[m->case_count - 1];
            Load *v = &c->lines[c->count++];
            if (!strcmp(p[0], "FORCE"))
                *v = (Load){FORCE, node_index(m, atoi(p[1])), strtod(p[2], NULL),
                            strtod(p[3], NULL)};
            else if (!strcmp(p[0], "TEMPERATURE"))
                *v = (Load){TEMPERATURE, member_index(m, atoi(p[1])), strtod(p[2], NULL), 0};
            else
                v->kind = !strcmp(p[0], "SELFWEIGHT") ? SELFWEIGHT : SETTLEMENT;
        }
    }
    fclose(file);
    Settings *s = &m->settings;
    file = fopen("input/params.txt", "r");
    while (row(file, text, p, &n, ' ')) {
        if (!strcmp(p[0], "deck")) {
            for (int i = 1; i < n; ++i)
                s->deck[s->deck_count++] = node_index(m, atoi(p[i]));
        } else if (!strcmp(p[0], "influence")) {
            if (s->influence_count == s->influence_capacity) {
                s->influence_capacity = s->influence_capacity ? 2 * s->influence_capacity : 4;
                s->influence =
                    realloc(s->influence, (size_t)s->influence_capacity * sizeof *s->influence);
            }
            s->influence[s->influence_count++] = member_index(m, atoi(p[1]));
        } else if (!strcmp(p[0], "vehicle")) {
            s->vehicle_step = atoi(p[1]);
            for (int i = 2; i < n; i += 2)
                s->axles[s->axle_count++] = (Axle){atoi(p[i]), strtod(p[i + 1], NULL)};
        } else if (!strcmp(p[0], "rating")) {
            strcpy(s->rating, p[1]);
            s->dead_factor = strtod(p[2], NULL);
            s->vehicle_factor = strtod(p[3], NULL);
        } else if (!strcmp(p[0], "slenderness")) {
            s->compression_limit = strtod(p[1], NULL);
            s->tension_limit = strtod(p[2], NULL);
        } else if (!strcmp(p[0], "deflection")) {
            strcpy(s->deflection, p[1]);
            s->deflection_ratio = atoi(p[2]);
        } else if (!strcmp(p[0], "vibration")) {
            strcpy(s->vibration, p[1]);
            s->modes = atoi(p[2]);
            s->iterations = atoi(p[3]);
        } else if (!strcmp(p[0], "removal"))
            strcpy(s->removal, p[1]);
        else if (!strcmp(p[0], "drawing")) {
            if (s->drawing_count == s->drawing_capacity) {
                s->drawing_capacity = s->drawing_capacity ? 2 * s->drawing_capacity : 4;
                s->drawings =
                    realloc(s->drawings, (size_t)s->drawing_capacity * sizeof *s->drawings);
            }
            Drawing *v = &s->drawings[s->drawing_count++];
            strcpy(v->name, p[1]);
            v->magnification = atoi(p[2]);
            v->horizontal = atoi(p[3]);
            v->vertical = atoi(p[4]);
        } else {
            s->map_horizontal = atoi(p[1]);
            s->map_vertical = atoi(p[2]);
        }
    }
    fclose(file);
}
