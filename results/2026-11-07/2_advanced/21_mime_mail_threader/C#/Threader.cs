using System;
using System.Collections.Generic;

sealed class Container {
    public readonly string Id;
    public Message Message;
    public Container Parent;
    public List<Container> Children = new();
    public string Subject;
    public Container(string id) { Id = id; }
    public bool AncestorOrSelf(Container other) {
        while (other != null) { if (other == this) return true; other = other.Parent; }
        return false;
    }
}
sealed class Threader {
    readonly Dictionary<string, Container> table = new(StringComparer.Ordinal);
    readonly List<Container> containers = new();
    Container ContainerOf(string id) {
        if (!table.TryGetValue(id, out Container container)) { container = new Container(id); table.Add(id, container); containers.Add(container); }
        return container;
    }
    static void Adopt(Container parent, Container child) { child.Parent = parent; parent.Children.Add(child); }
    void Add(Message message) {
        Container container;
        if (message.Id.Length > 0) container = ContainerOf(message.Id);
        else { container = new Container(""); containers.Add(container); }
        container.Message = message;
        List<Container> references = new();
        foreach (string id in message.References) references.Add(ContainerOf(id));
        for (int i = 0; i + 1 < references.Count; i++) {
            Container current = references[i], following = references[i + 1];
            if (following.Parent == null && !following.AncestorOrSelf(current)) Adopt(current, following);
        }
        if (container.Parent != null) { container.Parent.Children.Remove(container); container.Parent = null; }
        if (references.Count > 0 && !container.AncestorOrSelf(references[^1])) Adopt(references[^1], container);
    }
    static List<Container> Prune(List<Container> containers, bool atRoot) {
        List<Container> result = new();
        foreach (Container container in containers) {
            container.Children = Prune(container.Children, false);
            if (container.Message != null || atRoot && container.Children.Count >= 2) result.Add(container);
            else {
                foreach (Container child in container.Children) child.Parent = atRoot ? null : container.Parent;
                result.AddRange(container.Children);
            }
        }
        return result;
    }
    static SortKey Key(Container container) {
        if (container.Message != null) return container.Message.SortKey;
        SortKey best = null;
        foreach (Container child in container.Children) { SortKey key = Key(child); if (best == null || key.CompareTo(best) < 0) best = key; }
        return best;
    }
    static void Sort(List<Container> containers) {
        foreach (Container container in containers) Sort(container.Children);
        containers.Sort((a, b) => Key(a).CompareTo(Key(b)));
    }
    public static string RootSubject(Container root) => root.Message == null ? root.Children[0].Message.BaseSubject : root.Message.BaseSubject;
    static Container MergeGroup(string subject, List<Container> group) {
        Container target = null;
        List<Container> originals = new();
        foreach (Container root in group) {
            if (target == null && root.Message == null) target = root;
            if (root.Message != null && !root.Message.Reply) originals.Add(root);
        }
        if (target == null && originals.Count == 1) target = originals[0];
        if (target == null) { target = new Container(""); target.Subject = subject; }
        foreach (Container root in group) if (root != target) {
            if (root.Message != null) Adopt(target, root);
            else foreach (Container child in root.Children) Adopt(target, child);
        }
        return target;
    }
    static List<Container> Merge(List<Container> roots) {
        Dictionary<string, List<Container>> groups = new(StringComparer.Ordinal);
        List<string> subjects = new();
        foreach (Container root in roots) {
            string subject = RootSubject(root);
            if (subject.Length == 0) continue;
            if (!groups.TryGetValue(subject, out List<Container> group)) { groups[subject] = group = new(); subjects.Add(subject); }
            group.Add(root);
        }
        List<Container> result = new();
        foreach (Container root in roots) { string subject = RootSubject(root); if (subject.Length == 0 || groups[subject].Count == 1) result.Add(root); }
        foreach (string subject in subjects) if (groups[subject].Count >= 2) result.Add(MergeGroup(subject, groups[subject]));
        return result;
    }
    public static List<Container> Build(List<Message> messages) {
        Threader threader = new();
        foreach (Message message in messages) threader.Add(message);
        List<Container> roots = new();
        foreach (Container container in threader.containers) if (container.Parent == null) roots.Add(container);
        roots = Prune(roots, true); Sort(roots); roots = Merge(roots); Sort(roots);
        return roots;
    }
}
