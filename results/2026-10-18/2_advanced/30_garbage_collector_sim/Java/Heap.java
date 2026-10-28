import java.util.*;

final class HeapObject {
    final int number, size;
    final int[] fields;
    int address, moves, age, count;
    boolean marked;
    HeapObject(int number, int pointers, int data) {
        this.number = number;
        size = 1 + pointers + data;
        fields = new int[pointers];
    }
}
final class Pair {
    int count, words;
    void add(HeapObject object) {
        count++;
        words += object.size;
    }
    void add(Pair other) {
        count += other.count;
        words += other.words;
    }
    public String toString() {
        return count + " " + words;
    }
}
record FreeBlock(int address, int length) {}
final class CollectionRecord {
    final int number, line, request;
    final String kind;
    final Pair live = new Pair(), freed = new Pair(), moved = new Pair(), promoted = new Pair();
    final int[] before;
    int[] after = new int[2];
    int stack, work;
    CollectionRecord(int number, int line, int request, String kind, List<FreeBlock> blocks) {
        this.number = number;
        this.line = line;
        this.request = request;
        this.kind = kind;
        before = new int[] {Heap.total(blocks), Heap.largest(blocks)};
    }
    void finish(List<FreeBlock> blocks) {
        after = new int[] {Heap.total(blocks), Heap.largest(blocks)};
    }
}
abstract class Collector {
    final int size;
    List<HeapObject> objects = new ArrayList<>();
    final List<HeapObject> placed = new ArrayList<>();
    final List<CollectionRecord> records = new ArrayList<>();
    Collector(int size) {
        this.size = size;
    }
    HeapObject lookup(int number) {
        return placed.get(number - 1);
    }
    void place(HeapObject object, int address) {
        object.address = address;
        objects.add(object);
        placed.add(object);
    }
    int[] inactive() {
        return new int[] {0, 0};
    }
    abstract List<FreeBlock> freeList();
    abstract boolean allocate(HeapObject object, List<Integer> roots, int line);
}
final class Heap {
    static List<HeapObject> byAddress(Collection<HeapObject> objects) {
        List<HeapObject> ordered = new ArrayList<>(objects);
        ordered.sort(Comparator.comparingInt(object -> object.address));
        return ordered;
    }
    static List<FreeBlock> freeBlocks(List<HeapObject> objects, int start, int end) {
        List<FreeBlock> blocks = new ArrayList<>();
        int position = start;
        for (HeapObject object : byAddress(objects)) {
            if (object.address < start || object.address >= end)
                continue;
            if (object.address > position)
                blocks.add(new FreeBlock(position, object.address - position));
            position = object.address + object.size;
        }
        if (position < end)
            blocks.add(new FreeBlock(position, end - position));
        return blocks;
    }
    static int firstFit(List<FreeBlock> blocks, int size) {
        for (FreeBlock block : blocks)
            if (block.length() >= size)
                return block.address();
        return -1;
    }
    static int total(List<FreeBlock> blocks) {
        int total = 0;
        for (FreeBlock block : blocks)
            total += block.length();
        return total;
    }
    static int largest(List<FreeBlock> blocks) {
        int largest = 0;
        for (FreeBlock block : blocks)
            largest = Math.max(largest, block.length());
        return largest;
    }
    static String dec2(int numerator, int denominator) {
        int rounded = (200 * numerator + denominator) / (2 * denominator);
        return rounded / 100 + "." + String.format(Locale.ROOT, "%02d", rounded % 100);
    }
    static String percent(int part, int whole) {
        return whole == 0 ? "-" : dec2(100 * part, whole);
    }
    static String classes(List<Integer> values) {
        String[] labels = {"1", "2-3", "4-7", "8-15", "16+"};
        int[] limits = {1, 3, 7, 15};
        int[] counts = new int[5];
        for (int value : values) {
            int index = 0;
            while (index < limits.length && value > limits[index])
                index++;
            counts[index]++;
        }
        List<String> parts = new ArrayList<>();
        for (int i = 0; i < 5; i++)
            parts.add(labels[i] + ":" + counts[i]);
        return String.join(" ", parts);
    }
    static String map(int size, List<HeapObject> objects, Set<Integer> reachable, int[] inactive) {
        char[] cells = new char[size];
        Arrays.fill(cells, '.');
        Arrays.fill(cells, inactive[0], inactive[1], '-');
        for (HeapObject object : objects) {
            boolean live = reachable.contains(object.number);
            char letter = (char)('A' + (object.number - 1) % 26);
            cells[object.address] = live ? letter : '#';
            for (int address = object.address + 1; address < object.address + object.size; address++)
                cells[address] = live ? Character.toLowerCase(letter) : '=';
        }
        return new String(cells);
    }
}
