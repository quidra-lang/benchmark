#ifndef INTERPOLATE_H
#define INTERPOLATE_H
#include "main.h"

/* Results have the same indices as configuration; NULL is expansion failure. */
char **expand_configuration(Configuration configuration, Diagnostics *diagnostics);
#endif
