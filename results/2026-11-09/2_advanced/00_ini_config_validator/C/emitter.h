#ifndef EMITTER_H
#define EMITTER_H
#include "schema.h"

char *string_notation(const char *text);
char *value_notation(Value value);
const char *shown(const OutputKey *output);
void write_outputs(Profiles profiles, Diffs diffs);
#endif
