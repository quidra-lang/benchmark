import java.util.*;
sealed interface Doc permits DocBuilder.Text, DocBuilder.Break, DocBuilder.Suffix,
    DocBuilder.IfBreak, DocBuilder.Concat, DocBuilder.Group, DocBuilder.Nest, DocBuilder.Align {}
final class DocBuilder {
    record Text(String value) implements Doc {}
    enum Break implements Doc { LINE, SOFTLINE, HARDLINE, BREAK_PARENT }
    record Suffix(String value) implements Doc {}
    record IfBreak(String broken, String flat) implements Doc {}
    record Concat(List<Doc> items) implements Doc {}
    static final class Group implements Doc {
        Doc child;
        boolean forced;
        String mode;
        Group(Doc child) {
            this.child = child;
            forced = forceBroken(child);
        }
    }
    record Nest(int amount, Doc child) implements Doc {}
    record Align(Doc child) implements Doc {}
    static Doc text(String value) { return new Text(value); }
    static void add(List<Doc> elements, Doc part) {
        if (part == null)
            return;
        if (part instanceof Concat concat) {
            for (Doc child : concat.items())
                add(elements, child);
        } else if (part instanceof Text text) {
            if (text.value().isEmpty())
                return;
            if (!elements.isEmpty() && elements.getLast() instanceof Text previous)
                elements.set(elements.size() - 1, new Text(previous.value() + text.value()));
            else
                elements.add(part);
        } else
            elements.add(part);
    }
    static Doc concat(List<Doc> parts) {
        List<Doc> elements = new ArrayList<>();
        for (Doc part : parts)
            add(elements, part);
        return elements.isEmpty() ? text("")
        : elements.size() == 1    ? elements.getFirst()
                                  : new Concat(List.copyOf(elements));
    }
    static Doc concat(Doc... parts) { return concat(Arrays.asList(parts)); }
    static boolean forceBroken(Doc doc) {
        return switch (doc) {
            case Break marker -> marker == Break.HARDLINE || marker == Break.BREAK_PARENT;
            case Concat concat -> concat.items().stream().anyMatch(DocBuilder::forceBroken);
            case Group group -> forceBroken(group.child);
            case Nest nest -> forceBroken(nest.child());
            case Align align -> forceBroken(align.child());
            default -> false;
        };
    }
    static List<Group> groups(Doc doc) {
        List<Group> result = new ArrayList<>();
        if (doc == null)
            return result;
        switch (doc) {
        case Group group -> {
            result.add(group);
            result.addAll(groups(group.child));
        }
        case Nest nest -> result.addAll(groups(nest.child()));
        case Align align -> result.addAll(groups(align.child()));
        case Concat concat -> {
            for (Doc child : concat.items())
                result.addAll(groups(child));
        }
        default -> {
        }
        }
        return result;
    }
}
