#include "timezone.h"

static int instance_order(const void *a, const void *b) {
    const Instance *first = a, *second = b;
    if (first->nominal != second->nominal) return first->nominal < second->nominal ? -1 : 1;
    return first->rule->number - second->rule->number;
}
Instances instance_sequence(Rule *const *rules, int count) {
    Instances instances = {0};
    for (int i = 0; i < count; ++i) instances.count += rules[i]->to - rules[i]->from + 1;
    instances.items = allocate((size_t)instances.count * sizeof(Instance));
    int position = 0;
    for (int i = 0; i < count; ++i) for (int year = rules[i]->from; year <= rules[i]->to; ++year) instances.items[position++] = (Instance){rules[i], day_spec_value(rules[i]->day, year, rules[i]->month) * 86400 + rules[i]->at};
    if (instances.count > 1) qsort(instances.items, (size_t)instances.count, sizeof(Instance), instance_order);
    return instances;
}
Integer adjustment(char type, Integer offset, Integer save) { return type == 'u' ? 0 : type == 's' ? offset : offset + save; }
LineRun run_instances(Instances instances, Integer offset, Integer start, const Until *until) {
    LineRun run = {0};
    run.end = POS_INFINITY;
    run.applied = malloc((size_t)(instances.count ? instances.count : 1) * sizeof(Applied));
    if (!run.applied) exit(EXIT_FAILURE);
    Integer save = 0;
    for (int i = 0; i < instances.count; ++i) {
        Rule *rule = instances.items[i].rule;
        Integer time = instances.items[i].nominal - adjustment(rule->type, offset, save);
        if (until && time >= until->value - adjustment(until->type, offset, save)) break;
        if (time <= start) run.pre_start = rule;
        else run.applied[run.count++] = (Applied){time, rule};
        save = rule->save;
    }
    if (until) run.end = until->value - adjustment(until->type, offset, save);
    return run;
}
char *abbreviation(const char *text, Integer save, const char *letter) {
    const char *slash = strchr(text, '/');
    if (slash) return save ? format("%s", slash + 1) : slice(text, 0, (size_t)(slash - text));
    const char *placeholder = strstr(text, "%s");
    return placeholder ? format("%s%s%s", slice(text, 0, (size_t)(placeholder - text)), letter, placeholder + 2) : (char *)text;
}
