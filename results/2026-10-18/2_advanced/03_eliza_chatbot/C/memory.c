#include "eliza.h"

bool memory_store(Memory *memory,const char *prefix,const char *keyword,const char *text) {
    if (strings_contains(memory->texts,text)) { strings_add(&memory->log,format("%s SKIP %s %s",prefix,keyword,text)); return false; }
    if (memory->texts.count==memory->capacity) { strings_add(&memory->log,format("%s DROP %s",prefix,memory->texts.data[0])); memmove(memory->texts.data,memory->texts.data+1,(size_t)(--memory->texts.count)*sizeof(*memory->texts.data)); }
    strings_add(&memory->texts,text); strings_add(&memory->log,format("%s STORE %s %s",prefix,keyword,text)); return true;
}
char *memory_recall(Memory *memory,const char *prefix) {
    char *text=memory->texts.data[0]; memmove(memory->texts.data,memory->texts.data+1,(size_t)(--memory->texts.count)*sizeof(*memory->texts.data)); strings_add(&memory->log,format("%s RECALL %s",prefix,text)); return text;
}
void memory_clear(Memory *memory,const char *prefix) { if (memory->texts.count) { strings_add(&memory->log,format("%s CLEAR %d",prefix,memory->texts.count)); memory->texts.count=0; } }
