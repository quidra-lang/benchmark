using System;
using System.Collections.Generic;
using System.Linq;
sealed class Member(LinkObject objectFile, List<string> exports) {
    public LinkObject ObjectFile {
        get;
    } = objectFile;
    public List<string> Exports {
        get;
    } = exports;
    public bool Loaded {
        get;
        set;
    }
}
sealed class Archive {
    readonly List<Member> members = new();
    public Archive(string name) {
        List<string> lines = ObjectParser.Lines(name);
        int i = 0;
        while (i < lines.Count) {
            string[] f = lines[i++].Split(' ');
            int start = i;
            while (lines[i] != "end") i++;
            i++;
            members.Add(new(ObjectParser.Parse($"{name}({f[1]})", lines.GetRange(start, i - start)), f.Skip(2).ToList()));
        }
    }
    public bool Scan(Func<Member, bool> extract) {
        bool any = false;
        while (true) {
            bool changed = false;
            foreach (Member member in members) if (!member.Loaded && extract(member)) {
                member.Loaded = true;
                changed = true;
                any = true;
            } if (!changed) return any;
        }
    }
}
