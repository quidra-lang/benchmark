#include "linker.hpp"
bool belongs(const std::string &name, const std::string &base) {
    return name == base || name.compare(0, base.size() + 1, base + ".") == 0;
}
std::vector<std::string> read_lines(const std::string &path) {
    std::ifstream input(path);
    std::vector<std::string> result;
    std::string line;
    while (std::getline(input, line))
        result.push_back(line);
    return result;
}
std::vector<std::string> words(const std::string &line) {
    std::istringstream input(line);
    std::vector<std::string> result;
    std::string word;
    while (input >> word)
        result.push_back(word);
    return result;
}
int64_t number(const std::string &text) {
    return std::stoll(text, nullptr, text.compare(0, 2, "0x") == 0 ? 16 : 10);
}
std::unique_ptr<Object> parse_object(const std::vector<std::string> &lines,
                                     const std::string &name) {
    auto object = std::make_unique<Object>();
    object->name = name;
    Section *current = nullptr;
    for (const std::string &line : lines) {
        std::vector<std::string> a = words(line);
        if (a[0] == "section") {
            auto section = std::make_unique<Section>();
            section->name = a[1];
            section->alignment = number(a[2]);
            section->size = number(a[3]);
            section->object = object.get();
            current = section.get();
            object->section_names[section->name] = current;
            object->sections.push_back(std::move(section));
        } else if (a[0] == "data") {
            for (size_t i = 0; i < a[1].size(); i += 2)
                current->data.push_back(
                    static_cast<uint8_t>(std::stoul(a[1].substr(i, 2), nullptr, 16)));
        } else if (a[0] == "comdat") {
            COMDATGroup group;
            group.signature = a[1];
            for (size_t i = 2; i < a.size(); ++i)
                group.sections.push_back(object->section_names.at(a[i]));
            object->groups.push_back(std::move(group));
        } else if (a[0] == "symbol") {
            auto symbol = std::make_unique<Symbol>();
            symbol->name = a[1];
            symbol->binding = a[2];
            symbol->location = a[3];
            symbol->object = object.get();
            if (a[3] == "common") {
                symbol->size = number(a[4]);
                symbol->alignment = number(a[5]);
            } else if (a[3] != "undef") {
                symbol->location = "section";
                symbol->section = object->section_names.at(a[3]);
                symbol->offset = number(a[4]);
            }
            object->symbol_names[symbol->name] = symbol.get();
            object->symbols.push_back(std::move(symbol));
        } else if (a[0] == "reloc") {
            auto relocation = std::make_unique<Relocation>();
            relocation->section = object->section_names.at(a[1]);
            relocation->offset = number(a[2]);
            relocation->type = a[3];
            relocation->symbol = object->symbol_names.at(a[4]);
            relocation->addend = number(a[5]);
            relocation->section->relocations.push_back(std::move(relocation));
        }
    }
    return object;
}
