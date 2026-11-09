import java.util.ArrayList;
import java.util.List;

final class Memory {
    final int capacity;
    final List<String> texts = new ArrayList<>(), log = new ArrayList<>();
    Memory(int capacity) { this.capacity = capacity; }
    Memory(Memory source) { capacity = source.capacity; texts.addAll(source.texts); log.addAll(source.log); }
    boolean store(String prefix, String keyword, String text) {
        if (texts.contains(text)) { log.add(prefix + " SKIP " + keyword + " " + text); return false; }
        if (texts.size() == capacity) log.add(prefix + " DROP " + texts.removeFirst());
        texts.add(text); log.add(prefix + " STORE " + keyword + " " + text); return true;
    }
    String recall(String prefix) { String text = texts.removeFirst(); log.add(prefix + " RECALL " + text); return text; }
    void clear(String prefix) { if (!texts.isEmpty()) log.add(prefix + " CLEAR " + texts.size()); texts.clear(); }
}
