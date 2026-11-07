#include "policy.h"
Policies read_policies(void) {
    Policies out = {0};
    Element *stack[8];
    int depth = 0;
    Names lines = read_lines("input/policies.txt");
    for (size_t i = 0; i < lines.count; ++i) {
        char *source = trim(lines.items[i]);
        if (!*source || *source == '#')
            continue;
        char *space = strchr(source, ' '),
             *keyword = space ? substring(source, (size_t)(space - source)) : source,
             *rest = space ? space + 1 : "";
        if (!strcmp(keyword, "POLICYSET") || !strcmp(keyword, "POLICY") ||
            !strcmp(keyword, "RULE")) {
            Names f = split(rest, " ");
            Element *e = allocate(sizeof(*e));
            e->kind = !strcmp(keyword, "RULE")     ? "rule"
                      : !strcmp(keyword, "POLICY") ? "policy"
                                                   : "policyset";
            e->identifier = f.items[0];
            e->behavior = f.items[1];
            e->index = (int)out.elements.count;
            if (depth) {
                e->parent = stack[depth - 1];
                Elements_add(&e->parent->children, e);
            }
            Elements_add(&out.elements, e);
            stack[depth++] = e;
        } else if (!strcmp(keyword, "END"))
            --depth;
        else if (!strcmp(keyword, "CONDITION"))
            stack[depth - 1]->condition = parse_expression(rest);
        else if (!strcmp(keyword, "TARGET")) {
            TargetLine target = {0};
            Names alternatives = split(rest, " | ");
            for (size_t a = 0; a < alternatives.count; ++a) {
                Alternative clauses = {0};
                Names parts = split(alternatives.items[a], " & ");
                for (size_t j = 0; j < parts.count; ++j) {
                    Names f = split(parts.items[j], " ");
                    char *reference = f.items[0];
                    size_t length = strlen(reference);
                    bool mandatory = reference[length - 1] == '!';
                    if (mandatory)
                        reference[length - 1] = '\0';
                    Alternative_add(&clauses, (Clause){reference, f.items[1], mandatory,
                                                       parse_expression(f.items[2])});
                }
                TargetLine_add(&target, clauses);
            }
            Targets_add(&stack[depth - 1]->targets, target);
        } else {
            char *first = strchr(rest, ' '), *second = strchr(first + 1, ' ');
            Attachment item = {.effect = substring(rest, (size_t)(first - rest)),
                               .identifier =
                                   second ? substring(first + 1, (size_t)(second - first - 1))
                                          : first + 1};
            if (second) {
                Names parts = split(second + 1, ";");
                for (size_t j = 0; j < parts.count; ++j) {
                    char *part = trim(parts.items[j]), *equal = strchr(part, '=');
                    Arguments_add(&item.arguments,
                                  (Argument){substring(part, (size_t)(equal - part)),
                                             parse_expression(equal + 1)});
                }
            }
            Attachments_add(!strcmp(keyword, "OBLIGATION") ? &stack[depth - 1]->obligations
                                                           : &stack[depth - 1]->advice,
                            item);
        }
    }
    out.root = out.elements.items[0];
    return out;
}
