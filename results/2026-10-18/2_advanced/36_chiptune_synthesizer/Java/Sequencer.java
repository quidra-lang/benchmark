import java.util.*;
final class Sequencer {
    record Position(int order, int row) {}
    static int samplesPerTick(int rate, int tempo) {
        return rate * 5 / (tempo * 2);
    }
    static Position next(int position, int row, SongParser.Cell[] cells, int length) {
        int jump = -1, patternBreak = -1;
        boolean stop = false;
        for (SongParser.Cell cell : cells) {
            SongParser.Effect effect = cell.effect();
            if (effect.name().equals("F") && effect.argument() == 0)
                stop = true;
            if (effect.name().equals("B"))
                jump = effect.argument();
            if (effect.name().equals("D"))
                patternBreak = effect.argument();
        }
        if (stop)
            return null;
        int p, r;
        if (jump >= 0 || patternBreak >= 0) {
            p = jump >= 0 ? jump : position + 1;
            r = patternBreak >= 0 && patternBreak < 64 ? patternBreak : 0;
        } else {
            p = row < 63 ? position : position + 1;
            r = row < 63 ? row + 1 : 0;
        }
        return p >= length ? null : new Position(p, r);
    }
    static Set<Integer> reachable(SongParser.Song song) {
        Set<Integer> seen = new HashSet<>();
        Position position = new Position(0, 0);
        while (position != null && seen.add(position.order * 64 + position.row))
            position = next(position.order, position.row,
                            song.patterns.get(song.order[position.order])[position.row], song.order.length);
        return seen;
    }
}
