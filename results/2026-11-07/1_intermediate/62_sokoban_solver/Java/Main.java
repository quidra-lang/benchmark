import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.OptionalInt;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

public class Main {
    static final String DIRECTIONS = "udlr";
    static final int[][] DELTAS = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
    static final Map<String, String> TURNS = Map.of(
            "ROT90", "rlud",
            "ROT180", "durl",
            "ROT270", "lrdu",
            "FLIPH", "udrl",
            "FLIPV", "dulr");
    static final String STEP_LETTERS = "udlrUDLR";
    static final String LEVEL_CHARACTERS = "#-.$*@+";
    static final int MAX_SIDE = 10;
    static final int MAX_LIMIT = 100000;
    static final int UNDEFINED = -1;
    static final int NO_PARENT = -1;
    static final Pattern NUMBER_WORD = Pattern.compile("0|[1-9][0-9]{0,5}");
    static final Pattern NAME_WORD = Pattern.compile("[a-z]{1,8}");

    enum Kind { NUMBER, STEPS, DIRECTION, NAME, TRANSFORM, TEXT }

    enum Command {
        IMPORT(Kind.TEXT),
        VALID,
        INFO,
        SHOW,
        EXPORT,
        MOVE(Kind.STEPS),
        PUSH(Kind.NUMBER, Kind.NUMBER, Kind.DIRECTION),
        BRING(Kind.NUMBER, Kind.NUMBER, Kind.NUMBER, Kind.NUMBER),
        PATH(Kind.NUMBER, Kind.NUMBER),
        UNDO(Kind.NUMBER),
        REDO(Kind.NUMBER),
        RESET,
        STATUS,
        HISTORY,
        BOXES,
        REACH,
        DEADSQUARES,
        DEADLOCK,
        BOUND,
        SAVE(Kind.NAME),
        RESTORE(Kind.NAME),
        CHECK(Kind.STEPS),
        SOLVE(Kind.NUMBER),
        HINT(Kind.NUMBER),
        PLAY,
        TRANSFORM(Kind.TRANSFORM);

        final List<Kind> kinds;

        Command(Kind... kinds) {
            this.kinds = List.of(kinds);
        }

        static Optional<Command> named(String name) {
            return Arrays.stream(values())
                    .filter(command -> command.name().equals(name))
                    .findFirst();
        }
    }

    static class CommandException extends RuntimeException {
        CommandException(String message) {
            super(message);
        }
    }

    static class StepException extends RuntimeException {
        StepException(String reason) {
            super(reason);
        }
    }

    record Position(int player, List<Integer> boxes) {}

    record Step(Position position, char letter) {}

    record Simulation(Position position, String letters, String failure) {}

    record CameFrom(int cell, char direction) {}

    record Push(int box, char direction) {}

    record SearchNode(List<Integer> boxes, int representative, int parent, Push push) {}

    record SearchState(List<Integer> boxes, int representative) {}

    record SearchResult(String outcome, int expanded, int states, String notation) {}

    record Summary(String text, String notation) {}

    record Snapshot(Position position, String history) {}

    record Solution(String notation, Position position) {}

    record Assignment(List<Integer> order, List<Integer> pushes, int total) {}

    record LoadedLevel(Level level, Position position) {}

    static Optional<String> decode(String text, String allowed) {
        StringBuilder result = new StringBuilder();
        int index = 0;
        while (index < text.length()) {
            int start = index;
            while (index < text.length() && Character.isDigit(text.charAt(index))) {
                index++;
            }
            String count = text.substring(start, index);
            if (count.length() > 2 || count.startsWith("0") || index == text.length()) {
                return Optional.empty();
            }
            char symbol = text.charAt(index);
            if (allowed.indexOf(symbol) < 0) {
                return Optional.empty();
            }
            result.repeat(symbol, count.isEmpty() ? 1 : Integer.parseInt(count));
            index++;
        }
        return Optional.of(result.toString());
    }

    static String encode(String text) {
        StringBuilder result = new StringBuilder();
        int start = 0;
        while (start < text.length()) {
            int end = start;
            while (end < text.length() && text.charAt(end) == text.charAt(start)) {
                end++;
            }
            int run = end - start;
            if (run > 1) {
                result.append(run);
            }
            result.append(text.charAt(start));
            start = end;
        }
        return result.toString();
    }

    static String stepSequence(String word) {
        return decode(word, STEP_LETTERS).orElseThrow().toLowerCase();
    }

    static boolean validArgument(Kind kind, String text) {
        return switch (kind) {
            case NUMBER -> NUMBER_WORD.matcher(text).matches();
            case STEPS -> decode(text, STEP_LETTERS).isPresent();
            case DIRECTION -> text.length() == 1 && DIRECTIONS.contains(text);
            case NAME -> NAME_WORD.matcher(text).matches();
            case TRANSFORM -> TURNS.containsKey(text);
            case TEXT -> true;
        };
    }

