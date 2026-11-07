#include "collector.h"
Config read_config(void) {
    Config config = {0};
    FILE *file = fopen("input/config.txt", "r");
    char *line;
    while ((line = read_line(file))) {
        char *word = strtok(line, " ");
        if (!strcmp(word, "HEAP"))
            config.heap = atoi(strtok(NULL, " "));
        else if (!strcmp(word, "COLLECTOR")) {
            Collector *collector = &config.collectors[config.collector_count++];
            strcpy(collector->name, strtok(NULL, " "));
            char *name = strtok(NULL, " ");
            for (int i = 0; i < 5; ++i)
                if (!strcmp(name, type_name((CollectorType)i)))
                    collector->type = (CollectorType)i;
            if (collector->type == GENERATIONAL) {
                collector->young = atoi(strtok(NULL, " "));
                collector->promotion_age = atoi(strtok(NULL, " "));
            }
        } else if (!strcmp(word, "MAPS")) {
            while ((word = strtok(NULL, " ")))
                strcpy(config.maps[config.map_count++], word);
        } else if (!strcmp(word, "MMU")) {
            while ((word = strtok(NULL, " ")))
                config.windows[config.window_count++] = atoi(word);
        } else
            config.width = atoi(strtok(NULL, " "));
        free(line);
    }
    fclose(file);
    return config;
}
static bool number_token(const char *token) {
    size_t size = strlen(token);
    if (!size || size > 4 || (size > 1 && token[0] == '0'))
        return false;
    for (size_t i = 0; i < size; ++i)
        if (token[i] < '0' || token[i] > '9')
            return false;
    return true;
}
static bool label_token(const char *token) {
    size_t size = strlen(token);
    if (!size || size > 16)
        return false;
    for (size_t i = 0; i < size; ++i) {
        char c = token[i];
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'))
            return false;
    }
    return true;
}
Script read_commands(void) {
    Script script = {.items = calloc(5000, sizeof(Command))};
    FILE *file = fopen("input/mutator.txt", "r");
    char *line;
    const char *forms[] = {"nn", "r", "nn", "n", "nnr", "nr", "l"};
    while ((line = read_line(file))) {
        Command *command = &script.items[script.count++];
        command->line = script.count;
        command->kind = -1;
        char *fields[101];
        int count = 1;
        fields[0] = line;
        for (char *cursor = line; *cursor; ++cursor)
            if (*cursor == ' ') {
                *cursor = 0;
                fields[count++] = cursor + 1;
            }
        for (int k = 0; k < 7; ++k)
            if (!strcmp(fields[0], kind_name(k)))
                command->kind = k;
        bool valid = command->kind >= 0 && count == (int)strlen(forms[command->kind]) + 1;
        if (valid) {
            const char *form = forms[command->kind];
            for (int i = 0; form[i]; ++i) {
                const char *value = fields[i + 1];
                bool matches = form[i] == 'l'   ? label_token(value)
                               : form[i] == 'r' ? (!strcmp(value, "-") || number_token(value))
                                                : number_token(value);
                if (!matches) {
                    valid = false;
                    break;
                }
                if (form[i] == 'l')
                    strcpy(command->label, value);
                else
                    command->args[i] = !strcmp(value, "-") ? -1 : atoi(value);
            }
        }
        if (!valid)
            command->error = "syntax";
        else if ((command->kind == ALLOC && (command->args[0] > 6 || command->args[1] > 24)) ||
                 (command->kind == POP && command->args[0] == 0))
            command->error = "range";
        free(line);
    }
    fclose(file);
    return script;
}
