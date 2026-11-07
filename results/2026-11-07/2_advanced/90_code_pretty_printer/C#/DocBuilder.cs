using System;
using System.Collections.Generic;
using System.Linq;
abstract record Document {
    public sealed record Text(string Value) : Document;
    public sealed record Line : Document;
    public sealed record Softline : Document;
    public sealed record Hardline : Document;
    public sealed record BreakParent : Document;
    public sealed record Suffix(string Value) : Document;
    public sealed record IfBreak(string Broken, string Flat) : Document;
    public sealed record Group(int Id, Document Child) : Document;
    public sealed record Nest(int Amount, Document Child) : Document;
    public sealed record Align(Document Child) : Document;
    public sealed record Concat(List<Document> Children) : Document;
    public bool Forced => this switch {
        Hardline or BreakParent => true, Group g => g.Child.Forced, Nest n => n.Child.Forced, Align a => a.Child.Forced, Concat c => c.Children.Any(x => x.Forced), _ => false
    };
    public int GroupCount => this switch {
        Group g => 1 + g.Child.GroupCount, Nest n => n.Child.GroupCount, Align a => a.Child.GroupCount, Concat c => c.Children.Sum(x => x.GroupCount), _ => 0
    };
}
static class Docs {
    public static Document Text(string value) => new Document.Text(value);
    public static Document Concat(IEnumerable<Document> parts) {
        List<Document> result = new();
        void Flatten(Document document) {
            if (document is Document.Concat c) foreach (Document child in c.Children) Flatten(child);
            else if (document is Document.Text t) {
                if (t.Value.Length == 0) return;
                if (result.LastOrDefault() is Document.Text previous) result[^1] = new Document.Text(previous.Value + t.Value);
                else result.Add(document);
            }
            else result.Add(document);
        }
        foreach (Document part in parts) Flatten(part);
        return result.Count == 0 ? Text("") : result.Count == 1 ? result[0] : new Document.Concat(result);
    }
    public static Document Concat(params Document[] parts) => Concat((IEnumerable<Document>)parts);
    public static Document Nest(int n, Document child) => new Document.Nest(n, child);
    public static Document Align(Document child) => new Document.Align(child);
    public static Document Line() => new Document.Line();
    public static Document Softline() => new Document.Softline();
    public static Document Hardline() => new Document.Hardline();
    public static Document Suffix(string value) => new Document.Suffix(value);
    public static Document BreakParent() => new Document.BreakParent();
    public static Document IfBreak(string broken, string flat) => new Document.IfBreak(broken, flat);
}
sealed class DocBuilder {
    int next;
    public Document Group(Document child) => new Document.Group(next++, child);
}