    static int pushCount(CharSequence letters) {
        return (int) letters.chars().filter(Character::isUpperCase).count();
    }

    static String turnLetters(CharSequence letters, String kind) {
        String turn = TURNS.get(kind);
        StringBuilder turned = new StringBuilder();
        for (int index = 0; index < letters.length(); index++) {
            char letter = letters.charAt(index);
            char direction = turn.charAt(DIRECTIONS.indexOf(Character.toLowerCase(letter)));
            turned.append(
                    Character.isUpperCase(letter) ? Character.toUpperCase(direction) : direction);
        }
        return turned.toString();
    }

    static List<Integer> moveBox(List<Integer> boxes, int source, int destination) {
        return boxes.stream().map(box -> box == source ? destination : box).sorted().toList();
    }

    static String counted(String label, CharSequence letters) {
        return letters.isEmpty() ? label + " 0" : label + " " + letters.length() + " " + letters;
    }

    static int countTrue(boolean[] flags) {
        int count = 0;
        for (boolean flag : flags) {
            if (flag) {
                count++;
            }
        }
        return count;
    }

    static int firstTrue(boolean[] flags) {
        int index = 0;
        while (!flags[index]) {
            index++;
        }
        return index;
    }

    static List<List<Integer>> permutations(List<Integer> items) {
        if (items.isEmpty()) {
            return List.of(List.of());
        }
        List<List<Integer>> result = new ArrayList<>();
        for (Integer item : items) {
            List<Integer> rest = new ArrayList<>(items);
            rest.remove(item);
            for (List<Integer> tail : permutations(rest)) {
                List<Integer> permutation = new ArrayList<>(List.of(item));
                permutation.addAll(tail);
                result.add(permutation);
            }
        }
        return result;
    }

    static boolean[] findInterior(int height, int width, boolean[] walls, int start) {
        boolean[] interior = new boolean[height * width];
        interior[start] = true;
        Deque<Integer> stack = new ArrayDeque<>();
        stack.push(start);
        while (!stack.isEmpty()) {
            int cell = stack.pop();
            int row = cell / width;
            int column = cell % width;
            for (int[] delta : DELTAS) {
                int nextRow = row + delta[0];
                int nextColumn = column + delta[1];
                if (nextRow >= 0 && nextRow < height && nextColumn >= 0 && nextColumn < width) {
                    int neighbor = nextRow * width + nextColumn;
                    if (!walls[neighbor] && !interior[neighbor]) {
                        interior[neighbor] = true;
                        stack.push(neighbor);
                    }
                }
            }
        }
        return interior;
    }

    static class Level {
        final int height;
        final int width;
        final int size;
        final boolean[] walls;
        final boolean[] goals;
        final boolean[] interior;
        final int[] offsets;
        final List<Integer> goalCells;
        String reason;
        List<int[]> distances = List.of();
        boolean[] dead;

        Level(int height, int width, boolean[] walls, boolean[] goals, boolean[] interior) {
            this.height = height;
            this.width = width;
            this.size = height * width;
            this.walls = walls;
            this.goals = goals;
            this.interior = interior;
            this.offsets = Arrays.stream(DELTAS)
                    .mapToInt(delta -> delta[0] * width + delta[1])
                    .toArray();
            this.goalCells = IntStream.range(0, size).filter(cell -> goals[cell]).boxed().toList();
            this.dead = new boolean[size];
        }

        int offsetOf(char direction) {
            return offsets[DIRECTIONS.indexOf(direction)];
        }

        String cellText(int cell) {
            return (cell / width + 1) + " " + (cell % width + 1);
        }

        int cellAt(int row, int column) {
            return (row - 1) * width + column - 1;
        }

        boolean contains(int row, int column) {
            return 1 <= row && row <= height && 1 <= column && column <= width;
        }

        boolean onBorder(int cell) {
            int row = cell / width;
            int column = cell % width;
            return row == 0 || row == height - 1 || column == 0 || column == width - 1;
        }

        String invalidity(int players, List<Integer> boxes) {
            if (players != 1) {
                return "players " + players;
            }
            if (boxes.isEmpty()) {
                return "no boxes";
            }
            if (boxes.size() != goalCells.size()) {
                return "boxes " + boxes.size() + " goals " + goalCells.size();
            }
            for (int cell = 0; cell < size; cell++) {
                if (interior[cell] && onBorder(cell)) {
                    return "open " + cellText(cell);
                }
            }
            for (int cell = 0; cell < size; cell++) {
                if ((goals[cell] || boxes.contains(cell)) && !interior[cell]) {
                    return "outside " + cellText(cell);
                }
            }
            return null;
        }

