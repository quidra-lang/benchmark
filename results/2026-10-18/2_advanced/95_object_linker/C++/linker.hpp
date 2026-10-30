#ifndef OBJECT_LINKER_HPP
#define OBJECT_LINKER_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
struct Object;
struct Symbol;
struct Relocation;
struct OutputSection;
struct Component;
struct Resolution;
struct Section {
    std::string name, reason;
    int64_t alignment = 1, size = 0, address = 0;
    std::vector<uint8_t> data;
    Object *object = nullptr;
    std::vector<std::unique_ptr<Relocation>> relocations;
    OutputSection *output = nullptr;
    bool live = false;
    Component *merged = nullptr;
    std::map<int64_t, int64_t> string_offsets;
};
struct Symbol {
    std::string name, binding, location;
    Section *section = nullptr;
    int64_t offset = 0, size = 0, alignment = 1;
    Object *object = nullptr;
};
struct Relocation {
    Section *section;
    int64_t offset, addend;
    std::string type;
    Symbol *symbol;
};
struct COMDATGroup {
    std::string signature;
    std::vector<Section *> sections;
};
struct Object {
    std::string name;
    int rank = 0;
    std::vector<std::unique_ptr<Section>> sections;
    std::vector<std::unique_ptr<Symbol>> symbols;
    std::vector<COMDATGroup> groups;
    std::map<std::string, Section *> section_names;
    std::map<std::string, Symbol *> symbol_names;
};
bool belongs(const std::string &, const std::string &);
std::vector<std::string> read_lines(const std::string &);
std::vector<std::string> words(const std::string &);
int64_t number(const std::string &);
std::unique_ptr<Object> parse_object(const std::vector<std::string> &, const std::string &);
struct ArchiveMember {
    std::unique_ptr<Object> object;
    std::vector<std::string> exports;
    bool loaded = false;
};
struct Archive {
    std::string name;
    std::vector<ArchiveMember> members;
};
struct Extraction {
    std::string object, reason, referrer;
};
std::unique_ptr<Archive> read_archive(const std::string &);
int scan_archive(Archive &, const std::function<bool(const std::string &)> &,
                 const std::function<std::string(const std::string &)> &,
                 const std::function<void(Object *)> &, const std::function<void(Extraction)> &);
struct Resolution {
    std::string name, kind, definer = "-";
    Symbol *definition = nullptr;
    std::vector<Symbol *> strong, weak, common, references;
    std::vector<std::string> referrers;
    int64_t size = 0, alignment = 1, address = 0;
    bool live = false;
};
Resolution resolve_name(const std::string &, const std::vector<Symbol *> &, bool);
std::vector<std::string> strong_definers(const Resolution &, bool);
struct Segment {
    std::string name;
    int64_t base = 0, length = 0, fill = 0, physical = 0, file_size = 0, memory_size = 0, used = 0;
    std::vector<std::unique_ptr<OutputSection>> sections;
    std::vector<uint8_t> image;
};
struct OutputSection {
    std::string name;
    Segment *segment = nullptr;
    std::vector<std::unique_ptr<Component>> components;
    int64_t address = 0, size = 0, alignment = 1;
};
struct Component {
    std::string kind, target;
    int64_t size = 0, alignment = 1, address = 0, original_size = 0;
    Section *section = nullptr;
    Resolution *common = nullptr;
    std::vector<uint8_t> data;
    int string_sections = 0, strings = 0, unique = 0;
};
int64_t aligned(int64_t, int64_t);
OutputSection *output_for(Section *, const std::vector<OutputSection *> &);
void place_segment(Segment &);
extern const std::array<std::string, 7> relocation_types;
int relocation_width(const std::string &);
int64_t modulo(int64_t, int64_t);
int64_t floor_divide(int64_t, int64_t);
struct RelocationField {
    int64_t value, field;
    bool valid;
};
RelocationField relocation_field(const std::string &, int64_t, int64_t, int64_t, int64_t);
bool unpaired(const std::vector<std::unique_ptr<Relocation>> &, size_t);
void little_endian(std::vector<uint8_t> &, size_t, int64_t, int);
struct ScriptDefinition {
    std::string name, expression;
};
struct Input {
    std::string kind;
    std::vector<std::string> names;
};
struct Script {
    std::string entry, checksum_segment, checksum_symbol;
    bool gc = false;
    std::vector<std::unique_ptr<Segment>> segments;
    std::vector<OutputSection *> outputs;
    std::map<std::string, Segment *> segment_names;
    std::map<std::string, OutputSection *> output_names;
    std::vector<std::pair<std::string, std::string>> loads;
    std::set<std::string> keep, sort, wrap, script_names;
    std::vector<ScriptDefinition> definitions;
    std::vector<Input> inputs;
};
struct COMDATRecord {
    Object *keeper;
    std::vector<std::string> discarders;
};
struct Linker {
    Script script;
    std::vector<std::unique_ptr<Object>> direct_objects;
    std::vector<Object *> objects;
    std::map<std::string, std::vector<Symbol *>> entries;
    std::map<std::string, std::unique_ptr<Archive>> archives;
    std::vector<Extraction> extractions;
    std::map<std::string, COMDATRecord> comdat;
    std::vector<std::string> comdat_order;
    std::map<std::string, Resolution> names;
    std::map<std::string, int> orphans;
    std::map<OutputSection *, std::set<std::string>> veneers;
    std::map<OutputSection *, std::map<std::string, Component *>> veneer_components;
    std::map<std::string, int64_t> script_values;
    std::vector<std::string> relocation_lines, relocation_diagnostics;
    std::map<std::string, std::map<std::string, int>> relocation_counts;
    void read_script();
    void load(Object *);
    bool defined(const std::string &) const;
    bool undefined(const std::string &) const;
    std::string referrer(const std::string &) const;
    int scan(const std::string &);
    void load_inputs();
    void resolve();
    void collect();
    std::vector<std::unique_ptr<Component>> components(OutputSection *);
    int64_t section_value(Section *, int64_t) const;
    std::optional<int64_t> name_value(const std::string &) const;
    std::optional<int64_t> symbol_value(Symbol *) const;
    bool far_call(const Relocation &) const;
    void layout();
    void load_addresses();
    void define_script_symbols();
    void relocate();
    void build_images();
    int64_t entry_address() const;
    std::vector<std::string> diagnostics() const;
    void write_reports() const;
};
#endif
