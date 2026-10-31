#ifndef OBJECT_LINKER_H
#define OBJECT_LINKER_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
void *ml_alloc(size_t);
void *ml_grow(void *, int *, size_t, int);
char *ml_text(const char *, size_t);
char *ml_format(const char *, ...);
void ml_cleanup(void);
#define PUSH(v, x)                                                                                 \
    do {                                                                                           \
        if ((v).count == (v).capacity)                                                             \
            (v).items = ml_grow((v).items, &(v).capacity, sizeof(*(v).items), (v).count);          \
        (v).items[(v).count++] = (x);                                                              \
    } while (0)
typedef struct {
    char *items;
    int count, capacity;
} Text;
void text_add(Text *, const char *);
void text_char(Text *, char);
char *text_value(Text *);
bool equal(const char *, const char *);
bool word_in(const char *, const char *);
typedef struct {
    char **items;
    int count, capacity;
} StringList;
typedef struct {
    uint8_t *items;
    int count, capacity;
} Bytes;
StringList read_lines(const char *);
StringList words(const char *);
int64_t number(const char *);
bool belongs(const char *, const char *);
typedef struct Object Object;
typedef struct Symbol Symbol;
typedef struct Section Section;
typedef struct Relocation Relocation;
typedef struct OutputSection OutputSection;
typedef struct Component Component;
typedef struct Resolution Resolution;
typedef struct Name Name;
typedef struct Segment Segment;
typedef struct Linker Linker;
typedef struct {
    Object **items;
    int count, capacity;
} ObjectList;
typedef struct {
    Symbol **items;
    int count, capacity;
} SymbolList;
typedef struct {
    Section **items;
    int count, capacity;
} SectionList;
typedef struct {
    Relocation **items;
    int count, capacity;
} RelocationList;
typedef struct {
    OutputSection **items;
    int count, capacity;
} OutputList;
typedef struct {
    Component **items;
    int count, capacity;
} ComponentList;
typedef struct {
    Resolution **items;
    int count, capacity;
} ResolutionList;
typedef struct {
    Name **items;
    int count, capacity;
} NameList;
typedef struct {
    Segment **items;
    int count, capacity;
} SegmentList;
struct Section {
    const char *name;
    const char *reason;
    int64_t alignment, size, address;
    Bytes data;
    Object *object;
    int order;
    RelocationList relocations;
    OutputSection *output;
    bool live;
    Component *merged;
    int64_t *string_offsets;
};
struct Symbol {
    const char *name;
    const char *binding;
    const char *location;
    Section *section;
    int64_t offset, size, alignment;
    Object *object;
    Name *global_name;
};
struct Relocation {
    Section *section;
    int64_t offset, addend;
    const char *type;
    Symbol *symbol;
};
typedef struct {
    const char *signature;
    SectionList sections;
} COMDATGroup;
typedef struct {
    COMDATGroup *items;
    int count, capacity;
} COMDATGroups;
struct Object {
    const char *name;
    int rank;
    SectionList sections;
    SymbolList symbols;
    COMDATGroups groups;
};
Object *parse_object(StringList, const char *);
typedef struct {
    Object *object;
    StringList exports;
    bool loaded;
} ArchiveMember;
typedef struct {
    ArchiveMember **items;
    int count, capacity;
} MemberList;
typedef struct {
    const char *name;
    MemberList members;
} Archive;
typedef struct {
    Archive **items;
    int count, capacity;
} ArchiveList;
typedef struct {
    const char *object;
    const char *reason;
    const char *referrer;
} Extraction;
typedef struct {
    Extraction *items;
    int count, capacity;
} ExtractionList;
Archive *read_archive(const char *);
int scan_archive(Archive *, Linker *);
struct Resolution {
    const char *name;
    const char *kind;
    const char *definer;
    Symbol *definition;
    SymbolList strong, weak, common, references;
    StringList referrers;
    int64_t size, alignment, address;
    bool live;
};
Resolution *resolve_name(const char *, SymbolList, bool);
StringList strong_definers(Resolution *, bool);
struct Segment {
    const char *name;
    int64_t base, length, fill, physical, file_size, memory_size, used;
    OutputList sections;
    Bytes image;
};
struct OutputSection {
    const char *name;
    Segment *segment;
    ComponentList components;
    int64_t address, size, alignment;
    NameList veneer_targets;
};
struct Component {
    const char *kind;
    int64_t size, alignment, address, original_size;
    Section *section;
    Resolution *common;
    Name *target;
    Bytes data;
    int string_sections, strings, unique;
};
int64_t aligned(int64_t, int64_t);
OutputSection *output_for(Section *, OutputList);
void place_segment(Segment *);
extern const char *relocation_types[7];
int relocation_width(const char *);
int64_t modulo(int64_t, int64_t);
int64_t floor_divide(int64_t, int64_t);
typedef struct {
    int64_t value, field;
    bool valid;
} RelocationField;
RelocationField relocation_field(const char *, int64_t, int64_t, int64_t, int64_t);
bool unpaired(RelocationList, int);
void little_endian(Bytes, int, int64_t, int);
typedef struct {
    const char *name;
    const char *expression;
} ScriptDefinition;
typedef struct {
    ScriptDefinition *items;
    int count, capacity;
} DefinitionList;
typedef struct {
    const char *kind;
    StringList names;
} Input;
typedef struct {
    Input *items;
    int count, capacity;
} InputList;
typedef struct {
    Segment *source;
    Segment *target;
} Load;
typedef struct {
    Load *items;
    int count, capacity;
} LoadList;
typedef struct {
    const char *entry;
    bool gc;
    SegmentList segments;
    OutputList outputs;
    LoadList loads;
    StringList keep, sort, wrap;
    DefinitionList definitions;
    Segment *checksum_segment;
    const char *checksum_symbol;
    InputList inputs;
} Script;
struct Name {
    const char *name;
    SymbolList entries;
    bool script;
    int64_t value;
    Resolution *resolution;
    Name *next;
};
typedef struct {
    const char *signature;
    Object *keeper;
    StringList discarders;
} COMDATRecord;
typedef struct {
    COMDATRecord **items;
    int count, capacity;
} COMDATList;
typedef struct {
    const char *name;
    int count;
} OrphanCount;
typedef struct {
    OrphanCount *items;
    int count, capacity;
} OrphanList;
typedef struct LayoutAllocation {
    void *value;
    struct LayoutAllocation *next;
} LayoutAllocation;
struct Linker {
    Script script;
    ObjectList objects;
    Name *buckets[8192];
    NameList names;
    ArchiveList archives;
    ExtractionList extractions;
    COMDATList comdat;
    OrphanList orphans;
    StringList relocation_lines, relocation_diagnostics;
    int relocation_counts[7][5];
    LayoutAllocation *layout_allocations;
};
Name *find_name(Linker *, const char *, bool);
void load_object(Linker *, Object *);
bool undefined_name(Linker *, const char *);
const char *referrer(Linker *, const char *);
void *layout_alloc(Linker *, size_t);
void layout_clear(Linker *);
#endif