        void analyze() {
            distances = goalCells.stream().map(this::pushDistances).toList();
            for (int cell = 0; cell < size; cell++) {
                dead[cell] = interior[cell] && goalDistance(cell).isEmpty();
            }
        }

        int[] pushDistances(int goal) {
            int[] distance = new int[size];
            Arrays.fill(distance, UNDEFINED);
            distance[goal] = 0;
            Deque<Integer> queue = new ArrayDeque<>();
            queue.add(goal);
            while (!queue.isEmpty()) {
                int cell = queue.poll();
                for (int offset : offsets) {
                    int box = cell - offset;
                    if (interior[box] && interior[box - offset] && distance[box] == UNDEFINED) {
                        distance[box] = distance[cell] + 1;
                        queue.add(box);
                    }
                }
            }
            return distance;
        }

        OptionalInt goalDistance(int cell) {
            return distances.stream()
                    .mapToInt(distance -> distance[cell])
                    .filter(distance -> distance != UNDEFINED)
                    .min();
        }

        int boxesOnGoals(List<Integer> boxes) {
            return (int) boxes.stream().filter(box -> goals[box]).count();
        }

        boolean solved(List<Integer> boxes) {
            return boxesOnGoals(boxes) == boxes.size();
        }

        boolean[] reachable(int player, List<Integer> boxes) {
            boolean[] seen = new boolean[size];
            seen[player] = true;
            Deque<Integer> stack = new ArrayDeque<>();
            stack.push(player);
            while (!stack.isEmpty()) {
                int cell = stack.pop();
                for (int offset : offsets) {
                    int neighbor = cell + offset;
                    if (interior[neighbor] && !seen[neighbor] && !boxes.contains(neighbor)) {
                        seen[neighbor] = true;
                        stack.push(neighbor);
                    }
                }
            }
            return seen;
        }

        int representative(int player, List<Integer> boxes) {
            return firstTrue(reachable(player, boxes));
        }

        String walkPath(int start, int target, List<Integer> boxes) {
            CameFrom[] cameFrom = new CameFrom[size];
            Deque<Integer> queue = new ArrayDeque<>();
            queue.add(start);
            while (!queue.isEmpty()) {
                int cell = queue.poll();
                for (char direction : DIRECTIONS.toCharArray()) {
                    int neighbor = cell + offsetOf(direction);
                    if (interior[neighbor] && !boxes.contains(neighbor) && neighbor != start
                            && cameFrom[neighbor] == null) {
                        cameFrom[neighbor] = new CameFrom(cell, direction);
                        queue.add(neighbor);
                    }
                }
            }
            StringBuilder directions = new StringBuilder();
            for (int cell = target; cell != start; cell = cameFrom[cell].cell()) {
                directions.append(cameFrom[cell].direction());
            }
            return directions.reverse().toString();
        }

        Step step(Position position, char direction) {
            int offset = offsetOf(direction);
            int target = position.player() + offset;
            if (walls[target]) {
                throw new StepException("wall");
            }
            if (!position.boxes().contains(target)) {
                return new Step(new Position(target, position.boxes()), direction);
            }
            int beyond = target + offset;
            if (walls[beyond] || position.boxes().contains(beyond)) {
                throw new StepException("blocked");
            }
            List<Integer> boxes = moveBox(position.boxes(), target, beyond);
            return new Step(new Position(target, boxes), Character.toUpperCase(direction));
        }

        boolean pushable(int box, char direction, List<Integer> boxes, boolean[] reachable) {
            int offset = offsetOf(direction);
            int destination = box + offset;
            return reachable[box - offset] && interior[destination] && !boxes.contains(destination);
        }

        boolean sideBlocked(int box, int[] sides, List<Integer> boxes, List<Integer> assumed) {
            if (Arrays.stream(sides).anyMatch(side -> walls[side] || assumed.contains(side))) {
                return true;
            }
            if (Arrays.stream(sides).allMatch(side -> dead[side])) {
                return true;
            }
            List<Integer> extended = new ArrayList<>(assumed);
            extended.add(box);
            return Arrays.stream(sides)
                    .anyMatch(side -> boxes.contains(side) && frozen(side, boxes, extended));
        }

        boolean frozen(int box, List<Integer> boxes, List<Integer> assumed) {
            int[] horizontal = {box + offsetOf('l'), box + offsetOf('r')};
            int[] vertical = {box + offsetOf('u'), box + offsetOf('d')};
            return sideBlocked(box, horizontal, boxes, assumed)
                    && sideBlocked(box, vertical, boxes, assumed);
        }

