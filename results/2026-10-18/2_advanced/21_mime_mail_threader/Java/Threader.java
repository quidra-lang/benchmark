import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

final class Container {
    final String id;
    Message message;
    Container parent;
    List<Container> children = new ArrayList<>();
    String subject;
    Container(String id) { this.id = id; }
    boolean ancestorOrSelf(Container other) { while (other != null) { if (other == this) return true; other = other.parent; } return false; }
}
final class Threader {
    final Map<String, Container> table = new LinkedHashMap<>();
    final List<Container> containers = new ArrayList<>();
    Container containerOf(String id) {
        if (!table.containsKey(id)) { Container container = new Container(id); table.put(id, container); containers.add(container); }
        return table.get(id);
    }
    static void adopt(Container parent, Container child) { child.parent = parent; parent.children.add(child); }
    void add(Message message) {
        Container container;
        if (!message.id.isEmpty()) container = containerOf(message.id); else { container = new Container(""); containers.add(container); }
        container.message = message; List<Container> references = new ArrayList<>(); for (String id : message.references) references.add(containerOf(id));
        for (int i = 0; i + 1 < references.size(); i++) { Container current = references.get(i), following = references.get(i + 1); if (following.parent == null && !following.ancestorOrSelf(current)) adopt(current, following); }
        if (container.parent != null) { container.parent.children.remove(container); container.parent = null; }
        if (!references.isEmpty() && !container.ancestorOrSelf(references.getLast())) adopt(references.getLast(), container);
    }
    static List<Container> prune(List<Container> containers, boolean atRoot) {
        List<Container> result = new ArrayList<>();
        for (Container container : containers) {
            container.children = prune(container.children, false);
            if (container.message != null || atRoot && container.children.size() >= 2) result.add(container);
            else { for (Container child : container.children) child.parent = atRoot ? null : container.parent; result.addAll(container.children); }
        }
        return result;
    }
    static SortKey key(Container container) {
        if (container.message != null) return container.message.sortKey;
        SortKey best = null; for (Container child : container.children) { SortKey key = key(child); if (best == null || key.compareTo(best) < 0) best = key; } return best;
    }
    static void sort(List<Container> containers) { for (Container container : containers) sort(container.children); containers.sort((a, b) -> key(a).compareTo(key(b))); }
    static String rootSubject(Container root) { return root.message == null ? root.children.getFirst().message.baseSubject : root.message.baseSubject; }
    static Container mergeGroup(String subject, List<Container> group) {
        Container target = null; List<Container> originals = new ArrayList<>();
        for (Container root : group) { if (target == null && root.message == null) target = root; if (root.message != null && !root.message.reply) originals.add(root); }
        if (target == null && originals.size() == 1) target = originals.getFirst();
        if (target == null) { target = new Container(""); target.subject = subject; }
        for (Container root : group) if (root != target) { if (root.message != null) adopt(target, root); else for (Container child : root.children) adopt(target, child); }
        return target;
    }
    static List<Container> merge(List<Container> roots) {
        Map<String, List<Container>> groups = new LinkedHashMap<>();
        for (Container root : roots) { String subject = rootSubject(root); if (!subject.isEmpty()) groups.computeIfAbsent(subject, ignored -> new ArrayList<>()).add(root); }
        List<Container> result = new ArrayList<>();
        for (Container root : roots) { String subject = rootSubject(root); if (subject.isEmpty() || groups.get(subject).size() == 1) result.add(root); }
        for (var entry : groups.entrySet()) if (entry.getValue().size() >= 2) result.add(mergeGroup(entry.getKey(), entry.getValue()));
        return result;
    }
    static List<Container> build(List<Message> messages) {
        Threader threader = new Threader(); for (Message message : messages) threader.add(message);
        List<Container> roots = new ArrayList<>(); for (Container container : threader.containers) if (container.parent == null) roots.add(container);
        roots = prune(roots, true); sort(roots); roots = merge(roots); sort(roots); return roots;
    }
}
