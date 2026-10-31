import java.util.*;
final class Canvas {
    record Position(int main, int secondary) {}
    record Cell(int row, int column) {
        public String toString() { return row + "," + column; }
    }
    String direction;
    int mainLength, rows, columns;
    boolean vertical;
    byte[][] lines;
    char[][] arrows, boxes;
    boolean[][] highlighted;
    char mainCharacter, secondaryCharacter;
    Canvas(String direction, int mainLength, int secondaryLength) {
        this.direction = direction;
        this.mainLength = mainLength;
        vertical = direction.equals("TB") || direction.equals("BT");
        rows = vertical ? mainLength : secondaryLength;
        columns = vertical ? secondaryLength : mainLength;
        lines = new byte[rows][columns];
        arrows = new char[rows][columns];
        boxes = new char[rows][columns];
        highlighted = new boolean[rows][columns];
        mainCharacter = vertical ? '|' : '-';
        secondaryCharacter = vertical ? '-' : '|';
    }
    Cell cell(int main, int secondary) {
        if (direction.equals("BT") || direction.equals("RL"))
            main = mainLength - 1 - main;
        return vertical ? new Cell(main, secondary) : new Cell(secondary, main);
    }
    void addLine(int main, int secondary, char character) {
        Cell cell = cell(main, secondary);
        int bit = character == '|' ? 1 : character == '-' ? 2 : 4;
        lines[cell.row()][cell.column()] |= (byte)bit;
    }
    void mainLine(int start, int end, int secondary) {
        for (int main = start; main <= end; main++)
            addLine(main, secondary, mainCharacter);
    }
    void segment(int start, int gap, int first, int second, Integer offset) {
        if (first == second) {
            mainLine(start, start + gap - 1, first);
            return;
        }
        mainLine(start, start + offset - 1, first);
        addLine(start + offset, first, '+');
        addLine(start + offset, second, '+');
        for (int secondary = Math.min(first, second) + 1; secondary < Math.max(first, second);
             secondary++)
            addLine(start + offset, secondary, secondaryCharacter);
        mainLine(start + offset + 1, start + gap - 1, second);
    }
    void arrow(Position point, boolean reversed) {
        Cell cell = cell(point.main(), point.secondary());
        char character = switch (direction) {
            case "TB" -> reversed ? '^' : 'v';
            case "BT" -> reversed ? 'v' : '^';
            case "LR" -> reversed ? '<' : '>';
            default -> reversed ? '>' : '<';
        };
        arrows[cell.row()][cell.column()] = character;
    }
    void highlightRoute(List<Cell> points) {
        for (int i = 0; i + 1 < points.size(); i++) {
            Cell first = points.get(i), second = points.get(i + 1);
            int rowStep = Integer.compare(second.row(), first.row()),
                columnStep = Integer.compare(second.column(), first.column()),
                distance = Math.abs(second.row() - first.row()) +
                           Math.abs(second.column() - first.column());
            for (int step = 0; step <= distance; step++)
                highlighted[first.row() + step * rowStep][first.column() + step * columnStep] =
                    true;
        }
    }
    void box(String label, int bandStart, int coordinate, int left, boolean onPath) {
        String text = onPath ? "{" + label + "}" : "[" + label + "]";
        Cell start;
        if (vertical)
            start = cell(bandStart, coordinate - left);
        else
            start = new Cell(coordinate, direction.equals("LR")
                                             ? bandStart
                                             : mainLength - bandStart - text.length());
        for (int i = 0; i < text.length(); i++)
            boxes[start.row()][start.column() + i] = text.charAt(i);
    }
    char character(int row, int column) {
        if (boxes[row][column] != 0)
            return boxes[row][column];
        if (arrows[row][column] != 0)
            return arrows[row][column];
        if (highlighted[row][column])
            return '#';
        return switch (lines[row][column]) {
            case 0 -> ' ';
            case 1 -> '|';
            case 2 -> '-';
            default -> '+';
        };
    }
    int crossingCells() {
        int count = 0;
        for (byte[] row : lines)
            for (byte bits : row)
                if ((bits & 3) == 3)
                    count++;
        return count;
    }
    List<String> drawingLines() {
        List<String> output = new ArrayList<>();
        StringBuilder ruler = new StringBuilder("    ");
        for (int column = 0; column < columns; column++)
            ruler.append(column % 10);
        output.add(ruler.toString());
        for (int row = 0; row < rows; row++) {
            StringBuilder line = new StringBuilder(String.format(Locale.ROOT, "%3d ", row));
            for (int column = 0; column < columns; column++)
                line.append(character(row, column));
            while (!line.isEmpty() && line.charAt(line.length() - 1) == ' ')
                line.setLength(line.length() - 1);
            output.add(line.toString());
        }
        return output;
    }
}