        boolean hasFrozenBox(List<Integer> boxes) {
            return boxes.stream().anyMatch(box -> !goals[box] && frozen(box, boxes, List.of()));
        }

        List<String> splitRows(String symbols) {
            List<String> rows = new ArrayList<>();
            for (int start = 0; start < size; start += width) {
                rows.add(symbols.substring(start, start + width));
            }
            return rows;
        }

        char symbol(int cell, Position position) {
            if (walls[cell]) {
                return '#';
            }
            if (cell == position.player()) {
                return goals[cell] ? '+' : '@';
            }
            if (position.boxes().contains(cell)) {
                return goals[cell] ? '*' : '$';
            }
            return goals[cell] ? '.' : '-';
        }

        List<String> render(Position position) {
            StringBuilder symbols = new StringBuilder();
            for (int cell = 0; cell < size; cell++) {
                symbols.append(symbol(cell, position));
            }
            return splitRows(symbols.toString());
        }

        char deadSymbol(int cell) {
            if (walls[cell]) {
                return '#';
            }
            if (goals[cell]) {
                return '.';
            }
            return dead[cell] ? 'x' : '-';
        }

        List<String> deadMap() {
            StringBuilder symbols = new StringBuilder();
            for (int cell = 0; cell < size; cell++) {
                symbols.append(deadSymbol(cell));
            }
            return splitRows(symbols.toString());
        }

        int mapCell(String kind, int cell) {
            int row = cell / width;
            int column = cell % width;
            int lastRow = height - 1;
            int lastColumn = width - 1;
            return switch (kind) {
                case "ROT90" -> column * height + lastRow - row;
                case "ROT180" -> (lastRow - row) * width + lastColumn - column;
                case "ROT270" -> (lastColumn - column) * height + row;
                case "FLIPH" -> row * width + lastColumn - column;
                default -> (lastRow - row) * width + column;
            };
        }

        Position mapPosition(String kind, Position position) {
            List<Integer> boxes = position.boxes().stream()
                    .map(box -> mapCell(kind, box))
                    .sorted()
                    .toList();
            return new Position(mapCell(kind, position.player()), boxes);
        }

        Level transformed(String kind) {
            boolean rotated = kind.equals("ROT90") || kind.equals("ROT270");
            boolean[] movedWalls = new boolean[size];
            boolean[] movedGoals = new boolean[size];
            boolean[] movedInterior = new boolean[size];
            for (int cell = 0; cell < size; cell++) {
                int moved = mapCell(kind, cell);
                movedWalls[moved] = walls[cell];
                movedGoals[moved] = goals[cell];
                movedInterior[moved] = interior[cell];
            }
            Level level = new Level(rotated ? width : height, rotated ? height : width,
                    movedWalls, movedGoals, movedInterior);
            level.analyze();
            return level;
        }
    }

    static LoadedLevel buildLevel(List<String> rows) {
        int height = rows.size();
        int width = rows.get(0).length();
        String cells = String.join("", rows);
        boolean[] walls = new boolean[cells.length()];
        boolean[] goals = new boolean[cells.length()];
        List<Integer> players = new ArrayList<>();
        List<Integer> boxes = new ArrayList<>();
        for (int cell = 0; cell < cells.length(); cell++) {
            char symbol = cells.charAt(cell);
            walls[cell] = symbol == '#';
            goals[cell] = ".*+".indexOf(symbol) >= 0;
            if ("@+".indexOf(symbol) >= 0) {
                players.add(cell);
            }
            if ("$*".indexOf(symbol) >= 0) {
                boxes.add(cell);
            }
        }
        boolean[] interior = players.size() == 1
                ? findInterior(height, width, walls, players.get(0))
                : new boolean[cells.length()];
        Level level = new Level(height, width, walls, goals, interior);
        level.reason = level.invalidity(players.size(), boxes);
        if (level.reason == null) {
            level.analyze();
        }
        int player = players.isEmpty() ? -1 : players.get(0);
        return new LoadedLevel(level, new Position(player, List.copyOf(boxes)));
    }

    static List<Push> solutionPushes(List<SearchNode> nodes) {
        List<Push> pushes = new ArrayList<>();
        for (SearchNode node = nodes.getLast(); node.parent() != NO_PARENT;
                node = nodes.get(node.parent())) {
            pushes.add(node.push());
        }
        return pushes.reversed();
    }

    static String solutionNotation(Level level, Position start, List<Push> pushes) {
        Position position = start;
        StringBuilder notation = new StringBuilder();
        for (Push push : pushes) {
            int offset = level.offsetOf(push.direction());
            int behind = push.box() - offset;
            notation.append(level.walkPath(position.player(), behind, position.boxes()));
            notation.append(Character.toUpperCase(push.direction()));
            List<Integer> boxes = moveBox(position.boxes(), push.box(), push.box() + offset);
            position = new Position(push.box(), boxes);
        }
        return notation.toString();
    }

