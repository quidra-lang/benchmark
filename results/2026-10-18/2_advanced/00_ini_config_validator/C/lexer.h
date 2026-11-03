#ifndef LEXER_H
#define LEXER_H
#include "main.h"

/* Input cannot contain this byte; it preserves an escaped dollar until expansion. */
#define LITERAL_DOLLAR '\1'
typedef struct { char *text; bool quoted; } Segment;
VECTOR(Segment, Segments);
typedef struct { int number; Segments segments; char *code, *message; } LogicalLine;
VECTOR(LogicalLine, LogicalLines);
LogicalLines lex_document(const char *text);
#endif
