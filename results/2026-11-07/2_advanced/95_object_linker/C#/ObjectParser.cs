using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
readonly record struct Reference(int ObjectIndex, int Index);
sealed class Section(string name, int alignment, int size) {
    public string Name {
        get;
    } = name;
    public int Alignment {
        get;
    } = alignment;
    public int Size {
        get;
    } = size;
    public List<int> Data {
        get;
    } = new();
    public string? Discard {
        get;
        set;
    } public int? Output {
        get;
        set;
    } public bool Live {
        get;
        set;
    } public long Address {
        get;
        set;
    } public Dictionary<int, long> Strings {
        get;
    } = new();
}
abstract record Definition {
    public sealed record SectionDef(int Section, int Offset) : Definition;
    public sealed record Undefined : Definition;
    public sealed record Common(int Size, int Alignment) : Definition;
}
sealed class Symbol(string name, string binding, Definition definition) {
    public string Name {
        get;
        set;
    } = name;
    public string Binding {
        get;
    } = binding;
    public Definition Definition {
        get;
        set;
    } = definition;
}
sealed record Relocation(int Section, int Offset, string Kind, int Symbol, long Addend);
sealed class LinkObject(string name) {
    public string Name {
        get;
    } = name;
    public List<Section> Sections {
        get;
    } = new();
    public List<(string Signature, List<int> Sections)> Groups {
        get;
    } = new();
    public List<Symbol> Symbols {
        get;
    } = new();
    public List<Relocation> Relocations {
        get;
    } = new();
}
static class ObjectParser {
    public static bool Belongs(string name, string output) => name == output || name.StartsWith(output + ".", StringComparison.Ordinal);
    public static bool Nobits(string name) => Belongs(name, ".bss");
    public static bool StringSection(string name) => Belongs(name, ".rodata.str");
    public static List<string> Lines(string name) => File.ReadAllLines("input/" + name).ToList();
    public static LinkObject Parse(string name, List<string> lines) {
        LinkObject objectFile = new(name);
        foreach (string line in lines) {
            string[] f = line.Split(' ');
            switch (f[0]) {
                case "section": objectFile.Sections.Add(new(f[1], int.Parse(f[2]), int.Parse(f[3])));
                break;
                case "data": for (int i = 0; i < f[1].Length; i += 2) objectFile.Sections[^1].Data.Add(Convert.ToInt32(f[1].Substring(i, 2), 16));
                break;
                case "comdat": objectFile.Groups.Add((f[1], f.Skip(2).Select(section => objectFile.Sections.FindIndex(s => s.Name == section)).ToList()));
                break;
                case "symbol": {
                    Definition definition = f[3] switch {
                        "undef" => new Definition.Undefined(), "common" => new Definition.Common(int.Parse(f[4]), int.Parse(f[5])), _ => new Definition.SectionDef(objectFile.Sections.FindIndex(s => s.Name == f[3]), int.Parse(f[4]))
                    };
                    objectFile.Symbols.Add(new(f[1], f[2], definition));
                    break;
                }
                case "reloc": objectFile.Relocations.Add(new(objectFile.Sections.FindIndex(s => s.Name == f[1]), int.Parse(f[2]), f[3], objectFile.Symbols.FindIndex(s => s.Name == f[4]), long.Parse(f[5])));
                break;
            }
        } return objectFile;
    }
}