    static SearchResult pushSearch(Level level, Position start, List<Integer> fixed,
            OptionalInt target, boolean pruning, OptionalInt limit) {
        int startRepresentative = level.representative(start.player(), start.boxes());
        List<SearchNode> nodes = new ArrayList<>();
        nodes.add(new SearchNode(start.boxes(), startRepresentative, NO_PARENT, null));
        Set<SearchState> known = new HashSet<>();
        known.add(new SearchState(start.boxes(), startRepresentative));
        int expanded = 0;
        while (expanded < nodes.size()) {
            if (limit.isPresent() && expanded == limit.getAsInt()) {
                return new SearchResult("limit", expanded, nodes.size(), "");
            }
            SearchNode node = nodes.get(expanded);
            expanded++;
            boolean[] reachable = level.reachable(node.representative(), node.boxes());
            for (int box : node.boxes()) {
                if (fixed.contains(box)) {
                    continue;
                }
                for (char direction : DIRECTIONS.toCharArray()) {
                    if (!level.pushable(box, direction, node.boxes(), reachable)) {
                        continue;
                    }
                    int destination = box + level.offsetOf(direction);
                    List<Integer> boxes = moveBox(node.boxes(), box, destination);
                    if (pruning && (level.dead[destination] || level.hasFrozenBox(boxes))) {
                        continue;
                    }
                    int representative = level.representative(box, boxes);
                    if (!known.add(new SearchState(boxes, representative))) {
                        continue;
                    }
                    Push push = new Push(box, direction);
                    nodes.add(new SearchNode(boxes, representative, expanded - 1, push));
                    boolean reached = target.isPresent()
                            ? destination == target.getAsInt()
                            : level.solved(boxes);
                    if (reached) {
                        String notation = solutionNotation(level, start, solutionPushes(nodes));
                        return new SearchResult("found", expanded, nodes.size(), notation);
                    }
                }
            }
        }
        return new SearchResult("no solution", expanded, nodes.size(), "");
    }

    static class Sokoban {
        final StringBuilder output = new StringBuilder();
        private Level level;
        private Position initial;
        private Position current;
        private StringBuilder history;
        private StringBuilder redoList;
        private Map<String, Snapshot> snapshots;
        private Solution solution;

        Sokoban(List<String> rows) {
            load(rows);
        }

        private void emit(Object... parts) {
            String line = Arrays.stream(parts)
                    .map(String::valueOf)
                    .collect(Collectors.joining(" "));
            output.append(line).append('\n');
        }

        private void load(List<String> rows) {
            LoadedLevel loaded = buildLevel(rows);
            level = loaded.level();
            initial = loaded.position();
            current = initial;
            history = new StringBuilder();
            redoList = new StringBuilder();
            snapshots = new HashMap<>();
            solution = null;
        }

        private int cellArgument(List<String> arguments, int index) {
            int row = Integer.parseInt(arguments.get(index));
            int column = Integer.parseInt(arguments.get(index + 1));
            return level.cellAt(row, column);
        }

        private Simulation simulate(String directions) {
            Position position = current;
            StringBuilder letters = new StringBuilder();
            try {
                for (char direction : directions.toCharArray()) {
                    Step step = level.step(position, direction);
                    position = step.position();
                    letters.append(step.letter());
                }
            } catch (StepException failure) {
                String reason = "step " + (letters.length() + 1) + " " + failure.getMessage();
                return new Simulation(position, letters.toString(), reason);
            }
            return new Simulation(position, letters.toString(), null);
        }

        private Simulation takeSteps(String directions) {
            Simulation simulation = simulate(directions);
            current = simulation.position();
            history.append(simulation.letters());
            if (!simulation.letters().isEmpty()) {
                redoList = new StringBuilder();
            }
            return simulation;
        }

        private String progress(List<Integer> boxes) {
            int onGoals = level.boxesOnGoals(boxes);
            String text = "goals " + onGoals + "/" + boxes.size();
            return onGoals == boxes.size() ? text + " solved" : text;
        }

        private Summary searchSolution(int limit) {
            if (level.solved(current.boxes())) {
                return new Summary("already solved", null);
            }
            SearchResult result = pushSearch(level, current, List.of(), OptionalInt.empty(), true,
                    OptionalInt.of(limit));
            String counts = "expanded " + result.expanded() + " states " + result.states();
            if (!result.outcome().equals("found")) {
                return new Summary(result.outcome() + " " + counts, null);
            }
            String notation = result.notation();
            String text = "solution pushes " + pushCount(notation) + " moves " + notation.length()
                    + " " + counts;
            return new Summary(text, notation);
        }

