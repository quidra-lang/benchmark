using System;
using System.Collections.Generic;
using System.Linq;
sealed record MergedPosition(Reference Reference, int Offset, int Merged);
sealed record MergedData(int Sections, int Strings, int Unique, int Saved, List<MergedPosition> Positions);
abstract record ComponentKind {
    public sealed record Input(Reference Reference) : ComponentKind;
    public sealed record Merged(MergedData Data) : ComponentKind;
    public sealed record Common(string Name) : ComponentKind;
    public sealed record Veneer(string Name) : ComponentKind;
}
sealed class Component(ComponentKind kind, int size, int alignment, List<int>? data = null) {
    public ComponentKind Kind {
        get;
    } = kind;
    public int Size {
        get;
    } = size;
    public int Alignment {
        get;
    } = alignment;
    public List<int> Data {
        get;
    } = data ?? new();
    public long Address {
        get;
        set;
    }
}
sealed class OutputSection(string name) {
    public string Name {
        get;
    } = name;
    public List<Component> Components {
        get;
        set;
    } = new();
    public long Address {
        get;
        set;
    } public long Size {
        get;
        set;
    } public int Alignment {
        get;
        set;
    } = 1;
}
sealed class Segment(string name, long baseAddress, long length, int fill, List<int> outputs) {
    public string Name {
        get;
    } = name;
    public long Base {
        get;
    } = baseAddress;
    public long Length {
        get;
    } = length;
    public int Fill {
        get;
    } = fill;
    public List<int> Outputs {
        get;
    } = outputs;
    public long Memsz {
        get;
        set;
    } public long Filesz {
        get;
        set;
    } public long Paddr {
        get;
        set;
    } public long Used {
        get;
        set;
    } public List<int> Image {
        get;
        set;
    } = new();
}
static class Layout {
    public static long Mod(long value, long divisor) {
        long remainder = value % divisor;
        return remainder < 0 ? remainder + divisor : remainder;
    }
    public static long Align(long value, long alignment) => value + Mod(alignment - Mod(value, alignment), alignment);
    public static int? Output(string name, List<OutputSection> outputs) {
        int index = outputs.FindIndex(output => ObjectParser.Belongs(name, output.Name));
        return index < 0 ? null : index;
    }
    public static void Assign(Segment segment, List<OutputSection> outputs) {
        long cursor = segment.Base;
        segment.Filesz = 0;
        foreach (int i in segment.Outputs) {
            OutputSection output = outputs[i];
            output.Alignment = output.Components.Select(component => component.Alignment).DefaultIfEmpty(1).Max();
            cursor = Align(cursor, output.Alignment);
            output.Address = cursor;
            foreach (Component component in output.Components) {
                cursor = Align(cursor, component.Alignment);
                component.Address = cursor;
                cursor += component.Size;
            } output.Size = cursor - output.Address;
            if (!ObjectParser.Nobits(output.Name)) segment.Filesz = cursor - segment.Base;
        } segment.Memsz = cursor - segment.Base;
        segment.Paddr = segment.Base;
        segment.Used = segment.Memsz;
    }
}
