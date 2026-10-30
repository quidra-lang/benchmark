#include "bayes.h"
char *read_line(FILE *input) {
    Text out = {0};
    int c;
    while ((c = fgetc(input)) != EOF && c != '\n')
        text(&out, "%c", c);
    if (c == EOF && !out.length) {
        free(out.data);
        return NULL;
    }
    if (!out.data)
        text(&out, "");
    return out.data;
}
int variable_id(const Network *network, const char *name) {
    for (int i = 0; i < network->count; ++i)
        if (!strcmp(network->names[i], name))
            return i;
    return -1;
}
int state_id(const Network *network, int variable, const char *name) {
    for (int i = 0; i < network->sizes[variable]; ++i)
        if (!strcmp(network->states[variable][i], name))
            return i;
    return -1;
}
Input *read_inputs(void) {
    Input *out = calloc(1, sizeof(Input));
    Network *network = &out->network;
    FILE *in = fopen("input/network.txt", "r");
    char *value;
    while ((value = read_line(in))) {
        if (!*value || value[0] == '#') {
            free(value);
            continue;
        }
        char *key = strtok(value, " "), *name = strtok(NULL, " ");
        if (!strcmp(key, "VARIABLE")) {
            int v = network->count++;
            strcpy(network->names[v], name);
            char *state;
            while ((state = strtok(NULL, " ")))
                strcpy(network->states[v][network->sizes[v]++], state);
        } else if (!strcmp(key, "PARENTS")) {
            int v = variable_id(network, name);
            char *parent;
            while ((parent = strtok(NULL, " ")))
                network->parents[v].values[network->parents[v].count++] =
                    variable_id(network, parent);
        } else {
            int v = variable_id(network, name), rows = 1;
            for (int i = 0; i < network->parents[v].count; ++i)
                rows *= network->sizes[network->parents[v].values[i]];
            CPT *table = &network->expert[v];
            table->rows = rows;
            table->states = network->sizes[v];
            table->values = calloc((size_t)rows, sizeof(*table->values));
            for (int row = 0; row < rows; ++row) {
                char *line_value = read_line(in), *token = strtok(line_value, " ");
                for (int state = 0; state < table->states; ++state) {
                    table->values[row][state] = strtod(token, NULL);
                    token = strtok(NULL, " ");
                }
                free(line_value);
            }
            network->has_expert[v] = 1;
        }
        free(value);
    }
    fclose(in);
    in = fopen("input/samples.csv", "r");
    value = read_line(in);
    int columns[15], column_count = 0;
    char *name = strtok(value, ",");
    while (name) {
        columns[column_count++] = variable_id(network, name);
        name = strtok(NULL, ",");
    }
    free(value);
    out->samples = calloc(2000, sizeof(Assignment));
    while ((value = read_line(in))) {
        Assignment *sample = &out->samples[out->sample_count++];
        char *token = strtok(value, ",");
        for (int c = 0; c < column_count; ++c) {
            int v = columns[c];
            sample->values[v] = state_id(network, v, token);
            token = strtok(NULL, ",");
        }
        free(value);
    }
    fclose(in);
    in = fopen("input/queries.txt", "r");
    while ((value = read_line(in)))
        out->queries[out->query_count++] = value;
    fclose(in);
    in = fopen("input/params.txt", "r");
    for (int i = 0; i < network->count + 5; ++i)
        out->settings[i] = read_line(in);
    fclose(in);
    return out;
}