        private void loadRows(int width, List<String> rows) {
            for (int number = 1; number <= rows.size(); number++) {
                String row = rows.get(number - 1);
                boolean known = row.chars()
                        .allMatch(symbol -> LEVEL_CHARACTERS.indexOf(symbol) >= 0);
                if (row.length() != width || !known) {
                    throw new CommandException("bad row " + number);
                }
            }
            load(rows);
            emit("loaded", rows.size() + "x" + width);
        }

        private void importLevel(String text) {
            List<String> rows = new ArrayList<>();
            for (String part : text.split("\\|", -1)) {
                Optional<String> row = decode(part, LEVEL_CHARACTERS);
                if (row.isEmpty()) {
                    throw new CommandException("bad level");
                }
                rows.add(row.get());
            }
            if (rows.size() > MAX_SIDE) {
                throw new CommandException("bad level");
            }
            int width = rows.get(0).length();
            boolean uneven = rows.stream().anyMatch(row -> row.length() != width);
            if (uneven || width < 1 || width > MAX_SIDE) {
                throw new CommandException("bad level");
            }
            load(rows);
            emit("loaded", rows.size() + "x" + width);
        }

        private void valid() {
            if (level.reason == null) {
                emit("valid");
            } else {
                emit("invalid", level.reason);
            }
        }

        private void info() {
            emit("size", level.height + "x" + level.width, "walls", countTrue(level.walls),
                    "cells", countTrue(level.interior), "boxes", current.boxes().size(),
                    "dead", countTrue(level.dead));
        }

        private void show() {
            for (String row : level.render(current)) {
                emit(row);
            }
        }

        private void exportLevel() {
            List<String> rows = level.render(current);
            emit("level", rows.stream().map(Main::encode).collect(Collectors.joining("|")));
        }

        private void move(String word) {
            Simulation simulation = takeSteps(stepSequence(word));
            if (!simulation.letters().isEmpty()) {
                emit("moved", simulation.letters());
            }
            if (simulation.failure() != null) {
                throw new CommandException(simulation.failure());
            }
        }

        private void push(int box, char direction) {
            int offset = level.offsetOf(direction);
            List<Integer> boxes = current.boxes();
            if (!boxes.contains(box)) {
                throw new CommandException("no box");
            }
            int destination = box + offset;
            if (!level.interior[destination] || boxes.contains(destination)) {
                throw new CommandException("blocked");
            }
            if (!level.reachable(current.player(), boxes)[box - offset]) {
                throw new CommandException("unreachable");
            }
            String path = level.walkPath(current.player(), box - offset, boxes);
            emit("pushed", takeSteps(path + direction).letters());
        }

        private void bring(int source, int target) {
            List<Integer> boxes = current.boxes();
            if (!boxes.contains(source)) {
                throw new CommandException("no box");
            }
            if (source == target) {
                emit("brought", 0);
                return;
            }
            List<Integer> fixed = boxes.stream().filter(box -> box != source).toList();
            SearchResult result = pushSearch(level, current, fixed, OptionalInt.of(target), false,
                    OptionalInt.empty());
            if (!result.outcome().equals("found")) {
                throw new CommandException("no route");
            }
            takeSteps(result.notation().toLowerCase());
            emit("brought", pushCount(result.notation()), result.notation());
        }

        private void path(int target) {
            if (!level.reachable(current.player(), current.boxes())[target]) {
                throw new CommandException("unreachable");
            }
            String path = level.walkPath(current.player(), target, current.boxes());
            emit(counted("path", takeSteps(path).letters()));
        }

        private void undo(int requested) {
            if (history.isEmpty()) {
                throw new CommandException("nothing to undo");
            }
            int count = Math.min(requested, history.length());
            for (int index = 0; index < count; index++) {
                char letter = history.charAt(history.length() - 1);
                history.deleteCharAt(history.length() - 1);
                char direction = Character.toLowerCase(letter);
                int offset = level.offsetOf(direction);
                int player = current.player();
                List<Integer> boxes = Character.isUpperCase(letter)
                        ? moveBox(current.boxes(), player + offset, player)
                        : current.boxes();
                current = new Position(player - offset, boxes);
                redoList.append(direction);
            }
            emit("undone", count);
        }

        private void redo(int requested) {
            if (redoList.isEmpty()) {
                throw new CommandException("nothing to redo");
            }
            int count = Math.min(requested, redoList.length());
            for (int index = 0; index < count; index++) {
                char direction = redoList.charAt(redoList.length() - 1);
                redoList.deleteCharAt(redoList.length() - 1);
                Step step = level.step(current, direction);
                current = step.position();
                history.append(step.letter());
            }
            emit("redone", count);
        }

