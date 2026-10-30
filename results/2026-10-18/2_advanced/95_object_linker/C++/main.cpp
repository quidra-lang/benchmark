#include "linker.hpp"
static std::string hex_value(int64_t value, int width = 8, bool upper = false) {
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    std::string result(static_cast<size_t>(width), '0');
    for (int i = width - 1; i >= 0; --i) {
        result[static_cast<size_t>(i)] = digits[value % 16];
        value /= 16;
    }
    while (value) {
        result.insert(result.begin(), digits[value % 16]);
        value /= 16;
    }
    return result;
}
static bool word_in(const std::string &list, const std::string &value) {
    std::vector<std::string> names = words(list);
    return std::find(names.begin(), names.end(), value) != names.end();
}

static std::string joined(const std::vector<std::string> &values, const std::string &separator,
                          const std::string &empty = "-") {
    if (values.empty())
        return empty;
    std::string result;
    for (size_t i = 0; i < values.size(); ++i) {
        if (i)
            result += separator;
        result += values[i];
    }
    return result;
}
void Linker::read_script() {
    for (const std::string &line : read_lines("input/link.txt")) {
        std::vector<std::string> a = words(line);
        if (a[0] == "entry")
            script.entry = a[1];
        else if (a[0] == "gc")
            script.gc = a[1] == "on";
        else if (a[0] == "segment") {
            auto segment = std::make_unique<Segment>();
            segment->name = a[1];
            segment->base = number(a[2]);
            segment->length = number(a[3]);
            segment->fill = number(a[4]);
            Segment *pointer = segment.get();
            script.segment_names[pointer->name] = pointer;
            for (size_t i = 5; i < a.size(); ++i) {
                auto output = std::make_unique<OutputSection>();
                output->name = a[i];
                output->segment = pointer;
                script.outputs.push_back(output.get());
                script.output_names[a[i]] = output.get();
                pointer->sections.push_back(std::move(output));
            }
            script.segments.push_back(std::move(segment));
        } else if (a[0] == "load")
            script.loads.push_back({a[1], a[2]});
        else if (a[0] == "keep")
            script.keep.insert(a[1]);
        else if (a[0] == "sort")
            script.sort.insert(a[1]);
        else if (a[0] == "wrap")
            script.wrap.insert(a[1]);
        else if (a[0] == "define") {
            script.definitions.push_back({a[1], line.substr(line.find(" = ") + 3)});
            script.script_names.insert(a[1]);
        } else if (a[0] == "checksum") {
            script.checksum_segment = a[1];
            script.checksum_symbol = a[2];
        } else
            script.inputs.push_back({a[0], std::vector<std::string>(a.begin() + 1, a.end())});
    }
}
void Linker::load(Object *object) {
    object->rank = static_cast<int>(objects.size());
    for (const COMDATGroup &group : object->groups) {
        auto previous = comdat.find(group.signature);
        if (previous != comdat.end()) {
            for (Section *section : group.sections)
                section->reason = "comdat";
            previous->second.discarders.push_back(object->name);
        } else {
            comdat[group.signature] = {object, {}};
            comdat_order.push_back(group.signature);
        }
    }
    for (const auto &pointer : object->symbols) {
        Symbol &symbol = *pointer;
        if (symbol.binding == "local")
            continue;
        if (symbol.location == "section" && symbol.section->reason == "comdat") {
            symbol.location = "undef";
            symbol.section = nullptr;
        }
        if (symbol.location == "undef") {
            if (script.wrap.count(symbol.name))
                symbol.name = "__wrap_" + symbol.name;
            else if (symbol.name.compare(0, 7, "__real_") == 0 &&
                     script.wrap.count(symbol.name.substr(7)))
                symbol.name = symbol.name.substr(7);
        }
        entries[symbol.name].push_back(&symbol);
    }
    objects.push_back(object);
}
bool Linker::defined(const std::string &name) const {
    if (script.script_names.count(name))
        return true;
    auto found = entries.find(name);
    if (found != entries.end())
        for (Symbol *symbol : found->second)
            if (symbol->location != "undef")
                return true;
    return false;
}
bool Linker::undefined(const std::string &name) const {
    if (defined(name))
        return false;
    if (name == script.entry)
        return true;
    auto found = entries.find(name);
    if (found != entries.end())
        for (Symbol *symbol : found->second)
            if (symbol->binding == "global" && symbol->location == "undef")
                return true;
    return false;
}
std::string Linker::referrer(const std::string &name) const {
    auto found = entries.find(name);
    if (found != entries.end())
        for (Symbol *symbol : found->second)
            if (symbol->location == "undef" && symbol->binding == "global")
                return symbol->object->name;
    return "*entry*";
}
int Linker::scan(const std::string &name) {
    if (!archives.count(name))
        archives[name] = read_archive(name);
    return scan_archive(
        *archives.at(name), [&](const std::string &value) { return undefined(value); },
        [&](const std::string &value) { return referrer(value); },
        [&](Object *object) { load(object); },
        [&](Extraction record) { extractions.push_back(std::move(record)); });
}
void Linker::load_inputs() {
    for (const Input &input : script.inputs) {
        if (input.kind == "object") {
            direct_objects.push_back(
                parse_object(read_lines("input/" + input.names[0]), input.names[0]));
            load(direct_objects.back().get());
        } else if (input.kind == "library")
            scan(input.names[0]);
        else {
            while (true) {
                int count = 0;
                for (const std::string &name : input.names)
                    count += scan(name);
                if (count == 0)
                    break;
            }
        }
    }
}
void Linker::resolve() {
    std::set<std::string> global_names = script.script_names;
    for (const auto &entry : entries)
        global_names.insert(entry.first);
    for (const std::string &name : global_names)
        names[name] = resolve_name(name, entries[name], script.script_names.count(name));
}
void Linker::collect() {
    for (Object *object : objects)
        for (const auto &pointer : object->sections) {
            Section *section = pointer.get();
            if (section->reason == "comdat")
                continue;
            section->output = output_for(section, script.outputs);
            if (!section->output) {
                section->reason = "orphan";
                ++orphans[section->name];
            } else if (!script.gc)
                section->live = true;
        }
    if (!script.gc) {
        for (auto &entry : names)
            if (entry.second.kind == "common")
                entry.second.live = true;
        return;
    }
    std::vector<Section *> queue;
    auto mark = [&](Section *section) {
        if (section && section->reason.empty() && section->output && !section->live) {
            section->live = true;
            queue.push_back(section);
        }
    };
    for (Object *object : objects)
        for (const auto &section : object->sections)
            if (section->output && script.keep.count(section->output->name))
                mark(section.get());
    auto entry = names.find(script.entry);
    if (entry != names.end()) {
        Resolution &resolution = entry->second;
        if (resolution.kind == "global" || resolution.kind == "weak")
            mark(resolution.definition->section);
        else if (resolution.kind == "common")
            resolution.live = true;
    }
    for (size_t head = 0; head < queue.size(); ++head)
        for (const auto &relocation : queue[head]->relocations) {
            Symbol *symbol = relocation->symbol;
            if (symbol->binding == "local")
                mark(symbol->section);
            else {
                Resolution &resolution = names.at(symbol->name);
                if (resolution.kind == "global" || resolution.kind == "weak")
                    mark(resolution.definition->section);
                else if (resolution.kind == "common")
                    resolution.live = true;
            }
        }
    for (Object *object : objects)
        for (const auto &section : object->sections)
            if (section->output && section->reason.empty() && !section->live)
                section->reason = "gc";
}
std::vector<std::unique_ptr<Component>> Linker::components(OutputSection *output) {
    std::vector<Section *> sections;
    for (Object *object : objects)
        for (const auto &section : object->sections)
            if (section->live && section->output == output)
                sections.push_back(section.get());
    if (script.sort.count(output->name))
        std::stable_sort(sections.begin(), sections.end(), [&](Section *a, Section *b) {
            int64_t pa =
                a->name == output->name ? 65536 : number(a->name.substr(output->name.size() + 1));
            int64_t pb =
                b->name == output->name ? 65536 : number(b->name.substr(output->name.size() + 1));
            return pa < pb;
        });
    std::vector<Section *> strings;
    for (Section *section : sections)
        if (belongs(section->name, ".rodata.str"))
            strings.push_back(section);
    std::unique_ptr<Component> merged;
    if (!strings.empty()) {
        merged = std::make_unique<Component>();
        merged->kind = "merged";
        merged->string_sections = static_cast<int>(strings.size());
        std::map<std::vector<uint8_t>, int64_t> seen;
        for (Section *section : strings) {
            section->merged = merged.get();
            section->string_offsets.clear();
            merged->original_size += section->size;
            for (size_t start = 0; start < section->data.size();) {
                size_t end = start;
                while (section->data[end] != 0)
                    ++end;
                ++end;
                std::vector<uint8_t> value(section->data.begin() + start,
                                           section->data.begin() + end);
                auto found = seen.find(value);
                int64_t offset;
                if (found == seen.end()) {
                    offset = static_cast<int64_t>(merged->data.size());
                    seen[value] = offset;
                    merged->data.insert(merged->data.end(), value.begin(), value.end());
                    ++merged->unique;
                } else
                    offset = found->second;
                section->string_offsets[static_cast<int64_t>(start)] = offset;
                ++merged->strings;
                start = end;
            }
        }
        merged->size = static_cast<int64_t>(merged->data.size());
    }
    std::vector<std::unique_ptr<Component>> result;
    bool inserted = false;
    for (Section *section : sections) {
        if (belongs(section->name, ".rodata.str")) {
            if (!inserted) {
                result.push_back(std::move(merged));
                inserted = true;
            }
        } else {
            auto component = std::make_unique<Component>();
            component->kind = "section";
            component->size = section->size;
            component->alignment = section->alignment;
            component->section = section;
            result.push_back(std::move(component));
        }
    }
    if (output->name == ".bss") {
        std::vector<Resolution *> commons;
        for (auto &entry : names)
            if (entry.second.kind == "common" && entry.second.live)
                commons.push_back(&entry.second);
        std::sort(commons.begin(), commons.end(), [](Resolution *a, Resolution *b) {
            return a->alignment != b->alignment ? a->alignment > b->alignment : a->name < b->name;
        });
        for (Resolution *common : commons) {
            auto component = std::make_unique<Component>();
            component->kind = "common";
            component->size = common->size;
            component->alignment = common->alignment;
            component->common = common;
            result.push_back(std::move(component));
        }
    }
    auto found = veneers.find(output);
    if (found != veneers.end())
        for (const std::string &target : found->second) {
            auto component = std::make_unique<Component>();
            component->kind = "veneer";
            component->size = 8;
            component->alignment = 4;
            component->target = target;
            result.push_back(std::move(component));
        }
    return result;
}
int64_t Linker::section_value(Section *section, int64_t offset) const {
    if (belongs(section->name, ".rodata.str"))
        return section->merged->address + section->string_offsets.at(offset);
    return section->address + offset;
}
std::optional<int64_t> Linker::name_value(const std::string &name) const {
    const Resolution &resolution = names.at(name);
    if (resolution.kind == "global" || resolution.kind == "weak")
        return section_value(resolution.definition->section, resolution.definition->offset);
    if (resolution.kind == "common")
        return resolution.address;
    if (resolution.kind == "script") {
        auto found = script_values.find(name);
        return found == script_values.end() ? 0 : found->second;
    }
    if (resolution.kind == "weakundef")
        return 0;
    return std::nullopt;
}
std::optional<int64_t> Linker::symbol_value(Symbol *symbol) const {
    return symbol->binding == "local"
               ? std::optional<int64_t>(section_value(symbol->section, symbol->offset))
               : name_value(symbol->name);
}
bool Linker::far_call(const Relocation &relocation) const {
    if (relocation.type != "CALL24" || relocation.symbol->binding == "local")
        return false;
    const Resolution &resolution = names.at(relocation.symbol->name);
    if (resolution.kind != "global" && resolution.kind != "weak")
        return false;
    int64_t value = *name_value(relocation.symbol->name) + relocation.addend -
                    (relocation.section->address + relocation.offset);
    return value < -(int64_t(1) << 25) || value >= (int64_t(1) << 25);
}
void Linker::layout() {
    while (true) {
        veneer_components.clear();
        for (const auto &segment : script.segments) {
            for (const auto &output : segment->sections)
                output->components = components(output.get());
            place_segment(*segment);
            for (const auto &output : segment->sections)
                for (const auto &component : output->components)
                    if (component->kind == "veneer")
                        veneer_components[output.get()][component->target] = component.get();
        }
        bool changed = false;
        for (Object *object : objects)
            for (const auto &section : object->sections)
                if (section->live)
                    for (const auto &relocation : section->relocations)
                        if (far_call(*relocation)) {
                            if (veneers[section->output].insert(relocation->symbol->name).second)
                                changed = true;
                        }
        if (!changed)
            return;
    }
}
void Linker::load_addresses() {
    std::map<std::string, int64_t> positions;
    for (const auto &segment : script.segments) {
        segment->physical = segment->base;
        positions[segment->name] = segment->base + segment->memory_size;
    }
    for (const auto &load : script.loads) {
        Segment *a = script.segment_names.at(load.first);
        Segment *b = script.segment_names.at(load.second);
        a->physical = aligned(positions[b->name], 4);
        positions[b->name] = a->physical + a->file_size;
    }
    for (const auto &segment : script.segments)
        segment->used = positions[segment->name] - segment->base;
}
struct ScriptExpression {
    std::vector<std::string> tokens;
    size_t index = 0;
    Linker *linker;
    std::string peek() const { return index == tokens.size() ? "" : tokens[index]; }
    int64_t expression() {
        int64_t value = term();
        while (peek() == "+" || peek() == "-") {
            std::string op = tokens[index++];
            int64_t right = term();
            if (op == "+")
                value += right;
            else
                value -= right;
        }
        return value;
    }
    int64_t term() {
        std::string token = tokens[index++];
        if (token == "(") {
            int64_t value = expression();
            ++index;
            return value;
        }
        if (token[0] >= '0' && token[0] <= '9')
            return number(token);
        if (peek() == "(" && word_in("start end size loadaddr align", token)) {
            ++index;
            if (token == "align") {
                int64_t value = expression();
                ++index;
                int64_t alignment = expression();
                ++index;
                return aligned(value, alignment);
            }
            OutputSection *output = linker->script.output_names.at(tokens[index]);
            index += 2;
            if (token == "start")
                return output->address;
            if (token == "end")
                return output->address + output->size;
            if (token == "size")
                return output->size;
            return output->segment->physical + output->address - output->segment->base;
        }
        return linker->script_values.at(token);
    }
};
static std::vector<std::string> expression_tokens(const std::string &source) {
    std::vector<std::string> tokens;
    size_t i = 0;
    while (i < source.size()) {
        if (source[i] == ' ') {
            ++i;
            continue;
        }
        if (std::string("(),+-").find(source[i]) != std::string::npos) {
            tokens.push_back(source.substr(i++, 1));
            continue;
        }
        size_t start = i;
        while (i < source.size() && source[i] != ' ' &&
               std::string("(),+-").find(source[i]) == std::string::npos)
            ++i;
        tokens.push_back(source.substr(start, i - start));
    }
    return tokens;
}
void Linker::define_script_symbols() {
    for (const ScriptDefinition &definition : script.definitions) {
        ScriptExpression expression{expression_tokens(definition.expression), 0, this};
        script_values[definition.name] = expression.expression();
    }
}
static std::string relocation_location(const Relocation &relocation) {
    return relocation.section->object->name + " " + relocation.section->name + "+" +
           std::to_string(relocation.offset);
}
void Linker::relocate() {
    int64_t gp = script_values.count("_gp") ? script_values.at("_gp") : 0;
    for (const auto &segment : script.segments)
        for (const auto &output : segment->sections)
            for (const auto &component : output->components)
                if (component->kind == "section") {
                    Section *section = component->section;
                    for (size_t index = 0; index < section->relocations.size(); ++index) {
                        const Relocation &relocation = *section->relocations[index];
                        if (unpaired(section->relocations, index))
                            relocation_diagnostics.push_back("error: unpaired HI16 at " +
                                                             relocation_location(relocation) +
                                                             " against " + relocation.symbol->name);
                        int64_t p = section->address + relocation.offset;
                        std::optional<int64_t> original = symbol_value(relocation.symbol);
                        std::string status = "undefined", shown = "-", value = "-", field = "-";
                        if (original) {
                            int64_t s = *original;
                            status = "ok";
                            if (far_call(relocation)) {
                                s = veneer_components.at(output.get())
                                        .at(relocation.symbol->name)
                                        ->address;
                                status = "veneer";
                            }
                            RelocationField result =
                                relocation_field(relocation.type, s, relocation.addend, p, gp);
                            if (!result.valid) {
                                status = "overflow";
                                relocation_diagnostics.push_back(
                                    "error: relocation overflow at " +
                                    relocation_location(relocation) + ": " + relocation.type +
                                    " value " + std::to_string(result.value) + " against " +
                                    relocation.symbol->name);
                            }
                            little_endian(section->data, static_cast<size_t>(relocation.offset),
                                          result.field, relocation_width(relocation.type));
                            shown = hex_value(s);
                            value = std::to_string(result.value);
                            field = hex_value(result.field, 2 * relocation_width(relocation.type));
                        }
                        ++relocation_counts[relocation.type][status];
                        ++relocation_counts[relocation.type]["total"];
                        relocation_lines.push_back(
                            hex_value(p) + " " + section->object->name + " " + section->name + "+" +
                            std::to_string(relocation.offset) + " " + relocation.type + " " +
                            relocation.symbol->name + " " + std::to_string(relocation.addend) +
                            " " + shown + " " + value + " " + field + " " + status);
                    }
                }
    for (const std::string &type : relocation_types) {
        auto &counts = relocation_counts[type];
        relocation_lines.push_back("summary " + type + " total " + std::to_string(counts["total"]) +
                                   " ok " + std::to_string(counts["ok"]) + " veneer " +
                                   std::to_string(counts["veneer"]) + " overflow " +
                                   std::to_string(counts["overflow"]) + " undefined " +
                                   std::to_string(counts["undefined"]));
    }
}
void Linker::build_images() {
    for (const auto &segment : script.segments) {
        segment->image.assign(static_cast<size_t>(segment->file_size),
                              static_cast<uint8_t>(segment->fill));
        for (const auto &output : segment->sections)
            if (!belongs(output->name, ".bss"))
                for (const auto &component : output->components) {
                    const std::vector<uint8_t> *data;
                    if (component->kind == "section")
                        data = &component->section->data;
                    else {
                        if (component->kind == "veneer") {
                            component->data = {0x04, 0xf0, 0x1f, 0xe5, 0, 0, 0, 0};
                            little_endian(component->data, 4, *name_value(component->target), 4);
                        }
                        data = &component->data;
                    }
                    std::copy(data->begin(), data->end(),
                              segment->image.begin() +
                                  static_cast<size_t>(component->address - segment->base));
                }
    }
    if (!script.checksum_segment.empty()) {
        Segment *segment = script.segment_names.at(script.checksum_segment);
        const Resolution &resolution = names.at(script.checksum_symbol);
        size_t offset = static_cast<size_t>(
            section_value(resolution.definition->section, resolution.definition->offset) -
            segment->base);
        little_endian(segment->image, offset, 0, 4);
        int64_t total = 0;
        for (size_t i = 0; i < segment->image.size(); i += 4) {
            int64_t value = 0;
            for (size_t j = 0; j < 4 && i + j < segment->image.size(); ++j)
                value += int64_t(segment->image[i + j]) << (8 * j);
            total = modulo(total + value, int64_t(1) << 32);
        }
        little_endian(segment->image, offset, modulo(-total, int64_t(1) << 32), 4);
    }
}
int64_t Linker::entry_address() const {
    auto found = names.find(script.entry);
    if (found == names.end())
        return 0;
    const Resolution &resolution = found->second;
    if (resolution.kind == "global" || resolution.kind == "weak")
        return section_value(resolution.definition->section, resolution.definition->offset);
    if (resolution.kind == "common")
        return resolution.address;
    return 0;
}
std::vector<std::string> Linker::diagnostics() const {
    std::vector<std::string> result;
    for (const auto &orphan : orphans)
        result.push_back("warning: orphan section " + orphan.first + " discarded from " +
                         std::to_string(orphan.second) + " object(s)");
    for (const auto &entry : names) {
        const Resolution &resolution = entry.second;
        std::vector<std::string> definers =
            strong_definers(resolution, script.script_names.count(entry.first));
        if (definers.size() >= 2)
            result.push_back("error: multiple definition of " + entry.first + ": " +
                             joined(definers, " "));
        if (!resolution.common.empty() &&
            (resolution.kind == "global" || resolution.kind == "script"))
            result.push_back("warning: common symbol " + entry.first + " overridden by " +
                             resolution.definer);
        if (resolution.kind == "common") {
            std::set<std::pair<int64_t, int64_t>> pairs;
            for (Symbol *symbol : resolution.common)
                pairs.insert({symbol->size, symbol->alignment});
            if (pairs.size() >= 2)
                result.push_back("warning: common symbol " + entry.first + " merged to size " +
                                 std::to_string(resolution.size) + " align " +
                                 std::to_string(resolution.alignment));
        }
    }
    auto entry = names.find(script.entry);
    if (entry == names.end() || entry->second.kind == "undefined" ||
        entry->second.kind == "weakundef")
        result.push_back("error: entry symbol " + script.entry + " is undefined");
    for (const auto &entry : names)
        if (entry.second.kind == "undefined") {
            std::vector<std::string> referrers;
            for (Object *object : objects) {
                bool used = false;
                for (const auto &section : object->sections)
                    if (section->live)
                        for (const auto &relocation : section->relocations)
                            if (relocation->symbol->binding != "local" &&
                                relocation->symbol->name == entry.first)
                                used = true;
                if (used)
                    referrers.push_back(object->name);
            }
            if (!referrers.empty())
                result.push_back("error: undefined symbol " + entry.first + " referenced by " +
                                 joined(referrers, " "));
        }
    for (const auto &segment : script.segments)
        if (segment->used > segment->length)
            result.push_back("error: segment " + segment->name + " overflows its length by " +
                             std::to_string(segment->used - segment->length) + " bytes");
    for (size_t i = 0; i < script.segments.size(); ++i)
        for (size_t j = i + 1; j < script.segments.size(); ++j) {
            const Segment &a = *script.segments[i];
            const Segment &b = *script.segments[j];
            if (a.memory_size >= 1 && b.memory_size >= 1 && a.base < b.base + b.memory_size &&
                b.base < a.base + a.memory_size)
                result.push_back("error: segments " + a.name + " and " + b.name + " overlap");
        }
    result.insert(result.end(), relocation_diagnostics.begin(), relocation_diagnostics.end());
    int errors = 0, warnings = 0;
    for (const std::string &line : result) {
        if (line.compare(0, 5, "error") == 0)
            ++errors;
        else if (line.compare(0, 7, "warning") == 0)
            ++warnings;
    }
    result.push_back("errors " + std::to_string(errors) + " warnings " + std::to_string(warnings));
    return result;
}
static std::string intel_record(int address, int type, const std::vector<uint8_t> &data) {
    std::vector<uint8_t> record = {static_cast<uint8_t>(data.size()),
                                   static_cast<uint8_t>((address >> 8) & 255),
                                   static_cast<uint8_t>(address & 255), static_cast<uint8_t>(type)};
    record.insert(record.end(), data.begin(), data.end());
    int sum = 0;
    for (uint8_t byte : record)
        sum += byte;
    record.push_back(static_cast<uint8_t>((256 - sum % 256) % 256));
    std::string result = ":";
    for (uint8_t byte : record)
        result += hex_value(byte, 2, true);
    return result;
}
void Linker::write_reports() const {
    std::filesystem::create_directories("output");
    std::ofstream image("output/image.hex"), flash("output/flash.ihex"), map("output/link.map"),
        xref("output/xref.txt"), relocations("output/relocations.txt"),
        diagnostic_output("output/diagnostics.txt");
    int64_t entry = entry_address();
    image << "entry " << hex_value(entry) << " " << script.entry << "\n";
    for (const auto &segment : script.segments) {
        image << "segment " << segment->name << " vaddr " << hex_value(segment->base) << " paddr "
              << hex_value(segment->physical) << " filesz " << segment->file_size << " memsz "
              << segment->memory_size << "\n";
        for (size_t i = 0; i < segment->image.size(); i += 16) {
            image << hex_value(segment->base + static_cast<int64_t>(i));
            for (size_t j = i; j < std::min(i + 16, segment->image.size()); ++j)
                image << " " << hex_value(segment->image[j], 2);
            image << "\n";
        }
    }
    std::vector<Segment *> ordered;
    for (const auto &segment : script.segments)
        if (segment->file_size)
            ordered.push_back(segment.get());
    std::stable_sort(ordered.begin(), ordered.end(),
                     [](Segment *a, Segment *b) { return a->physical < b->physical; });
    int64_t upper = 0;
    for (Segment *segment : ordered)
        for (size_t k = 0; k < segment->image.size();) {
            int64_t address = segment->physical + static_cast<int64_t>(k);
            size_t n = std::min({size_t(16), segment->image.size() - k,
                                 static_cast<size_t>(65536 - address % 65536)});
            if (address / 65536 != upper) {
                upper = address / 65536;
                flash << intel_record(
                             0, 4,
                             {static_cast<uint8_t>(upper / 256), static_cast<uint8_t>(upper % 256)})
                      << "\n";
            }
            flash << intel_record(static_cast<int>(address % 65536), 0,
                                  std::vector<uint8_t>(segment->image.begin() + k,
                                                       segment->image.begin() + k + n))
                  << "\n";
            k += n;
        }
    flash << intel_record(0, 5,
                          {static_cast<uint8_t>((entry >> 24) & 255),
                           static_cast<uint8_t>((entry >> 16) & 255),
                           static_cast<uint8_t>((entry >> 8) & 255),
                           static_cast<uint8_t>(entry & 255)})
          << "\n"
          << intel_record(0, 1, {}) << "\n";
    for (const Extraction &extraction : extractions)
        map << "member " << extraction.object << " " << extraction.referrer << " "
            << extraction.reason << "\n";
    for (const std::string &signature : comdat_order) {
        const COMDATRecord &record = comdat.at(signature);
        map << "comdat " << signature << " " << record.keeper->name << " "
            << joined(record.discarders, ",") << "\n";
    }
    struct OutputSymbol {
        int64_t address;
        std::string name, kind, definer;
    };
    std::vector<OutputSymbol> symbols;
    for (const auto &segment : script.segments) {
        map << "segment " << segment->name << " vaddr " << hex_value(segment->base) << " paddr "
            << hex_value(segment->physical) << " filesz " << segment->file_size << " memsz "
            << segment->memory_size << " used " << segment->used << " length " << segment->length
            << " " << 100 * segment->used / segment->length << "%\n";
        for (const auto &output : segment->sections) {
            map << "section " << output->name << " " << hex_value(output->address) << " "
                << output->size << " " << output->alignment << "\n";
            for (const auto &component : output->components) {
                if (component->kind == "section")
                    map << "input " << hex_value(component->address) << " " << component->size
                        << " " << component->alignment << " " << component->section->object->name
                        << " " << component->section->name << "\n";
                else if (component->kind == "merged")
                    map << "merged " << hex_value(component->address) << " " << component->size
                        << " sections " << component->string_sections << " strings "
                        << component->strings << " unique " << component->unique << " saved "
                        << component->original_size - component->size << "\n";
                else if (component->kind == "common")
                    map << "common " << hex_value(component->address) << " " << component->size
                        << " " << component->alignment << " " << component->common->definer << " "
                        << component->common->name << "\n";
                else {
                    map << "veneer " << hex_value(component->address) << " 8 " << component->target
                        << "\n";
                    symbols.push_back({component->address, "__veneer_" + component->target,
                                       "veneer", "*linker*"});
                }
            }
        }
    }
    for (Object *object : objects)
        for (const auto &section : object->sections)
            if (!section->reason.empty())
                map << "discard " << object->name << " " << section->name << " " << section->size
                    << " " << section->reason << "\n";
    for (const auto &entry : names) {
        const Resolution &resolution = entry.second;
        if (resolution.kind == "common" && !resolution.live)
            map << "discard " << resolution.definer << " COMMON(" << entry.first << ") "
                << resolution.size << " gc\n";
        bool kept = resolution.kind == "script" ||
                    (resolution.kind == "common" && resolution.live) ||
                    ((resolution.kind == "global" || resolution.kind == "weak") &&
                     resolution.definition->section->live);
        if (kept)
            symbols.push_back(
                {*name_value(entry.first), entry.first, resolution.kind, resolution.definer});
        std::string status = "-";
        if (resolution.kind == "script")
            status = "kept";
        else if (resolution.kind == "common")
            status = resolution.live ? "kept" : "discarded";
        else if (resolution.kind == "global" || resolution.kind == "weak")
            status = resolution.definition->section->live ? "kept" : "discarded";
        xref << entry.first << " " << resolution.kind << " " << status << " " << resolution.definer
             << " " << joined(resolution.referrers, ",") << "\n";
    }
    std::stable_sort(symbols.begin(), symbols.end(),
                     [](const OutputSymbol &a, const OutputSymbol &b) {
                         return a.address != b.address ? a.address < b.address : a.name < b.name;
                     });
    for (const OutputSymbol &symbol : symbols)
        map << "symbol " << hex_value(symbol.address) << " " << symbol.name << " " << symbol.kind
            << " " << symbol.definer << "\n";
    for (const std::string &line : relocation_lines)
        relocations << line << "\n";
    for (const std::string &line : diagnostics())
        diagnostic_output << line << "\n";
}
int main() {
    Linker linker;
    linker.read_script();
    linker.load_inputs();
    linker.resolve();
    linker.collect();
    linker.layout();
    linker.load_addresses();
    linker.define_script_symbols();
    linker.relocate();
    linker.build_images();
    linker.write_reports();
}
