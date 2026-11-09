using System;
using System.Collections.Generic;

sealed record ShortRun(int Cell, string Direction);

sealed class Slot {
    public readonly int Index, Number, Length;
    public readonly bool Across;
    public readonly int[] Cells;
    public readonly string Label;
    public readonly List<int> Crossings = new();
    public Slot(int index, int number, bool across, int[] cells) {
        Index = index; Number = number; Across = across; Cells = cells;
        Length = cells.Length; Label = number + (across ? "A" : "D");
    }
}

sealed class Layout {
    public readonly Grid Grid;
    public readonly int[] Numbers, AcrossSlot, DownSlot;
    public readonly List<Slot> Slots = new();
    public Layout(Grid grid) {
        Grid = grid;
        Numbers = new int[grid.Size]; AcrossSlot = new int[grid.Size]; DownSlot = new int[grid.Size];
        Array.Fill(AcrossSlot, -1); Array.Fill(DownSlot, -1);
        int count = 0;
        for (int row = 0; row < grid.Height; row++) for (int column = 0; column < grid.Width; column++) foreach (bool across in new[] { true, false }) {
            if (!SlotFinder.Starts(grid, row, column, across)) continue;
            int length = SlotFinder.Length(grid, row, column, across);
            if (length < 3) continue;
            int start = grid.Cell(row, column);
            if (Numbers[start] == 0) Numbers[start] = ++count;
            int[] cells = new int[length];
            for (int i = 0; i < length; i++) cells[i] = grid.Cell(row + (across ? 0 : i), column + (across ? i : 0));
            Slot slot = new(Slots.Count, Numbers[start], across, cells);
            Slots.Add(slot);
            int[] owners = across ? AcrossSlot : DownSlot;
            foreach (int cell in cells) owners[cell] = slot.Index;
        }
        foreach (Slot slot in Slots) {
            int[] owners = slot.Across ? DownSlot : AcrossSlot;
            foreach (int cell in slot.Cells) if (owners[cell] >= 0) slot.Crossings.Add(owners[cell]);
            slot.Crossings.Sort();
        }
    }
    public int Owners(int cell) => (AcrossSlot[cell] < 0 ? 0 : 1) + (DownSlot[cell] < 0 ? 0 : 1);
    public int Orphan() {
        foreach (int cell in Grid.Whites()) if (Owners(cell) == 0) return cell;
        return -1;
    }
}

static class SlotFinder {
    public static bool Starts(Grid grid, int row, int column, bool across) => grid.Open(row, column) && !grid.Open(row - (across ? 0 : 1), column - (across ? 1 : 0));
    public static int Length(Grid grid, int row, int column, bool across) {
        int length = 0;
        while (grid.Open(row + (across ? 0 : length), column + (across ? length : 0))) length++;
        return length;
    }
    public static ShortRun FindShort(Grid grid) {
        for (int row = 0; row < grid.Height; row++) for (int column = 0; column < grid.Width; column++) foreach (bool across in new[] { true, false })
            if (Starts(grid, row, column, across) && Length(grid, row, column, across) == 2) return new ShortRun(grid.Cell(row, column), across ? "across" : "down");
        return null;
    }
}
