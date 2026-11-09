#ifndef POLICY_H
#define POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
typedef struct MemoryBlock MemoryBlock;
typedef struct {
    MemoryBlock *head;
} Memory;
extern Memory permanent;
extern Memory *memory;
void *allocate(size_t size);
void clear_memory(Memory *pool);
char *copy_text(const char *text), *substring(const char *text, size_t length),
    *format(const char *pattern, ...);
#define VECTOR(Name, Type)                                                                         \
    typedef struct {                                                                               \
        Type *items;                                                                               \
        size_t count, capacity;                                                                    \
    } Name;                                                                                        \
    static inline void Name##_add(Name *list, Type item) {                                         \
        if (list->count == list->capacity) {                                                       \
            size_t capacity = list->capacity ? list->capacity * 2 : 8;                             \
            Type *items = allocate(capacity * sizeof(Type));                                       \
            if (list->count)                                                                       \
                memcpy(items, list->items, list->count * sizeof(Type));                            \
            list->items = items;                                                                   \
            list->capacity = capacity;                                                             \
        }                                                                                          \
        list->items[list->count++] = item;                                                         \
    }
VECTOR(Names, char *)
Names split(const char *text, const char *separator), read_lines(const char *path);
char *join(Names values, const char *separator), *trim(const char *text);
typedef enum { V_INTEGER, V_STRING, V_BOOLEAN, V_BAG, V_ERROR } ValueKind;
typedef struct {
    ValueKind kind;
    int integer;
    bool boolean;
    char *string;
    Names bag;
} Value;
Value number_value(int n), word_value(char *s), bool_value(bool b), bag_value(Names a),
    error_value(char *s);
VECTOR(Values, Value)
typedef struct {
    char *name;
    Value value;
} Attribute;
VECTOR(Attributes, Attribute)
Value *attribute(Attributes values, const char *name);
void set_attribute(Attributes *values, char *name, Value value);
typedef struct Expression Expression;
VECTOR(Expressions, Expression *)
struct Expression {
    char *operation;
    Value literal;
    Expressions arguments;
};
Expression *parse_expression(const char *source);
typedef struct {
    char *reference, *operation;
    bool mandatory;
    Expression *literal;
} Clause;
VECTOR(Alternative, Clause)
VECTOR(TargetLine, Alternative)
VECTOR(Targets, TargetLine)
typedef struct {
    char *name;
    Expression *expression;
} Argument;
VECTOR(Arguments, Argument)
typedef struct {
    char *effect, *identifier;
    Arguments arguments;
} Attachment;
VECTOR(Attachments, Attachment)
typedef struct Element Element;
VECTOR(Elements, Element *)
struct Element {
    char *kind, *identifier, *behavior;
    Element *parent;
    int index;
    Elements children;
    Targets targets;
    Expression *condition;
    Attachments obligations, advice;
};
typedef struct {
    Elements elements;
    Element *root;
} Policies;
Policies read_policies(void);
typedef uint64_t Roles;
typedef struct {
    bool days[366];
} Days;
typedef struct {
    int role;
    char *action, *type;
} Grant;
typedef struct {
    char *name;
    int cardinality;
    Roles roles;
} Constraint;
typedef struct {
    char *user;
    int role, first, last;
} Assignment;
typedef struct {
    int number;
    char *keyword, *message;
} Diagnostic;
typedef struct {
    char *roles[40];
    int role_count;
    Roles inherits[40];
    Grant grants[300];
    int grant_count;
    Constraint ssd[300], dsd[300];
    int ssd_count, dsd_count;
    Assignment assignments[300];
    int assignment_count;
    Diagnostic diagnostics[300];
    int diagnostic_count;
} RBAC;
Roles bit(int role), closure(const RBAC *rbac, Roles source),
    assigned(const RBAC *rbac, const char *user, int day),
    authorized(const RBAC *rbac, const char *user, int day);
int cardinality(Roles roles), find_role(const RBAC *rbac, const char *name);
Names role_names(const RBAC *rbac, Roles source);
bool permits(const RBAC *rbac, int role, const char *action, const char *type);
void read_rbac(RBAC *rbac);
typedef enum { D_PERMIT, D_DENY, D_NA, D_IP, D_ID, D_IDP } Decision;
bool definite(Decision d), indeterminate(Decision d);
char *decision_name(Decision d), *notation(Decision d, const char *reason);
typedef enum { T_MATCH, T_NO_MATCH, T_INDETERMINATE } TargetKind;
typedef struct {
    TargetKind kind;
    char *reason;
} TargetResult;
char *target_name(TargetKind kind);
typedef struct Evaluation Evaluation;
typedef enum { C_SKIPPED, C_CHECKED, C_EVALUATED } ChildKind;
typedef struct {
    ChildKind kind;
    TargetResult checked;
    Evaluation *evaluation;
} ChildState;
VECTOR(ChildStates, ChildState)
typedef struct {
    char *identifier, *text;
} Item;
VECTOR(Items, Item)
struct Evaluation {
    Element *element;
    TargetResult target;
    Decision decision;
    char *reason;
    Element *decisive;
    Value condition;
    ChildStates children;
    Items obligations, advice;
};
typedef struct {
    Decision decision;
    char *reason;
    ChildStates children;
} Combined;
typedef struct {
    Attributes values;
    char *coverage;
} Evaluator;
TargetResult evaluate_target(Evaluator *evaluator, Element *element);
Evaluation *evaluate(Evaluator *evaluator, Element *element);
Combined combine(Evaluator *evaluator, Element *element);
typedef struct {
    char *reference;
    Values candidates;
} Domain;
VECTOR(Domains, Domain)
Attributes domain_point(Domains domains, int ordinal);
int point_count(Domains domains);
char *day_notation(Days days);
Element *blocker(Element *rule, const Decision standalone[100]);
Element *conflict_winner(Element *policy, Element *earlier, Element *later);
#endif
