using System;
using System.Collections.Generic;
using System.Linq;
readonly record struct CommonPair(int Size, int Alignment);
sealed class Resolution {
    public string Kind {
        get;
        set;
    } = "weakundef";
    public Reference? Definition {
        get;
        set;
    } public string Definer {
        get;
        set;
    } = "-";
    public int Size {
        get;
        set;
    } public int Alignment {
        get;
        set;
    } = 1;
    public List<int> Strong {
        get;
        set;
    } = new();
    public List<CommonPair> Common {
        get;
        set;
    } = new();
    public List<int> Referrers {
        get;
    } = new();
    public bool Live {
        get;
        set;
    } public long Address {
        get;
        set;
    }
}
static class Resolver {
    public static Resolution Resolve(List<LinkObject> objects, List<Reference> entries, bool script) {
        List<Reference> strong = new(), weak = new();
        List<(Reference Reference, Definition.Common Definition)> common = new();
        bool globalReference = false;
        Resolution result = new();
        foreach (Reference entry in entries) {
            Symbol symbol = objects[entry.ObjectIndex].Symbols[entry.Index];
            switch (symbol.Definition) {
                case Definition.SectionDef: (symbol.Binding == "global" ? strong : weak).Add(entry);
                break;
                case Definition.Common definition: common.Add((entry, definition));
                break;
                case Definition.Undefined: if (!result.Referrers.Contains(entry.ObjectIndex)) result.Referrers.Add(entry.ObjectIndex);
                globalReference |= symbol.Binding == "global";
                break;
            }
        }
        result.Strong = strong.Select(reference => reference.ObjectIndex).ToList();
        result.Common = common.Select(pair => new CommonPair(pair.Definition.Size, pair.Definition.Alignment)).ToList();
        if (script) {
            result.Kind = "script";
            result.Definer = "*script*";
            result.Live = true;
        }
        else if (strong.Count > 0) {
            Reference entry = strong[0];
            result.Kind = "global";
            result.Definition = entry;
            result.Definer = objects[entry.ObjectIndex].Name;
        }
        else if (common.Count > 0) {
            result.Kind = "common";
            result.Size = common.Max(pair => pair.Definition.Size);
            result.Alignment = common.Max(pair => pair.Definition.Alignment);
            result.Definer = objects[common.First(pair => pair.Definition.Size == result.Size).Reference.ObjectIndex].Name;
        }
        else if (weak.Count > 0) {
            Reference entry = weak[0];
            result.Kind = "weak";
            result.Definition = entry;
            result.Definer = objects[entry.ObjectIndex].Name;
        }
        else if (globalReference) result.Kind = "undefined";
        return result;
    }
}
