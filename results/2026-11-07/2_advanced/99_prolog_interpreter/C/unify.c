#include "prolog.h"
static void bind(Trail *trail,Term *variable,Term *value) {
    if(trail->count==trail->capacity) {
        int capacity=trail->capacity?trail->capacity*2:64;
        Term **data=realloc(trail->variables,(size_t)capacity*sizeof *data);
        if(!data)exit(EXIT_FAILURE);
        trail->variables=data;
        trail->capacity=capacity;
    }
    trail->variables[trail->count++]=variable;
    variable->binding=value;
}
int unify(Trail *trail,Term *a,Term *b) {
    a=dereference(a);
    b=dereference(b);
    if(a==b)return 1;
    if(a->kind==TERM_VARIABLE) {
        bind(trail,a,b);
        return 1;
    }
    if(b->kind==TERM_VARIABLE) {
        bind(trail,b,a);
        return 1;
    }
    if(a->kind!=b->kind)return 0;
    if(a->kind==TERM_INTEGER)return a->integer==b->integer;
    if(strcmp(a->name,b->name))return 0;
    if(a->kind==TERM_ATOM)return 1;
    if(a->arity!=b->arity)return 0;
    for(int i=0;i<a->arity;++i)if(!unify(trail,a->args[i],b->args[i]))return 0;
    return 1;
}
void undo(Trail *trail,int mark) {
    while(trail->count>mark)trail->variables[--trail->count]->binding=NULL;
}
int identical(Term *a,Term *b) {
    a=dereference(a);
    b=dereference(b);
    if(a==b)return 1;
    if(a->kind!=b->kind||a->kind==TERM_VARIABLE)return 0;
    if(a->kind==TERM_INTEGER)return a->integer==b->integer;
    if(strcmp(a->name,b->name))return 0;
    if(a->kind==TERM_ATOM)return 1;
    if(a->arity!=b->arity)return 0;
    for(int i=0;i<a->arity;++i)if(!identical(a->args[i],b->args[i]))return 0;
    return 1;
}
