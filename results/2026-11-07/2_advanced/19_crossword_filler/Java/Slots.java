import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

record ShortRun(int cell, String direction) {}
final class Slot {
    final int index, number, length;
    final boolean across;
    final int[] cells;
    final String label;
    final List<Integer> crossings = new ArrayList<>();
    Slot(int index, int number, boolean across, int[] cells) {
        this.index = index; this.number = number; this.across = across; this.cells = cells; length = cells.length; label = number + (across ? "A" : "D");
    }
}
final class Layout {
    final Grid grid;
    final int[] numbers, acrossSlot, downSlot;
    final List<Slot> slots = new ArrayList<>();
    Layout(Grid grid) {
        this.grid = grid; numbers = new int[grid.size()]; acrossSlot = new int[grid.size()]; downSlot = new int[grid.size()];
        Arrays.fill(acrossSlot, -1); Arrays.fill(downSlot, -1); int count = 0;
        for (int row = 0; row < grid.height; row++) for (int column = 0; column < grid.width; column++) for (boolean across : new boolean[] {true, false}) {
            if (!Slots.starts(grid, row, column, across)) continue;
            int length = Slots.length(grid, row, column, across);
            if (length < 3) continue;
            int start = grid.cell(row, column);
            if (numbers[start] == 0) numbers[start] = ++count;
            int[] cells = new int[length];
            for (int i = 0; i < length; i++) cells[i] = grid.cell(row + (across ? 0 : i), column + (across ? i : 0));
            Slot slot = new Slot(slots.size(), numbers[start], across, cells); slots.add(slot);
            int[] owners = across ? acrossSlot : downSlot;
            for (int cell : cells) owners[cell] = slot.index;
        }
        for (Slot slot : slots) {
            int[] owners = slot.across ? downSlot : acrossSlot;
            for (int cell : slot.cells) if (owners[cell] >= 0) slot.crossings.add(owners[cell]);
            slot.crossings.sort(Integer::compare);
        }
    }
    int owners(int cell) { return (acrossSlot[cell] < 0 ? 0 : 1) + (downSlot[cell] < 0 ? 0 : 1); }
    int orphan() { for (int cell : grid.whites()) if (owners(cell) == 0) return cell; return -1; }
}
final class Slots {
    static boolean starts(Grid grid, int row, int column, boolean across) { return grid.open(row, column) && !grid.open(row - (across ? 0 : 1), column - (across ? 1 : 0)); }
    static int length(Grid grid, int row, int column, boolean across) {
        int length = 0;
        while (grid.open(row + (across ? 0 : length), column + (across ? length : 0))) length++;
        return length;
    }
    static ShortRun shortRun(Grid grid) {
        for (int row = 0; row < grid.height; row++) for (int column = 0; column < grid.width; column++) for (boolean across : new boolean[] {true, false})
            if (starts(grid, row, column, across) && length(grid, row, column, across) == 2) return new ShortRun(grid.cell(row, column), across ? "across" : "down");
        return null;
    }
}
