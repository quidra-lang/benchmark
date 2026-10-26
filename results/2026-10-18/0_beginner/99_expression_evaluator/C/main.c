#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char names[32][32];
    long long values[32];
    int count;
} Variables;

typedef struct {
    char tokens[128][32];
    int count, position;
    char error[128];
    Variables *variables;
} Parser;

long long sum(Parser *p);

void tokenize(Parser *p, const char *line) {
    p->count = 0;
    p->position = 0;
    p->error[0] = 0;
    for (int i = 0; line[i];) {
        if (line[i] == ' ') {
            i++;
            continue;
        }
        int length = 0;
        if (line[i] >= '0' && line[i] <= '9') {
            while (line[i] >= '0' && line[i] <= '9')
                p->tokens[p->count][length++] = line[i++];
        } else if (line[i] >= 'a' && line[i] <= 'z') {
            while (line[i] >= 'a' && line[i] <= 'z')
                p->tokens[p->count][length++] = line[i++];
        } else {
            p->tokens[p->count][length++] = line[i++];
        }
        p->tokens[p->count++][length] = 0;
    }
}

long long unary(Parser *p) {
    const char *token = p->tokens[p->position++];
    if (strcmp(token, "-") == 0)
        return -unary(p);
    if (strcmp(token, "(") == 0) {
        long long value = sum(p);
        if (!p->error[0])
            p->position++;
        return value;
    }
    if (token[0] >= '0' && token[0] <= '9')
        return strtoll(token, NULL, 10);
    for (int i = 0; i < p->variables->count; i++)
        if (strcmp(p->variables->names[i], token) == 0)
            return p->variables->values[i];
    snprintf(p->error, sizeof p->error, "undefined variable %s", token);
    return 0;
}

long long product(Parser *p) {
    long long value = unary(p);
    while (!p->error[0] && p->position < p->count &&
           (strcmp(p->tokens[p->position], "*") == 0 || strcmp(p->tokens[p->position], "/") == 0)) {
        char operation = p->tokens[p->position++][0];
        long long right = unary(p);
        if (p->error[0])
            return 0;
        if (operation == '/' && right == 0) {
            strcpy(p->error, "division by zero");
            return 0;
        }
        value = operation == '*' ? value * right : value / right;
    }
    return value;
}

long long sum(Parser *p) {
    long long value = product(p);
    while (!p->error[0] && p->position < p->count &&
           (strcmp(p->tokens[p->position], "+") == 0 || strcmp(p->tokens[p->position], "-") == 0)) {
        char operation = p->tokens[p->position++][0];
        long long right = product(p);
        if (p->error[0])
            return 0;
        value = operation == '+' ? value + right : value - right;
    }
    return value;
}

int main(void) {
    const char *lines[] = {"width = 12", "height = width - 5", "area = width * height", "(area + 6) / 4",
        "shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus", "volume = area * depth",
        "width = (width+3)*-(2-4)", "width * shift - height"};
    Variables variables = {0};
    for (int line = 0; line < 9; line++) {
        Parser p;
        p.variables = &variables;
        tokenize(&p, lines[line]);
        int assignment = p.count > 1 && strcmp(p.tokens[1], "=") == 0;
        if (assignment)
            p.position = 2;
        long long value = sum(&p);
        if (p.error[0]) {
            printf("error: %s\n", p.error);
        } else if (assignment) {
            int i = 0;
            while (i < variables.count && strcmp(variables.names[i], p.tokens[0]))
                i++;
            if (i == variables.count) {
                strcpy(variables.names[i], p.tokens[0]);
                variables.count++;
            }
            variables.values[i] = value;
            printf("%s = %lld\n", p.tokens[0], value);
        } else {
            printf("%lld\n", value);
        }
    }
    return 0;
}
