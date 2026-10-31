#include "policy.h"
bool definite(Decision d) { return d == D_PERMIT || d == D_DENY; }
bool indeterminate(Decision d) { return d == D_IP || d == D_ID || d == D_IDP; }
char *decision_name(Decision d) {
    static char *names[] = {"PERMIT",           "DENY",
                            "NOT_APPLICABLE",   "INDETERMINATE{P}",
                            "INDETERMINATE{D}", "INDETERMINATE{DP}"};
    return names[d];
}
char *notation(Decision d, const char *reason) {
    return indeterminate(d) ? format("%s (%s)", decision_name(d), reason) : decision_name(d);
}
char *target_name(TargetKind kind) {
    return kind == T_MATCH ? "MATCH" : kind == T_NO_MATCH ? "NO_MATCH" : "INDETERMINATE";
}
Combined combine(Evaluator *evaluator, Element *element) {
    Combined out = {.decision = D_NA};
    for (size_t i = 0; i < element->children.count; ++i)
        ChildStates_add(&out.children, (ChildState){0});
    char *algorithm = element->behavior;
    if (!strcmp(algorithm, "only-one-applicable")) {
        int matched = -1;
        for (size_t i = 0; i < element->children.count; ++i) {
            TargetResult checked = evaluate_target(evaluator, element->children.items[i]);
            out.children.items[i] = (ChildState){.kind = C_CHECKED, .checked = checked};
            if (checked.kind == T_INDETERMINATE) {
                out.decision = D_IDP;
                out.reason = checked.reason;
                return out;
            }
            if (checked.kind == T_MATCH) {
                if (matched >= 0) {
                    out.decision = D_IDP;
                    out.reason = format("multiple applicable %s %s",
                                        element->children.items[matched]->identifier,
                                        element->children.items[i]->identifier);
                    return out;
                }
                matched = (int)i;
            }
        }
        if (matched >= 0) {
            Evaluation *result = evaluate(evaluator, element->children.items[matched]);
            out.children.items[matched] = (ChildState){.kind = C_EVALUATED, .evaluation = result};
            out.decision = result->decision;
            out.reason = result->reason;
        }
        return out;
    }
    bool present[6] = {0};
    char *first_error = NULL;
    for (size_t i = 0; i < element->children.count; ++i) {
        Evaluation *result = evaluate(evaluator, element->children.items[i]);
        out.children.items[i] = (ChildState){.kind = C_EVALUATED, .evaluation = result};
        Decision d = result->decision;
        present[d] = true;
        if (indeterminate(d) && !first_error)
            first_error = result->reason;
        bool stop =
            (!strcmp(algorithm, "first-applicable") && d != D_NA) ||
            ((!strcmp(algorithm, "deny-overrides") || !strcmp(algorithm, "permit-unless-deny")) &&
             d == D_DENY) ||
            ((!strcmp(algorithm, "permit-overrides") || !strcmp(algorithm, "deny-unless-permit")) &&
             d == D_PERMIT);
        if (stop) {
            out.decision = d;
            out.reason = result->reason;
            return out;
        }
    }
    if (!strcmp(algorithm, "deny-unless-permit"))
        out.decision = D_DENY;
    else if (!strcmp(algorithm, "permit-unless-deny"))
        out.decision = D_PERMIT;
    else if (!strcmp(algorithm, "deny-overrides")) {
        if (present[D_IDP] || (present[D_ID] && (present[D_IP] || present[D_PERMIT])))
            out.decision = D_IDP;
        else if (present[D_ID])
            out.decision = D_ID;
        else if (present[D_PERMIT])
            out.decision = D_PERMIT;
        else if (present[D_IP])
            out.decision = D_IP;
    } else if (!strcmp(algorithm, "permit-overrides")) {
        if (present[D_IDP] || (present[D_IP] && (present[D_ID] || present[D_DENY])))
            out.decision = D_IDP;
        else if (present[D_IP])
            out.decision = D_IP;
        else if (present[D_DENY])
            out.decision = D_DENY;
        else if (present[D_ID])
            out.decision = D_ID;
    }
    if (indeterminate(out.decision))
        out.reason = first_error;
    return out;
}