        private void reset() {
            current = initial;
            history = new StringBuilder();
            redoList = new StringBuilder();
            emit("reset");
        }

        private void status() {
            emit("moves", history.length(), "pushes", pushCount(history),
                    progress(current.boxes()));
        }

        private void showHistory() {
            emit(counted("history", history));
        }

        private void showBoxes() {
            List<Integer> boxes = current.boxes();
            boolean[] reachable = level.reachable(current.player(), boxes);
            emit("boxes", boxes.size());
            for (int box : boxes) {
                OptionalInt distance = level.goalDistance(box);
                StringBuilder directions = new StringBuilder();
                for (char direction : DIRECTIONS.toCharArray()) {
                    if (level.pushable(box, direction, boxes, reachable)) {
                        directions.append(direction);
                    }
                }
                emit("box", level.cellText(box),
                        distance.isPresent() ? String.valueOf(distance.getAsInt()) : "dead",
                        directions.isEmpty() ? "-" : directions);
            }
        }

        private void reach() {
            boolean[] reachable = level.reachable(current.player(), current.boxes());
            emit("reach", countTrue(reachable), "first", level.cellText(firstTrue(reachable)));
        }

        private void deadSquares() {
            emit("dead", countTrue(level.dead));
            for (String row : level.deadMap()) {
                emit(row);
            }
        }

        private void deadlock() {
            List<Integer> boxes = current.boxes();
            for (int box : boxes) {
                if (level.dead[box]) {
                    emit("deadlock", "dead", level.cellText(box));
                    return;
                }
            }
            for (int box : boxes) {
                if (!level.goals[box] && level.frozen(box, boxes, List.of())) {
                    emit("deadlock", "frozen", level.cellText(box));
                    return;
                }
            }
            emit("no deadlock");
        }

        private void bound() {
            List<Integer> boxes = current.boxes();
            List<Integer> goalIndices = IntStream.range(0, level.goalCells.size()).boxed().toList();
            Assignment best = null;
            for (List<Integer> order : permutations(goalIndices)) {
                List<Integer> pushes = new ArrayList<>();
                for (int index = 0; index < boxes.size(); index++) {
                    pushes.add(level.distances.get(order.get(index))[boxes.get(index)]);
                }
                if (pushes.contains(UNDEFINED)) {
                    continue;
                }
                int total = pushes.stream().mapToInt(Integer::intValue).sum();
                if (best == null || total < best.total()) {
                    best = new Assignment(order, pushes, total);
                }
            }
            if (best == null) {
                emit("bound", "none");
                return;
            }
            emit("bound", best.total());
            for (int index = 0; index < boxes.size(); index++) {
                int goal = level.goalCells.get(best.order().get(index));
                emit("box", level.cellText(boxes.get(index)), "goal", level.cellText(goal),
                        "pushes", best.pushes().get(index));
            }
        }

        private void save(String name) {
            snapshots.put(name, new Snapshot(current, history.toString()));
            emit("saved", name, "moves", history.length());
        }

        private void restore(String name) {
            Snapshot snapshot = snapshots.get(name);
            if (snapshot == null) {
                throw new CommandException("no snapshot " + name);
            }
            current = snapshot.position();
            history = new StringBuilder(snapshot.history());
            redoList = new StringBuilder();
            emit("restored", name, "moves", history.length());
        }

        private void check(String word) {
            Simulation simulation = simulate(stepSequence(word));
            if (simulation.failure() != null) {
                emit("check", "fail", simulation.failure());
                return;
            }
            String letters = simulation.letters();
            emit("check", "ok", "moves", letters.length(), "pushes", pushCount(letters),
                    progress(simulation.position().boxes()));
        }

        private void solve(int limit) {
            Summary summary = searchSolution(limit);
            emit(summary.text());
            solution = null;
            if (summary.notation() != null) {
                emit(summary.notation());
                solution = new Solution(summary.notation(), current);
            }
        }

        private void hint(int limit) {
            Summary summary = searchSolution(limit);
            String notation = summary.notation();
            if (notation == null) {
                emit(summary.text());
                return;
            }
            int end = 0;
            while (Character.isLowerCase(notation.charAt(end))) {
                end++;
            }
            String part = notation.substring(0, end + 1);
            takeSteps(part.toLowerCase());
            emit("hint", part);
        }

        private void play() {
            if (solution == null || !solution.position().equals(current)) {
                throw new CommandException("no solution");
            }
            String notation = solution.notation();
            takeSteps(notation.toLowerCase());
            emit("played", "pushes", pushCount(notation), "moves", notation.length());
        }

