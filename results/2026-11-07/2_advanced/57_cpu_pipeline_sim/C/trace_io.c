#include "simulator.h"
static Lines read_lines(const char *path) {
    FILE *input = fopen(path, "rb");
    fseek(input, 0, SEEK_END);
    long size = ftell(input);
    rewind(input);
    char *text = allocate((size_t)size + 1, 1);
    fread(text, 1, (size_t)size, input);
    fclose(input);
    Lines out = {0};
    char *start = text;
    for (long i = 0; i < size; ++i)
        if (text[i] == '\n') {
            text[i] = '\0';
            line(&out, "%s", start);
            start = text + i + 1;
        }
    free(text);
    return out;
}
Input read_inputs(void) {
    Input out = {0};
    out.trace = read_lines("input/trace.txt");
    Lines rows = read_lines("input/config.txt");
    for (int i = 0; i < rows.count; ++i) {
        char key[20];
        sscanf(rows.data[i], "%19s", key);
        const char *text = rows.data[i] + strlen(key) + 1;
        if (strcmp(key, "BTB") == 0)
            sscanf(text, "%d", &out.config.btb);
        else if (strcmp(key, "RAS") == 0)
            sscanf(text, "%d", &out.config.ras);
        else if (strcmp(key, "PREDICTOR") == 0) {
            Predictor *p = &out.config.predictors[out.config.predictor_count++];
            sscanf(text, "%16s %16s %d %d %d %d", p->name, p->scheme, &p->parameters[0],
                   &p->parameters[1], &p->parameters[2], &p->parameters[3]);
        } else if (strcmp(key, "VARIANT") == 0) {
            Variant *v = &out.config.variants[out.config.variant_count++];
            char forward[4], stage[3];
            sscanf(text, "%16s %3s %2s %d", v->name, forward, stage, &v->latency);
            v->forwarding = strcmp(forward, "ON") == 0;
            v->id = strcmp(stage, "ID") == 0;
        } else if (strcmp(key, "PRIMARY") == 0)
            sscanf(text, "%16s %16s", out.config.primary_variant, out.config.primary_predictor);
        else if (strcmp(key, "WINDOW") == 0)
            sscanf(text, "%d %d", &out.config.start, &out.config.end);
        else if (strcmp(key, "TOP") == 0)
            sscanf(text, "%d", &out.config.top);
        else if (strcmp(key, "INTERVAL") == 0)
            sscanf(text, "%d", &out.config.interval);
    }
    free(rows.data);
    return out;
}
bool parse_hex(const char *text, I *value) {
    if (strlen(text) != 8)
        return false;
    I out = 0;
    for (int i = 0; i < 8; ++i) {
        const char ch = text[i];
        if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')))
            return false;
        out = 16 * out + (ch <= '9' ? ch - '0' : ch - 'a' + 10);
    }
    *value = out;
    return true;
}
int parse_register(const char *text) {
    if (strcmp(text, "-") == 0)
        return -1;
    const size_t length = strlen(text);
    if (length < 2 || length > 3 || text[0] != 'r' || (length == 3 && text[1] == '0'))
        return -2;
    int out = 0;
    for (size_t i = 1; i < length; ++i) {
        if (text[i] < '0' || text[i] > '9')
            return -2;
        out = 10 * out + text[i] - '0';
    }
    return out <= 31 ? out : -2;
}
