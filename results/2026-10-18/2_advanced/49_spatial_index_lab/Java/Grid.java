import java.util.*;

final class Grid {
    static final class Cell {
        int x, y;
        List<Dataset.Obj> points = new ArrayList<>();
        Cell(int x, int y) {
            this.x = x;
            this.y = y;
        }
    }
    static final class Index {
        int count, size;
        List<Cell> cells = new ArrayList<>();
        Index(int world, int size) {
            this.size = size;
            count = world / size;
            for (int y = 0; y < count; y++)
                for (int x = 0; x < count; x++)
                    cells.add(new Cell(x, y));
        }
        Cell cell(Dataset.Obj point) {
            return cells.get((int)(point.box().y1() / size) * count + (int)(point.box().x1() / size));
        }
        void insert(Dataset.Obj point) {
            Cell cell = cell(point);
            cell.points.add(point);
            cell.points.sort(Comparator.comparingInt(Dataset.Obj::id));
        }
        void delete(Dataset.Obj point) {
            cell(point).points.removeIf(p -> p.id() == point.id());
        }
    }
}
