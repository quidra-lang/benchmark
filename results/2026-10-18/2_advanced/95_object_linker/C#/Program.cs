using System;
using System.IO;
using System.Globalization;
using System.Collections.Generic;
using System.Linq;
using static Program;
readonly record struct VeneerPair(int Output, string Name);
abstract record LiveUnit {
    public sealed record SectionUnit(Reference Reference) : LiveUnit;
    public sealed record Common(string Name) : LiveUnit;
}
sealed record Comdat(string Signature, string Keeper) {
    public List<string> Discarded {
        get;
    } = new();
}
sealed record SymbolLine(long Address, string Name, string Kind, string Definer);
sealed class ByteSequenceComparer : IEqualityComparer<List<int>> {
    public bool Equals(List<int>? a, List<int>? b) => ReferenceEquals(a, b) || a != null && b != null && a.SequenceEqual(b);
    public int GetHashCode(List<int> bytes) {
        HashCode hash = new();
        foreach (int value in bytes) hash.Add(value);
        return hash.ToHashCode();
    }
}
sealed class Linker {
    string entry = "";
    bool gc = true;
    readonly List<Segment> segments = new();
    readonly List<OutputSection> outputs = new();
    readonly List<(string A, string B)> loads = new();
    readonly HashSet<string> keeps = new(), sorts = new(), wraps = new();
    readonly List<(string Name, string Expression)> defines = new();
    (string Segment, string Symbol)? checksum;
    readonly List<string[]> inputs = new();
    readonly List<LinkObject> objects = new();
    readonly Dictionary<string, Archive> archives = new();
    readonly Dictionary<string, List<Reference>> entries = new();
    readonly Dictionary<string, Resolution> names = new();
    readonly List<Comdat> comdats = new();
    readonly List<(string Object, string Referrer, string Reason)> extractions = new();
    readonly HashSet<VeneerPair> veneers = new();
    public Linker() {
        foreach (string line in ObjectParser.Lines("link.txt")) {
            string[] f = line.Split(' ');
            switch (f[0]) {
                case "entry": entry = f[1];
                break;
                case "gc": gc = f[1] == "on";
                break;
                case "segment": {
                    List<int> indices = new();
                    foreach (string name in f.Skip(5)) {
                        indices.Add(outputs.Count);
                        outputs.Add(new(name));
                    } segments.Add(new(f[1], Number(f[2]), Number(f[3]), (int)Number(f[4]), indices));
                    break;
                }
                case "load": loads.Add((f[1], f[2]));
                break;
                case "keep": keeps.Add(f[1]);
                break;
                case "sort": sorts.Add(f[1]);
                break;
                case "wrap": wraps.Add(f[1]);
                break;
                case "define": {
                    string[] parts = line.Split(" = ", 2, StringSplitOptions.None);
                    defines.Add((parts[0][7..], parts[1]));
                    break;
                }
                case "checksum": checksum = (f[1], f[2]);
                break;
                default: inputs.Add(f);
                break;
            }
        }
    }
    bool Undefined(string name) {
        if (defines.Any(definition => definition.Name == name)) return false;
        List<Reference> references = entries.GetValueOrDefault(name, new());
        if (references.Any(reference => objects[reference.ObjectIndex].Symbols[reference.Index].Definition is not Definition.Undefined)) return false;
        return name == entry || references.Any(reference => objects[reference.ObjectIndex].Symbols[reference.Index].Binding == "global");
    }
    void Load(LinkObject objectFile) {
        foreach (var (signature, sections) in objectFile.Groups) {
            Comdat? old = comdats.FirstOrDefault(group => group.Signature == signature);
            if (old != null) {
                foreach (int s in sections) objectFile.Sections[s].Discard = "comdat";
                old.Discarded.Add(objectFile.Name);
            } else comdats.Add(new(signature, objectFile.Name));
        }
        foreach (Symbol symbol in objectFile.Symbols) {
            if (symbol.Binding != "local" && symbol.Definition is Definition.SectionDef definition && objectFile.Sections[definition.Section].Discard == "comdat") symbol.Definition = new Definition.Undefined();
            if (symbol.Definition is Definition.Undefined) {
                if (wraps.Contains(symbol.Name)) symbol.Name = "__wrap_" + symbol.Name;
                else if (symbol.Name.StartsWith("__real_", StringComparison.Ordinal) && wraps.Contains(symbol.Name[7..])) symbol.Name = symbol.Name[7..];
            }
        }
        int o = objects.Count;
        for (int i = 0; i < objectFile.Symbols.Count; i++) {
            Symbol symbol = objectFile.Symbols[i];
            if (symbol.Binding == "local") continue;
            if (!entries.TryGetValue(symbol.Name, out List<Reference>? list)) {
                list = new();
                entries[symbol.Name] = list;
            } list.Add(new(o, i));
        } objects.Add(objectFile);
    }
    bool Scan(string name) {
        if (!archives.TryGetValue(name, out Archive? archive)) {
            archive = new(name);
            archives[name] = archive;
        }
        return archive.Scan(member => {
            string? reason = member.Exports.FirstOrDefault(Undefined);
            if (reason == null) return false;
            Reference? first = entries.GetValueOrDefault(reason, new()).Where(reference => {
                Symbol symbol = objects[reference.ObjectIndex].Symbols[reference.Index];
                return symbol.Definition is Definition.Undefined && symbol.Binding == "global";
            }).Select(reference => (Reference?)reference).FirstOrDefault();
            string referrer = first.HasValue ? objects[first.Value.ObjectIndex].Name : "*entry*";
            extractions.Add((member.ObjectFile.Name, referrer, reason));
            Load(member.ObjectFile);
            return true;
        });
    }
    void LoadInputs() {
        foreach (string[] f in inputs) {
            if (f[0] == "object") Load(ObjectParser.Parse(f[1], ObjectParser.Lines(f[1])));
            else if (f[0] == "library") Scan(f[1]);
            else while (true) {
                bool changed = false;
                foreach (string name in f.Skip(1)) if (Scan(name)) changed = true;
                if (!changed) break;
            }
        }
        HashSet<string> scripts = defines.Select(definition => definition.Name).ToHashSet();
        foreach (string name in entries.Keys.Concat(scripts).Distinct().Order(StringComparer.Ordinal)) names[name] = Resolver.Resolve(objects, entries.GetValueOrDefault(name, new()), scripts.Contains(name));
        foreach (LinkObject objectFile in objects) foreach (Section section in objectFile.Sections) if (section.Discard == null) {
            section.Output = Layout.Output(section.Name, outputs);
            if (!section.Output.HasValue) section.Discard = "orphan";
        }
    }
    LiveUnit? DefinitionUnit(string name, Resolution resolution) {
        if (resolution.Kind == "common") return new LiveUnit.Common(name);
        if (resolution.Definition is Reference reference && objects[reference.ObjectIndex].Symbols[reference.Index].Definition is Definition.SectionDef definition) return new LiveUnit.SectionUnit(new(reference.ObjectIndex, definition.Section));
        return null;
    }
    LiveUnit? Target(int objectIndex, Relocation relocation) {
        Symbol symbol = objects[objectIndex].Symbols[relocation.Symbol];
        if (symbol.Binding == "local" && symbol.Definition is Definition.SectionDef definition) return new LiveUnit.SectionUnit(new(objectIndex, definition.Section));
        return symbol.Binding != "local" ? DefinitionUnit(symbol.Name, names[symbol.Name]) : null;
    }
    void Collect() {
        List<LiveUnit> pending = new();
        for (int o = 0; o < objects.Count; o++) for (int s = 0; s < objects[o].Sections.Count; s++) {
            Section section = objects[o].Sections[s];
            if (section.Discard == null && (!gc || keeps.Contains(outputs[section.Output!.Value].Name))) pending.Add(new LiveUnit.SectionUnit(new(o, s)));
        } if (!gc) foreach (string name in names.Keys.Order(StringComparer.Ordinal)) if (names[name].Kind == "common") pending.Add(new LiveUnit.Common(name));
        if (names.TryGetValue(entry, out Resolution? root) && DefinitionUnit(entry, root) is {
        } unit) pending.Add(unit);
        int i = 0;
        while (i < pending.Count) {
            switch (pending[i++]) {
                case LiveUnit.Common common: names[common.Name].Live = true;
                break;
                case LiveUnit.SectionUnit sectionUnit: {
                    Reference reference = sectionUnit.Reference;
                    LinkObject objectFile = objects[reference.ObjectIndex];
                    Section section = objectFile.Sections[reference.Index];
                    if (section.Live || section.Discard != null) continue;
                    section.Live = true;
                    foreach (Relocation relocation in objectFile.Relocations.Where(relocation => relocation.Section == reference.Index)) if (Target(reference.ObjectIndex, relocation) is {
                    } target) pending.Add(target);
                    break;
                }
            }
        }
        foreach (LinkObject objectFile in objects) foreach (Section section in objectFile.Sections) if (section.Discard == null && !section.Live) section.Discard = "gc";
        foreach (Resolution resolution in names.Values) if (resolution.Definition is Reference reference && objects[reference.ObjectIndex].Symbols[reference.Index].Definition is Definition.SectionDef definition) resolution.Live = objects[reference.ObjectIndex].Sections[definition.Section].Live;
    }
    Component Merged(List<Reference> sections) {
        Dictionary<List<int>, int> unique = new(new ByteSequenceComparer());
        List<int> data = new();
        List<MergedPosition> positions = new();
        int strings = 0, total = 0;
        foreach (Reference reference in sections) {
            Section section = objects[reference.ObjectIndex].Sections[reference.Index];
            total += section.Size;
            int start = 0;
            for (int end = 0; end < section.Data.Count; end++) if (section.Data[end] == 0) {
                List<int> text = section.Data.GetRange(start, end - start + 1);
                if (!unique.TryGetValue(text, out int offset)) {
                    offset = data.Count;
                    unique[text] = offset;
                    data.AddRange(text);
                } positions.Add(new(reference, start, offset));
                strings++;
                start = end + 1;
            }
        } return new(new ComponentKind.Merged(new(sections.Count, strings, unique.Count, total - data.Count, positions)), data.Count, 1, data);
    }
    void LayoutAll() {
        for (int index = 0; index < outputs.Count; index++) {
            OutputSection output = outputs[index];
            List<Reference> sections = new();
            for (int o = 0; o < objects.Count; o++) for (int s = 0; s < objects[o].Sections.Count; s++) if (objects[o].Sections[s].Live && objects[o].Sections[s].Output == index) sections.Add(new(o, s));
            if (sorts.Contains(output.Name)) sections = sections.OrderBy(reference => {
                string name = objects[reference.ObjectIndex].Sections[reference.Index].Name;
                return name == output.Name ? 65536 : int.Parse(name[(output.Name.Length + 1)..]);
            }).ToList();
            List<Reference> strings = sections.Where(reference => ObjectParser.StringSection(objects[reference.ObjectIndex].Sections[reference.Index].Name)).ToList();
            bool emitted = false;
            List<Component> components = new();
            foreach (Reference reference in sections) {
                Section section = objects[reference.ObjectIndex].Sections[reference.Index];
                if (ObjectParser.StringSection(section.Name)) {
                    if (!emitted) {
                        components.Add(Merged(strings));
                        emitted = true;
                    }
                } else components.Add(new(new ComponentKind.Input(reference), section.Size, section.Alignment, section.Data));
            }
            if (output.Name == ".bss") foreach (string name in names.Keys.Where(name => names[name].Kind == "common" && names[name].Live).OrderByDescending(name => names[name].Alignment).ThenBy(name => name, StringComparer.Ordinal)) {
                Resolution resolution = names[name];
                components.Add(new(new ComponentKind.Common(name), resolution.Size, resolution.Alignment));
            } foreach (VeneerPair pair in veneers.Where(pair => pair.Output == index).OrderBy(pair => pair.Name, StringComparer.Ordinal)) components.Add(new(new ComponentKind.Veneer(pair.Name), 8, 4));
            output.Components = components;
        }
        foreach (Segment segment in segments) Layout.Assign(segment, outputs);
        foreach (OutputSection output in outputs) foreach (Component component in output.Components) switch (component.Kind) {
            case ComponentKind.Input input: objects[input.Reference.ObjectIndex].Sections[input.Reference.Index].Address = component.Address;
            break;
            case ComponentKind.Merged merged: foreach (MergedPosition position in merged.Data.Positions) objects[position.Reference.ObjectIndex].Sections[position.Reference.Index].Strings[position.Offset] = component.Address + position.Merged;
            break;
            case ComponentKind.Common common: names[common.Name].Address = component.Address;
            break;
        }
        foreach (Resolution resolution in names.Values) if (resolution.Definition is Reference reference && objects[reference.ObjectIndex].Symbols[reference.Index].Definition is Definition.SectionDef definition) {
            Section section = objects[reference.ObjectIndex].Sections[definition.Section];
            resolution.Address = ObjectParser.StringSection(section.Name) && section.Live ? section.Strings[definition.Offset] : section.Address + definition.Offset;
        }
    }
    bool IsFar(int objectIndex, Relocation relocation) {
        Section section = objects[objectIndex].Sections[relocation.Section];
        Symbol symbol = objects[objectIndex].Symbols[relocation.Symbol];
        return section.Live && relocation.Kind == "CALL24" && symbol.Binding != "local" && names.TryGetValue(symbol.Name, out Resolution? resolution) && resolution.Kind is "global" or "weak" && !Relocator.Fits("CALL24", resolution.Address + relocation.Addend - section.Address - relocation.Offset);
    }
    HashSet<VeneerPair> FarPairs() {
        HashSet<VeneerPair> pairs = new();
        for (int o = 0; o < objects.Count; o++) foreach (Relocation relocation in objects[o].Relocations) if (IsFar(o, relocation)) pairs.Add(new(objects[o].Sections[relocation.Section].Output!.Value, objects[o].Symbols[relocation.Symbol].Name));
        return pairs;
    }
    void FinishLayout() {
        while (true) {
            LayoutAll();
            HashSet<VeneerPair> far = FarPairs();
            if (far.IsSubsetOf(veneers)) break;
            veneers.UnionWith(far);
        } List<long> storage = segments.Select(segment => segment.Base + segment.Memsz).ToList();
        foreach (var (a, b) in loads) {
            int first = segments.FindIndex(segment => segment.Name == a), second = segments.FindIndex(segment => segment.Name == b);
            segments[first].Paddr = Layout.Align(storage[second], 4);
            storage[second] = segments[first].Paddr + segments[first].Filesz;
        } for (int i = 0; i < segments.Count; i++) segments[i].Used = storage[i] - segments[i].Base;
        Dictionary<string, long> values = new();
        foreach (var (name, expression) in defines) {
            long value = new ScriptParser(expression, values, outputs, segments).Expression();
            values[name] = value;
            names[name].Address = value;
        }
    }
    long? SymbolValue(int objectIndex, int index) {
        Symbol symbol = objects[objectIndex].Symbols[index];
        if (symbol.Binding == "local" && symbol.Definition is Definition.SectionDef definition) {
            Section section = objects[objectIndex].Sections[definition.Section];
            return ObjectParser.StringSection(section.Name) ? section.Strings[definition.Offset] : section.Address + definition.Offset;
        } Resolution resolution = names[symbol.Name];
        return resolution.Kind == "undefined" ? null : resolution.Address;
    }
    List<string> Diagnostics() {
        List<string> lines = new();
        Dictionary<string, int> orphans = objects.SelectMany(objectFile => objectFile.Sections).Where(section => section.Discard == "orphan").GroupBy(section => section.Name).ToDictionary(group => group.Key, group => group.Count());
        foreach (string name in orphans.Keys.Order(StringComparer.Ordinal)) lines.Add($"warning: orphan section {name} discarded from {orphans[name]} object(s)");
        foreach (string name in names.Keys.Order(StringComparer.Ordinal)) {
            Resolution resolution = names[name];
            List<string> definers = (resolution.Kind == "script" ? new[] {
                "*script*"
            } : Array.Empty<string>()).Concat(resolution.Strong.Select(index => objects[index].Name)).ToList();
            if (definers.Count >= 2) lines.Add($"error: multiple definition of {name}: " + string.Join(" ", definers));
            if (resolution.Common.Count > 0 && resolution.Kind is "global" or "script") lines.Add($"warning: common symbol {name} overridden by {resolution.Definer}");
            if (resolution.Kind == "common" && resolution.Common.Distinct().Count() >= 2) lines.Add($"warning: common symbol {name} merged to size {resolution.Size} align {resolution.Alignment}");
        }
        if (!names.TryGetValue(entry, out Resolution? root) || root.Kind is "undefined" or "weakundef") lines.Add($"error: entry symbol {entry} is undefined");
        foreach (string name in names.Keys.Order(StringComparer.Ordinal)) if (names[name].Kind == "undefined") {
            List<string> referrers = objects.Where(objectFile => objectFile.Relocations.Any(relocation => objectFile.Sections[relocation.Section].Live && objectFile.Symbols[relocation.Symbol].Binding != "local" && objectFile.Symbols[relocation.Symbol].Name == name)).Select(objectFile => objectFile.Name).ToList();
            if (referrers.Count > 0) lines.Add($"error: undefined symbol {name} referenced by " + string.Join(" ", referrers));
        }
        foreach (Segment segment in segments) if (segment.Used > segment.Length) lines.Add($"error: segment {segment.Name} overflows its length by {segment.Used - segment.Length} bytes");
        for (int i = 0; i < segments.Count; i++) {
            Segment a = segments[i];
            foreach (Segment b in segments.Skip(i + 1)) if (a.Memsz > 0 && b.Memsz > 0 && a.Base < b.Base + b.Memsz && b.Base < a.Base + a.Memsz) lines.Add($"error: segments {a.Name} and {b.Name} overlap");
        } return lines;
    }
    List<string> Relocate(List<string> diagnostics) {
        List<string> lines = new();
        Dictionary<string, int[]> counts = Relocator.Types.ToDictionary(kind => kind, _ => new int[4]);
        Dictionary<VeneerPair, long> addresses = new();
        List<Reference> order = new();
        for (int i = 0; i < outputs.Count; i++) foreach (Component component in outputs[i].Components) switch (component.Kind) {
            case ComponentKind.Veneer veneer: addresses[new(i, veneer.Name)] = component.Address;
            break;
            case ComponentKind.Input input: order.Add(input.Reference);
            break;
        }
        long gp = names.GetValueOrDefault("_gp")?.Address ?? 0;
        foreach (Reference reference in order) {
            int o = reference.ObjectIndex;
            LinkObject objectFile = objects[o];
            Section section = objectFile.Sections[reference.Index];
            List<Relocation> relocations = objectFile.Relocations.Where(relocation => relocation.Section == reference.Index).ToList();
            for (int index = 0; index < relocations.Count; index++) {
                Relocation relocation = relocations[index];
                string symbolName = objectFile.Symbols[relocation.Symbol].Name, location = $"{objectFile.Name} {section.Name}+{relocation.Offset}";
                long position = section.Address + relocation.Offset;
                if (Relocator.Unpaired(relocations, index)) diagnostics.Add($"error: unpaired HI16 at {location} against {symbolName}");
                long? symbol = SymbolValue(o, relocation.Symbol);
                string status = "ok";
                if (IsFar(o, relocation)) {
                    symbol = addresses[new(section.Output!.Value, symbolName)];
                    status = "veneer";
                }
                if (symbol.HasValue) {
                    long value = Relocator.Value(relocation.Kind, symbol.Value, relocation.Addend, position, gp), field = Relocator.Field(relocation.Kind, value);
                    int width = Relocator.Width(relocation.Kind);
                    if (!Relocator.Fits(relocation.Kind, value)) {
                        status = "overflow";
                        diagnostics.Add($"error: relocation overflow at {location}: {relocation.Kind} value {value} against {symbolName}");
                    } List<int> bytes = Relocator.Little(field, width);
                    for (int i = 0; i < bytes.Count; i++) section.Data[relocation.Offset + i] = bytes[i];
                    lines.Add($"{Hex(position)} {objectFile.Name} {section.Name}+{relocation.Offset} {relocation.Kind} {symbolName} {relocation.Addend} {Hex(symbol.Value)} {value} {Hex(field, width * 2)} {status}");
                }
                else {
                    status = "undefined";
                    lines.Add($"{Hex(position)} {objectFile.Name} {section.Name}+{relocation.Offset} {relocation.Kind} {symbolName} {relocation.Addend} - - - undefined");
                } counts[relocation.Kind][status switch {
                    "ok" => 0, "veneer" => 1, "overflow" => 2, _ => 3
                }]++;
            }
        }
        foreach (string kind in Relocator.Types) {
            int[] c = counts[kind];
            lines.Add($"summary {kind} total {c.Sum()} ok {c[0]} veneer {c[1]} overflow {c[2]} undefined {c[3]}");
        } return lines;
    }
    void Images() {
        foreach (Segment segment in segments) {
            List<int> image = Enumerable.Repeat(segment.Fill, (int)segment.Filesz).ToList();
            foreach (int i in segment.Outputs.Where(index => !ObjectParser.Nobits(outputs[index].Name))) foreach (Component component in outputs[i].Components) {
                List<int> data = component.Kind switch {
                    ComponentKind.Input input => objects[input.Reference.ObjectIndex].Sections[input.Reference.Index].Data, ComponentKind.Veneer veneer => new[] {
                        4, 240, 31, 229
                    }.Concat(Relocator.Little(names[veneer.Name].Address, 4)).ToList(), _ => component.Data
                };
                int offset = (int)(component.Address - segment.Base);
                for (int k = 0; k < data.Count; k++) image[offset + k] = data[k];
            } segment.Image = image;
        }
        if (checksum is {
        } check) {
            Segment segment = segments.First(candidate => candidate.Name == check.Segment);
            int offset = (int)(names[check.Symbol].Address - segment.Base);
            for (int k = 0; k < 4; k++) segment.Image[offset + k] = 0;
            long sum = 0;
            for (int i = 0; i < segment.Image.Count; i++) sum += (long)segment.Image[i] << (8 * (i % 4));
            List<int> bytes = Relocator.Little(Layout.Mod(-sum, 4294967296L), 4);
            for (int i = 0; i < 4; i++) segment.Image[offset + i] = bytes[i];
        }
    }
    List<string> MapLines() {
        List<string> lines = extractions.Select(extraction => $"member {extraction.Object} {extraction.Referrer} {extraction.Reason}").ToList();
        List<SymbolLine> symbols = new();
        foreach (Comdat group in comdats) lines.Add($"comdat {group.Signature} {group.Keeper} {(group.Discarded.Count == 0 ? "-" : string.Join(",", group.Discarded))}");
        foreach (Segment segment in segments) {
            lines.Add($"segment {segment.Name} vaddr {Hex(segment.Base)} paddr {Hex(segment.Paddr)} filesz {segment.Filesz} memsz {segment.Memsz} used {segment.Used} length {segment.Length} {100 * segment.Used / segment.Length}%");
            foreach (int i in segment.Outputs) {
                OutputSection output = outputs[i];
                lines.Add($"section {output.Name} {Hex(output.Address)} {output.Size} {output.Alignment}");
                foreach (Component component in output.Components) switch (component.Kind) {
                    case ComponentKind.Input input: lines.Add($"input {Hex(component.Address)} {component.Size} {component.Alignment} {objects[input.Reference.ObjectIndex].Name} {objects[input.Reference.ObjectIndex].Sections[input.Reference.Index].Name}");
                    break;
                    case ComponentKind.Merged merged: lines.Add($"merged {Hex(component.Address)} {component.Size} sections {merged.Data.Sections} strings {merged.Data.Strings} unique {merged.Data.Unique} saved {merged.Data.Saved}");
                    break;
                    case ComponentKind.Common common: lines.Add($"common {Hex(component.Address)} {component.Size} {component.Alignment} {names[common.Name].Definer} {common.Name}");
                    break;
                    case ComponentKind.Veneer veneer: lines.Add($"veneer {Hex(component.Address)} 8 {veneer.Name}");
                    symbols.Add(new(component.Address, "__veneer_" + veneer.Name, "veneer", "*linker*"));
                    break;
                }
            }
        }
        foreach (LinkObject objectFile in objects) foreach (Section section in objectFile.Sections) if (section.Discard != null) lines.Add($"discard {objectFile.Name} {section.Name} {section.Size} {section.Discard}");
        foreach (string name in names.Keys.Order(StringComparer.Ordinal)) {
            Resolution resolution = names[name];
            if (resolution.Kind == "common" && !resolution.Live) lines.Add($"discard {resolution.Definer} COMMON({name}) {resolution.Size} gc");
            if (resolution.Live && resolution.Kind is "global" or "weak" or "common" or "script") symbols.Add(new(resolution.Address, name, resolution.Kind, resolution.Definer));
        } foreach (SymbolLine symbol in symbols.OrderBy(candidate => candidate.Address).ThenBy(candidate => candidate.Name, StringComparer.Ordinal)) lines.Add($"symbol {Hex(symbol.Address)} {symbol.Name} {symbol.Kind} {symbol.Definer}");
        return lines;
    }
    List<string> Xref() => names.Keys.Order(StringComparer.Ordinal).Select(name => {
        Resolution r = names[name];
        string status = r.Kind is "undefined" or "weakundef" ? "-" : r.Live ? "kept" : "discarded";
        return $"{name} {r.Kind} {status} {r.Definer} {(r.Referrers.Count == 0 ? "-" : string.Join(",", r.Referrers.Select(index => objects[index].Name)))}";
    }).ToList();
    void Output(List<string> relocations, List<string> diagnostics) {
        long address = names.TryGetValue(entry, out Resolution? resolution) && resolution.Kind is "global" or "weak" or "common" ? resolution.Address : 0;
        List<string> image = new() {
            $"entry {Hex(address)} {entry}"
        };
        foreach (Segment segment in segments) {
            image.Add($"segment {segment.Name} vaddr {Hex(segment.Base)} paddr {Hex(segment.Paddr)} filesz {segment.Filesz} memsz {segment.Memsz}");
            for (int k = 0; k < segment.Image.Count; k += 16) image.Add(Hex(segment.Base + k) + " " + string.Join(" ", segment.Image.Skip(k).Take(16).Select(value => Hex(value, 2))));
        }
        List<string> ihex = new();
        long upper = 0;
        foreach (Segment segment in segments.Select((segment, i) => (Segment: segment, Index: i)).Where(pair => pair.Segment.Filesz > 0).OrderBy(pair => pair.Segment.Paddr).ThenBy(pair => pair.Index).Select(pair => pair.Segment)) {
            int k = 0;
            while (k < segment.Filesz) {
                long a = segment.Paddr + k;
                int n = (int)Math.Min(Math.Min(16, segment.Filesz - k), 65536 - Layout.Mod(a, 65536));
                if (a / 65536 != upper) {
                    upper = a / 65536;
                    ihex.Add(Record(0, 4, new() {
                        (int)(upper / 256), (int)(upper % 256)
                    }));
                } ihex.Add(Record((int)Layout.Mod(a, 65536), 0, segment.Image.GetRange(k, n)));
                k += n;
            }
        } ihex.Add(Record(0, 5, new[] {
            24, 16, 8, 0
        }.Select(shift => (int)((address >> shift) & 255)).ToList()));
        ihex.Add(Record(0, 1, new()));
        int errors = diagnostics.Count(line => line.StartsWith("error", StringComparison.Ordinal)), warnings = diagnostics.Count(line => line.StartsWith("warning", StringComparison.Ordinal));
        diagnostics.Add($"errors {errors} warnings {warnings}");
        Write("image.hex", image);
        Write("flash.ihex", ihex);
        Write("link.map", MapLines());
        Write("xref.txt", Xref());
        Write("relocations.txt", relocations);
        Write("diagnostics.txt", diagnostics);
    }
    public void Run() {
        LoadInputs();
        Collect();
        FinishLayout();
        List<string> diagnostics = Diagnostics();
        List<string> relocations = Relocate(diagnostics);
        Images();
        Output(relocations, diagnostics);
    }
}
sealed class ScriptParser {
    readonly List<string> tokens = new();
    readonly Dictionary<string, long> values;
    readonly List<OutputSection> outputs;
    readonly List<Segment> segments;
    int index;
    public ScriptParser(string expression, Dictionary<string, long> values, List<OutputSection> outputs, List<Segment> segments) {
        this.values = values;
        this.outputs = outputs;
        this.segments = segments;
        int i = 0;
        while (i < expression.Length) {
            if (expression[i] == ' ') {
                i++;
                continue;
            } int start = i;
            if ("(),+-".Contains(expression[i])) i++;
            else while (i < expression.Length && expression[i] != ' ' && !"(),+-".Contains(expression[i])) i++;
            tokens.Add(expression[start..i]);
        }
    }
    string Peek => index < tokens.Count ? tokens[index] : "";
    public long Expression() {
        long value = Term();
        while (Peek is "+" or "-") {
            string op = tokens[index++];
            long right = Term();
            value = op == "+" ? value + right : value - right;
        } return value;
    }
    long Term() {
        string token = tokens[index++];
        if (token == "(") {
            long value = Expression();
            index++;
            return value;
        } if (token[0] is >= '0' and <= '9') return Number(token);
        if (Peek != "(") return values[token];
        index++;
        if (token == "align") {
            long value = Expression();
            index++;
            long alignment = Expression();
            index++;
            return Layout.Align(value, alignment);
        } string name = tokens[index];
        index += 2;
        int i = outputs.FindIndex(output => output.Name == name);
        OutputSection section = outputs[i];
        return token switch {
            "start" => section.Address, "end" => section.Address + section.Size, "size" => section.Size, _ => segments.First(segment => segment.Outputs.Contains(i)).Paddr + section.Address - segments.First(segment => segment.Outputs.Contains(i)).Base
        };
    }
}
static class Program {
    public static long Number(string text) => text.StartsWith("0x", StringComparison.Ordinal) ? Convert.ToInt64(text[2..], 16) : long.Parse(text, CultureInfo.InvariantCulture);
    public static string Hex(long value, int width = 8, bool uppercase = false) => value.ToString((uppercase ? "X" : "x") + width, CultureInfo.InvariantCulture);
    public static string Record(int address, int type, List<int> data) {
        List<int> bytes = new() {
            data.Count, (address >> 8) & 255, address & 255, type
        };
        bytes.AddRange(data);
        bytes.Add((int)Layout.Mod(-bytes.Sum(), 256));
        return ":" + string.Concat(bytes.Select(value => Hex(value, 2, true)));
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n");
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        new Linker().Run();
    }
}
