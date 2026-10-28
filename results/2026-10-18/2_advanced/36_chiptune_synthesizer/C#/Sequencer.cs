using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Sequencer {
    public sealed record Position(int order, int row);
    public static int SamplesPerTick(int rate, int tempo) {
        return rate * 5 / (tempo * 2);
    }
    public static Position Next(int position, int row, SongParser.Cell[] cells, int length) {
        int jump = -1, patternBreak = -1;
        bool stop = false;
        foreach (SongParser.Cell cell in cells) {
            SongParser.Effect effect = cell.effect;
            if (effect.name.Equals("F") && effect.argument == 0)
                stop = true;
            if (effect.name.Equals("B"))
                jump = effect.argument;
            if (effect.name.Equals("D"))
                patternBreak = effect.argument;
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
    public static HashSet<int> Reachable(SongParser.Song song) {
        HashSet<int> seen = new();
        Position position = new Position(0, 0);
        while (position != null && seen.Add(position.order * 64 + position.row))
            position = Next(position.order, position.row,
                            song.patterns[song.order[position.order]][position.row], song.order.Length);
        return seen;
    }
}
