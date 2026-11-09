import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

record Given(int row, int column, char value) {}
record Symmetry(String name, boolean rows, boolean columns) {}
final class Text {
    static String cat(Object... values) { StringBuilder text = new StringBuilder(); for (Object value : values) text.append(value); return text.toString(); }
    static boolean validName(String name) { return name.matches("[a-z0-9_]{1,20}"); }
    static String cell(int row, int column) { return (row + 1) + "," + (column + 1); }
    static String numbers(List<Integer> values) { return values.isEmpty() ? "-" : values.stream().map(Object::toString).collect(Collectors.joining(",")); }
    static List<List<String>> readBlocks(String path) throws IOException {
        List<List<String>> blocks = new ArrayList<>(); List<String> current = null;
        for (String line : Files.readAllLines(Path.of(path),StandardCharsets.US_ASCII)) {
            if (current == null) { if (!line.isEmpty() && line.charAt(0) != '#') { current = new ArrayList<>(); current.add(line); } }
            else if (line.equals("END")) { blocks.add(current); current = null; } else current.add(line);
        }
        return blocks;
    }
    static List<String> paragraphs(List<List<String>> paragraphs) { List<String> lines = new ArrayList<>(); for (List<String> paragraph : paragraphs) { if (!lines.isEmpty()) lines.add(""); lines.addAll(paragraph); } return lines; }
    static void write(String name, List<String> lines) throws IOException { Files.writeString(Path.of("output",name),String.join("\n",lines) + (lines.isEmpty() ? "" : "\n"),StandardCharsets.US_ASCII); }
    static List<Cell> differences(char[][] first, char[][] second) {
        List<Cell> cells = new ArrayList<>(); for (int r = 0; r < first.length; r++) for (int c = 0; c < first[0].length; c++) if (first[r][c] != second[r][c]) cells.add(new Cell(r,c)); return cells;
    }
}
final class Puzzle {
    final String name;
    final int width, height;
    final List<String> rowLines, columnLines = new ArrayList<>();
    final List<int[]> rows = new ArrayList<>(), columns = new ArrayList<>();
    final List<Given> givens = new ArrayList<>();
    char[][] answer;
    Puzzle(List<String> block) {
        name = block.getFirst().substring(7); String[] size = block.get(1).split(" "); width = Integer.parseInt(size[1]); height = Integer.parseInt(size[2]); int split = block.indexOf("COLUMNS"); rowLines = block.subList(3,split); int position = split + 1;
        while (position < block.size() && Clues.isLine(block.get(position))) columnLines.add(block.get(position++));
        while (position < block.size() && block.get(position).startsWith("GIVEN ")) { String[] p = block.get(position++).split(" "); givens.add(new Given(Integer.parseInt(p[1]) - 1,Integer.parseInt(p[2]) - 1,p[3].charAt(0))); }
        if (position < block.size()) answer = block.subList(position + 1,block.size()).stream().map(String::toCharArray).toArray(char[][]::new);
    }
    String validate(Set<String> names) {
        if (!Text.validName(name)) return "bad name"; if (names.contains(name)) return "duplicate name";
        if (width < 1 || width > 30 || height < 1 || height > 30) return "bad size";
        if (rowLines.size() != height) return Text.cat("row count ",rowLines.size()," expected ",height); if (columnLines.size() != width) return Text.cat("column count ",columnLines.size()," expected ",width);
        for (boolean row : new boolean[] { true,false }) {
            List<String> lines = row ? rowLines : columnLines; List<int[]> clues = row ? rows : columns; String kind = row ? "row" : "column";
            for (int i = 0; i < lines.size(); i++) { int[] clue = Clues.parse(lines.get(i)); if (clue == null) return Text.cat("bad clue ",kind," ",i + 1); if (Clues.span(clue) > (row ? width : height)) return Text.cat(kind," ",i + 1," too long"); clues.add(clue); }
        }
        int a = rows.stream().mapToInt(c -> Arrays.stream(c).sum()).sum(), b = columns.stream().mapToInt(c -> Arrays.stream(c).sum()).sum(); if (a != b) return Text.cat("total mismatch rows=",a," columns=",b);
        Set<Cell> taken = new HashSet<>();
        for (int i = 0; i < givens.size(); i++) { Given g = givens.get(i); if (g.row() < 0 || g.row() >= height || g.column() < 0 || g.column() >= width || g.value() != '#' && g.value() != '.') return "bad given " + (i + 1); if (!taken.add(new Cell(g.row(),g.column()))) return "duplicate given " + (i + 1); }
        if (answer != null) { if (answer.length != height) return "bad answer"; for (char[] row : answer) { if (row.length != width) return "bad answer"; for (char cell : row) if (cell != '#' && cell != '.' && cell != '?') return "bad answer"; } } return "";
    }
}
final class Analysis {
    final char[][] simpleGrid, logicGrid;
    final Propagation simple, logic;
    final String simpleResult, logicResult;
    String status, difficulty = "-";
    Search searchResult;
    List<char[][]> solutions = new ArrayList<>();
    int lineSolves, guesses, maxDepth;
    static String result(char[][] grid, Propagation propagation) { return propagation.conflict != null ? "contradiction at=" + propagation.conflict.label() : Propagation.determined(grid) == grid.length * grid[0].length ? "solved" : "stuck"; }
    static boolean[] allMarks(int count) { boolean[] marks = new boolean[count]; Arrays.fill(marks,true); return marks; }
    Analysis(List<int[]> rows, List<int[]> columns, List<Given> givens) {
        int h = rows.size(), w = columns.size(); char[][] initial = new char[h][w]; for (char[] row : initial) Arrays.fill(row,LineSolver.UNKNOWN); for (Given g : givens) initial[g.row()][g.column()] = g.value();
        simpleGrid = Propagation.copy(initial); logicGrid = Propagation.copy(initial); simple = Propagation.run(simpleGrid,rows,columns,false,allMarks(h),allMarks(w)); logic = Propagation.run(logicGrid,rows,columns,true,allMarks(h),allMarks(w));
        simpleResult = result(simpleGrid,simple); logicResult = result(logicGrid,logic); lineSolves = logic.steps.size();
        if (logic.conflict != null) status = "contradiction";
        else if (logicResult.equals("solved")) { status = "unique"; solutions.add(logicGrid); difficulty = simpleResult.equals("solved") ? "easy" : "medium"; }
        else { searchResult = new Search(rows,columns); searchResult.visit(logicGrid,1); solutions = searchResult.solutions; status = solutions.isEmpty() ? "none" : solutions.size() == 1 ? "unique" : "multiple"; if (status.equals("unique")) difficulty = "hard"; lineSolves += searchResult.lineSolves; guesses = searchResult.guesses.size(); maxDepth = searchResult.maxDepth; }
    }
}
final class Measures {
    static String clueStatistics(List<int[]> rows, List<int[]> columns) {
        int rowBlocks = rows.stream().mapToInt(c -> c.length).sum(), columnBlocks = columns.stream().mapToInt(c -> c.length).sum(), filled = rows.stream().mapToInt(c -> Arrays.stream(c).sum()).sum();
        int maximum = 0, fixed = 0; for (boolean row : new boolean[] { true,false }) for (int[] clue : row ? rows : columns) { for (int block : clue) maximum = Math.max(maximum,block); if (clue.length == 0 || Clues.span(clue) == (row ? columns.size() : rows.size())) fixed++; }
        return Text.cat("row_blocks=",rowBlocks," column_blocks=",columnBlocks," filled=",filled," max_block=",maximum," fixed_lines=",fixed);
    }
    static String stepStatistics(Propagation propagation) {
        int productive = 0, idle = 0, best = 0; String at = "-";
        for (LineStep step : propagation.steps) if (!step.contradiction()) { if (step.gain() > 0) productive++; else idle++; if (step.gain() > best) { best = step.gain(); at = step.label(); } }
        return Text.cat("productive=",productive," idle=",idle," best=",best," at=",at);
    }
    static String unknownSummary(char[][] grid, boolean row) {
        List<String> parts = new ArrayList<>(); for (int i = 0; i < (row ? grid.length : grid[0].length); i++) { int count = 0; for (char cell : Propagation.cells(grid,row,i)) if (cell == LineSolver.UNKNOWN) count++; if (count > 0) parts.add((i + 1) + ":" + count); } return String.join(" ",parts);
    }
    static String features(char[][] grid) {
        int h = grid.length, w = grid[0].length, filled = 0, components = 0, largest = 0, minRow = h, minColumn = w, maxRow = -1, maxColumn = -1; boolean[][] seen = new boolean[h][w];
        for (int r = 0; r < h; r++) for (int c = 0; c < w; c++) if (grid[r][c] == LineSolver.FILLED) {
            filled++; minRow = Math.min(minRow,r); maxRow = Math.max(maxRow,r); minColumn = Math.min(minColumn,c); maxColumn = Math.max(maxColumn,c); if (seen[r][c]) continue;
            components++; int size = 0; ArrayDeque<Cell> pending = new ArrayDeque<>(); pending.addLast(new Cell(r,c)); seen[r][c] = true;
            while (!pending.isEmpty()) {
                Cell cell = pending.removeLast(); size++;
                for (Cell delta : List.of(new Cell(-1,0),new Cell(1,0),new Cell(0,-1),new Cell(0,1))) { int row = cell.row() + delta.row(), column = cell.column() + delta.column(); if (row >= 0 && row < h && column >= 0 && column < w && grid[row][column] == LineSolver.FILLED && !seen[row][column]) { seen[row][column] = true; pending.addLast(new Cell(row,column)); } }
            }
            largest = Math.max(largest,size);
        }
        List<String> symmetries = new ArrayList<>();
        for (Symmetry symmetry : List.of(new Symmetry("lr",false,true),new Symmetry("ud",true,false),new Symmetry("rot180",true,true))) {
            boolean same = true; for (int r = 0; r < h; r++) for (int c = 0; c < w; c++) if (grid[r][c] != grid[symmetry.rows() ? h - 1 - r : r][symmetry.columns() ? w - 1 - c : c]) same = false; if (same) symmetries.add(symmetry.name());
        }
        String box = filled == 0 ? "-" : Text.cat(minRow + 1,",",minColumn + 1,",",maxRow + 1,",",maxColumn + 1); return Text.cat("filled=",filled," components=",components," largest=",largest," bbox=",box," symmetry=",symmetries.isEmpty() ? "none" : String.join(",",symmetries));
    }
    static String evaluate(Puzzle puzzle, Analysis analysis) {
        if (puzzle.givens.isEmpty() || analysis.status.equals("multiple")) return ""; List<Integer> accepted = new ArrayList<>();
        for (int i = 0; i < puzzle.givens.size(); i++) { List<Given> others = new ArrayList<>(puzzle.givens); others.remove(i); String status = new Analysis(puzzle.rows,puzzle.columns,others).status; if (status.equals("unique") || !analysis.status.equals("unique") && status.equals("multiple")) accepted.add(i + 1); }
        return "givens " + (analysis.status.equals("unique") ? "redundant=" : "blame=") + Text.numbers(accepted);
    }
}
final class Grade {
    String result = "-";
    final List<String> lines = new ArrayList<>();
    Grade(Puzzle puzzle, Analysis analysis) {
        if (puzzle.answer == null) return; char[][] answer = puzzle.answer; int known = Propagation.determined(answer); boolean partial = known < puzzle.width * puzzle.height; List<Integer> rows = new ArrayList<>(), columns = new ArrayList<>(), givens = new ArrayList<>(); List<String> mismatches = new ArrayList<>();
        for (boolean row : new boolean[] { true,false }) for (int i = 0; i < (row ? puzzle.height : puzzle.width); i++) {
            char[] cells = Propagation.cells(answer,row,i); int[] clue = row ? puzzle.rows.get(i) : puzzle.columns.get(i); if (LineSolver.hasPlacement(cells,clue)) continue;
            (row ? rows : columns).add(i + 1); mismatches.add("mismatch " + Propagation.label(row,i) + " expected=" + Clues.text(clue,",") + (partial ? " cells=" + Render.stateString(cells) : " got=" + Clues.text(Clues.run(cells),",")));
        }
        Set<Cell> taken = new HashSet<>(); for (int i = 0; i < puzzle.givens.size(); i++) { Given g = puzzle.givens.get(i); taken.add(new Cell(g.row(),g.column())); if (answer[g.row()][g.column()] != LineSolver.UNKNOWN && answer[g.row()][g.column()] != g.value()) givens.add(i + 1); }
        boolean mismatch = !rows.isEmpty() || !columns.isEmpty() || !givens.isEmpty(); result = partial ? "partial" : mismatch ? "wrong" : "correct";
        String text = Text.cat("answer result=",result," known=",known," rows=",Text.numbers(rows)," columns=",Text.numbers(columns)," givens=",Text.numbers(givens));
        if (partial) {
            boolean extendable = false;
            if (!mismatch) { List<Given> combined = new ArrayList<>(puzzle.givens); for (int r = 0; r < puzzle.height; r++) for (int c = 0; c < puzzle.width; c++) if (answer[r][c] != LineSolver.UNKNOWN && !taken.contains(new Cell(r,c))) combined.add(new Given(r,c,answer[r][c])); String status = new Analysis(puzzle.rows,puzzle.columns,combined).status; extendable = status.equals("unique") || status.equals("multiple"); }
            text += " extendable=" + (extendable ? "yes" : "no");
        }
        if (analysis.status.equals("unique")) { int differs = 0; for (int r = 0; r < puzzle.height; r++) for (int c = 0; c < puzzle.width; c++) if (answer[r][c] != LineSolver.UNKNOWN && answer[r][c] != analysis.solutions.getFirst()[r][c]) differs++; text += " differs=" + differs; }
        lines.add(text); lines.addAll(mismatches);
    }
}
final class Report {
    final Puzzle puzzle;
    final Analysis analysis;
    final Grade grade;
    Report(Puzzle puzzle) { this.puzzle = puzzle; analysis = new Analysis(puzzle.rows,puzzle.columns,puzzle.givens); grade = new Grade(puzzle,analysis); }
    int score() { return analysis.lineSolves + 25 * analysis.guesses; }
    List<String> paragraph() {
        Puzzle p = puzzle; Analysis a = analysis;
        List<String> result = new ArrayList<>(List.of("PUZZLE " + p.name,Text.cat("size=",p.width,"x",p.height," givens=",p.givens.size()," status=",a.status," difficulty=",a.difficulty),"clues " + Measures.clueStatistics(p.rows,p.columns),Text.cat("simple known=",Propagation.determined(a.simpleGrid)," line_solves=",a.simple.steps.size()," result=",a.simpleResult),Text.cat("logic known=",Propagation.determined(a.logicGrid)," line_solves=",a.logic.steps.size()," result=",a.logicResult),"steps " + Measures.stepStatistics(a.logic)));
        if (p.width * p.height <= 49) result.add("trace " + a.logic.record());
        if (a.logicResult.equals("stuck")) result.add("stuck rows=" + Measures.unknownSummary(a.logicGrid,true) + " columns=" + Measures.unknownSummary(a.logicGrid,false));
        if (a.status.equals("contradiction")) { LineStep step = a.logic.conflict; result.add("conflict line=" + step.label() + " clue=" + Clues.text(step.row() ? p.rows.get(step.index()) : p.columns.get(step.index()),",") + " cells=" + Render.stateString(Propagation.cells(a.logicGrid,step.row(),step.index()))); }
        if (a.searchResult != null) {
            Search s = a.searchResult; result.add(Text.cat("search guesses=",s.guesses.size()," max_depth=",s.maxDepth," backtracks=",s.backtracks," solutions=",s.solutions.size()," line_solves=",s.lineSolves));
            for (Guess g : s.guesses) result.add(Text.cat("guess ",g.number()," depth=",g.depth()," cell=",Text.cell(g.row(),g.column())," value=",Render.stateChar(g.value())," solves=",g.solves()," known=",g.known()," result=",g.result()));
        }
        if (a.status.equals("multiple")) { List<Cell> cells = Text.differences(a.solutions.get(0),a.solutions.get(1)); result.add("differ count=" + cells.size() + " cells=" + cells.stream().map(c -> Text.cell(c.row(),c.column())).collect(Collectors.joining(" "))); }
        List<DisplayGrid> display = new ArrayList<>();
        if (a.status.equals("contradiction")) display.add(new DisplayGrid("partial",a.logicGrid));
        else { if (a.simpleResult.equals("stuck")) display.add(new DisplayGrid("simple",a.simpleGrid)); if (a.logicResult.equals("stuck")) display.add(new DisplayGrid("logic",a.logicGrid)); if (a.status.equals("multiple")) { display.add(new DisplayGrid("first",a.solutions.get(0))); display.add(new DisplayGrid("second",a.solutions.get(1))); } } result.addAll(Render.gridDisplay(display));
        if (a.status.equals("unique")) { result.add("sheet"); result.addAll(Render.answerSheet(p.rows,p.columns,a.solutions.getFirst())); result.add("picture " + Measures.features(a.solutions.getFirst())); }
        String evaluation = Measures.evaluate(p,a); if (!evaluation.isEmpty()) result.add(evaluation); result.addAll(grade.lines); return result;
    }
    String stats() { return Text.cat(puzzle.name,",",analysis.status,",",analysis.difficulty,",",puzzle.width,",",puzzle.height,",",puzzle.givens.size(),",",Propagation.determined(analysis.simpleGrid),",",Propagation.determined(analysis.logicGrid),",",analysis.lineSolves,",",analysis.guesses,",",analysis.maxDepth,",",analysis.solutions.size(),",",grade.result); }
}
final class Generation {
    final char[][] grid;
    final List<int[]> rows, columns;
    List<Given> givens = new ArrayList<>();
    final List<String> log = new ArrayList<>();
    final Analysis initial;
    Analysis last;
    Analysis analyze(List<Given> cells) { return new Analysis(rows,columns,cells); }
    String add(Cell cell) { char value = grid[cell.row()][cell.column()]; givens.add(new Given(cell.row(),cell.column(),value)); return "cell=" + Text.cell(cell.row(),cell.column()) + " value=" + Render.stateChar(value); }
    Generation(char[][] grid) {
        this.grid = grid; rows = Arrays.stream(grid).map(Clues::run).toList(); columns = IntStream.range(0,grid[0].length).mapToObj(c -> Clues.run(Propagation.cells(grid,false,c))).toList(); initial = analyze(givens); Analysis current = initial;
        while (current.status.equals("multiple")) { String text = add(Text.differences(current.solutions.get(0),current.solutions.get(1)).getFirst()); current = analyze(givens); log.add(Text.cat("# hint ",givens.size()," ",text," status=",current.status)); }
        for (Given given : List.copyOf(givens)) { List<Given> others = givens.stream().filter(g -> !g.equals(given)).toList(); if (analyze(others).status.equals("unique")) { givens = new ArrayList<>(others); log.add("# drop cell=" + Text.cell(given.row(),given.column())); } }
        last = analyze(givens); int count = 0;
        while (last.difficulty.equals("hard")) { String text = add(Search.guessCell(last.logicGrid)); last = analyze(givens); log.add(Text.cat("# logic hint ",++count," ",text," difficulty=",last.difficulty)); }
    }
    List<String> paragraph(String name, List<Report> reports) {
        String duplicate = reports.stream().filter(r -> Clues.equal(r.puzzle.rows,rows) && Clues.equal(r.puzzle.columns,columns)).map(r -> r.puzzle.name).findFirst().orElse("-");
        List<String> result = new ArrayList<>(List.of(Text.cat("# picture ",name," size=",columns.size(),"x",rows.size()," ",Measures.features(grid)),"# clues " + Measures.clueStatistics(rows,columns) + " duplicate_of=" + duplicate,Text.cat("# plain status=",initial.status," difficulty=",initial.difficulty," line_solves=",initial.lineSolves," guesses=",initial.guesses)));
        result.addAll(log); result.add(Text.cat("# final status=",last.status," difficulty=",last.difficulty," hints=",givens.size()," line_solves=",last.lineSolves," guesses=",last.guesses)); result.addAll(List.of("PUZZLE " + name,"SIZE " + columns.size() + " " + rows.size(),"ROWS"));
        for (int[] clue : rows) result.add(Clues.text(clue)); result.add("COLUMNS"); for (int[] clue : columns) result.add(Clues.text(clue));
        for (Given given : givens.stream().sorted(Comparator.comparingInt(Given::row).thenComparingInt(Given::column)).toList()) result.add(Text.cat("GIVEN ",given.row() + 1," ",given.column() + 1," ",Render.stateChar(given.value()))); result.add("END"); return result;
    }
}
public class Main {
    static List<Report> processPuzzles(List<Puzzle> puzzles) throws IOException {
        Set<String> names = new HashSet<>(); List<Report> reports = new ArrayList<>(); List<List<String>> paragraphs = new ArrayList<>(); List<String> stats = new ArrayList<>(List.of("puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer"));
        for (Puzzle puzzle : puzzles) {
            String error = puzzle.validate(names); names.add(puzzle.name);
            if (!error.isEmpty()) { paragraphs.add(List.of("PUZZLE " + puzzle.name,"error " + error)); stats.add(puzzle.name + ",invalid" + ",-".repeat(11)); }
            else { Report report = new Report(puzzle); reports.add(report); paragraphs.add(report.paragraph()); stats.add(report.stats()); }
        }
        Map<String, Integer> difficulty = Map.of("easy",0,"medium",1,"hard",2); List<Report> ranked = reports.stream().filter(r -> r.analysis.status.equals("unique")).sorted(Comparator.comparingInt((Report r) -> difficulty.get(r.analysis.difficulty)).thenComparingInt(Report::score).thenComparing(r -> r.puzzle.name)).toList(); List<String> ranking = new ArrayList<>(List.of("RANKING"));
        for (int i = 0; i < ranked.size(); i++) { Report r = ranked.get(i); ranking.add(Text.cat("rank ",i + 1," ",r.puzzle.name," ",r.analysis.difficulty," score=",r.score()," size=",r.puzzle.width,"x",r.puzzle.height)); } paragraphs.add(ranking);
        Map<String, Integer> counts = new HashMap<>(); int solves = 0, guesses = 0; for (Report report : reports) { counts.merge(report.analysis.status,1,Integer::sum); counts.merge(report.analysis.difficulty,1,Integer::sum); solves += report.analysis.lineSolves; guesses += report.analysis.guesses; }
        paragraphs.add(List.of(Text.cat("SUMMARY puzzles=",puzzles.size()," invalid=",puzzles.size() - reports.size()," contradiction=",counts.getOrDefault("contradiction",0)," none=",counts.getOrDefault("none",0)," unique=",counts.getOrDefault("unique",0)," multiple=",counts.getOrDefault("multiple",0)," easy=",counts.getOrDefault("easy",0)," medium=",counts.getOrDefault("medium",0)," hard=",counts.getOrDefault("hard",0)," line_solves=",solves," guesses=",guesses))); Text.write("solutions.txt",Text.paragraphs(paragraphs)); Text.write("stats.csv",stats); return reports;
    }
    static void processPictures(List<List<String>> pictures, List<Report> reports) throws IOException {
        Set<String> names = new HashSet<>(); List<List<String>> paragraphs = new ArrayList<>(); int valid = 0, unique = 0, logic = 0, hinted = 0, hints = 0;
        for (List<String> block : pictures) {
            String name = block.getFirst().substring(8), error = ""; char[][] grid = block.subList(1,block.size()).stream().map(String::toCharArray).toArray(char[][]::new);
            if (!Text.validName(name)) error = "bad name"; else if (names.contains(name)) error = "duplicate name"; else if (grid.length < 1 || grid.length > 30) error = "bad height";
            else for (int i = 0; i < grid.length; i++) { boolean bad = grid[i].length < 1 || grid[i].length > 30 || grid[i].length != grid[0].length; for (char cell : grid[i]) if (cell != '#' && cell != '.') bad = true; if (bad) { error = "bad row " + (i + 1); break; } }
            names.add(name); if (!error.isEmpty()) { paragraphs.add(List.of("# picture " + name + " error " + error)); continue; }
            Generation generation = new Generation(grid); valid++; if (generation.initial.status.equals("unique")) unique++; if (generation.initial.difficulty.equals("easy") || generation.initial.difficulty.equals("medium")) logic++; if (!generation.givens.isEmpty()) hinted++; hints += generation.givens.size(); paragraphs.add(generation.paragraph(name,reports));
        }
        paragraphs.add(List.of(Text.cat("# SUMMARY pictures=",pictures.size()," invalid=",pictures.size() - valid," unique=",unique," line_logic=",logic," hinted=",hinted," hints=",hints))); Text.write("generated.txt",Text.paragraphs(paragraphs));
    }
    public static void main(String[] args) throws IOException {
        Files.createDirectories(Path.of("output")); List<Report> reports = processPuzzles(Text.readBlocks("input/puzzles.txt").stream().map(Puzzle::new).toList()); processPictures(Text.readBlocks("input/pictures.txt"),reports);
    }
}
