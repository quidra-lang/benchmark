using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Grid {
    public sealed class Cell {
        public int x, y;
        public List<Dataset.Obj> points = new();
        public Cell(int x, int y) {
            this.x = x;
            this.y = y;
        }
    }
    public sealed class Index {
        public int count, size;
        public List<Cell> cells = new();
        public Index(int world, int size) {
            this.size = size;
            count = world / size;
            for (int y = 0; y < count; y++)
                for (int x = 0; x < count; x++)
                    cells.Add(new Cell(x, y));
        }
        public Cell Cell(Dataset.Obj point) {
            return cells[(int)(point.box.y1 / size) * count + (int)(point.box.x1 / size)];
        }
        public void Insert(Dataset.Obj point) {
            Cell cell = Cell(point);
            cell.points.Add(point);
            cell.points.Sort(Comparer<Dataset.Obj>.Create((a, b) => a.id.CompareTo(b.id)));
        }
        public void Delete(Dataset.Obj point) {
            Cell(point).points.RemoveAll(p => p.id == point.id);
        }
    }
}