        private void transform(String kind) {
            Level old = level;
            level = old.transformed(kind);
            initial = old.mapPosition(kind, initial);
            current = old.mapPosition(kind, current);
            history = new StringBuilder(turnLetters(history, kind));
            redoList = new StringBuilder(turnLetters(redoList, kind));
            snapshots.replaceAll((name, snapshot) -> new Snapshot(
                    old.mapPosition(kind, snapshot.position()),
                    turnLetters(snapshot.history(), kind)));
            if (solution != null) {
                solution = new Solution(turnLetters(solution.notation(), kind),
                        old.mapPosition(kind, solution.position()));
            }
            emit("transformed", level.height + "x" + level.width);
        }

        private void checkValues(Command command, List<String> arguments) {
            int cellCount = switch (command) {
                case PATH, PUSH -> 1;
                case BRING -> 2;
                default -> 0;
            };
            for (int index = 0; index < 2 * cellCount; index += 2) {
                int row = Integer.parseInt(arguments.get(index));
                int column = Integer.parseInt(arguments.get(index + 1));
                if (!level.contains(row, column)) {
                    throw new CommandException("bad value");
                }
            }
            if ((command == Command.UNDO || command == Command.REDO)
                    && Integer.parseInt(arguments.get(0)) < 1) {
                throw new CommandException("bad value");
            }
            if (command == Command.SOLVE || command == Command.HINT) {
                int limit = Integer.parseInt(arguments.get(0));
                if (limit < 1 || limit > MAX_LIMIT) {
                    throw new CommandException("bad value");
                }
            }
        }

        private void runCommand(String name, List<String> arguments) {
            Command command = Command.named(name)
                    .orElseThrow(() -> new CommandException("unknown command " + name));
            List<Kind> kinds = command.kinds;
            if (arguments.size() != kinds.size() || !IntStream.range(0, kinds.size())
                    .allMatch(index -> validArgument(kinds.get(index), arguments.get(index)))) {
                throw new CommandException("bad arguments");
            }
            if (command != Command.IMPORT && command != Command.VALID) {
                if (level.reason != null) {
                    throw new CommandException("invalid level");
                }
                checkValues(command, arguments);
            }
            switch (command) {
                case IMPORT -> importLevel(arguments.get(0));
                case VALID -> valid();
                case INFO -> info();
                case SHOW -> show();
                case EXPORT -> exportLevel();
                case MOVE -> move(arguments.get(0));
                case PUSH -> push(cellArgument(arguments, 0), arguments.get(2).charAt(0));
                case BRING -> bring(cellArgument(arguments, 0), cellArgument(arguments, 2));
                case PATH -> path(cellArgument(arguments, 0));
                case UNDO -> undo(Integer.parseInt(arguments.get(0)));
                case REDO -> redo(Integer.parseInt(arguments.get(0)));
                case RESET -> reset();
                case STATUS -> status();
                case HISTORY -> showHistory();
                case BOXES -> showBoxes();
                case REACH -> reach();
                case DEADSQUARES -> deadSquares();
                case DEADLOCK -> deadlock();
                case BOUND -> bound();
                case SAVE -> save(arguments.get(0));
                case RESTORE -> restore(arguments.get(0));
                case CHECK -> check(arguments.get(0));
                case SOLVE -> solve(Integer.parseInt(arguments.get(0)));
                case HINT -> hint(Integer.parseInt(arguments.get(0)));
                case PLAY -> play();
                case TRANSFORM -> transform(arguments.get(0));
            }
        }

        void execute(List<String> words, List<String> rows) {
            try {
                if (words.get(0).equals("LOAD")) {
                    loadRows(Integer.parseInt(words.get(2)), rows);
                } else {
                    runCommand(words.get(0), words.subList(1, words.size()));
                }
            } catch (CommandException error) {
                emit("error:", error.getMessage());
            }
        }
    }

    static List<String> readRows(BufferedReader reader, int count) throws IOException {
        List<String> rows = new ArrayList<>();
        for (int index = 0; index < count; index++) {
            rows.add(reader.readLine());
        }
        return rows;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        int height = Integer.parseInt(reader.readLine().split(" ")[0]);
        Sokoban game = new Sokoban(readRows(reader, height));
        int count = Integer.parseInt(reader.readLine().trim());
        for (int index = 0; index < count; index++) {
            List<String> words = List.of(reader.readLine().split(" ", -1));
            List<String> rows = words.get(0).equals("LOAD")
                    ? readRows(reader, Integer.parseInt(words.get(1)))
                    : List.of();
            game.execute(words, rows);
        }
        System.out.print(game.output);
    }
}
