object Sequencer {
    data class Position(val order: Int, val row: Int)
    fun samplesPerTick(rate: Int, tempo: Int) = rate * 5 / (tempo * 2)
    fun next(position: Int, row: Int, cells: Array<SongParser.Cell>, length: Int): Position? {
        var jump = -1;
        var patternBreak = -1;
        var stop = false;
        for (cell in cells) {
            val effect = cell.effect;
            if (effect.name == "F" && effect.argument == 0) stop = true;
            if (effect.name == "B") jump = effect.argument;
            if (effect.name == "D") patternBreak = effect.argument
        };
        if (stop) return null;
        val p: Int;
        val r: Int;
        if (jump >= 0 || patternBreak >= 0) {
            p = if (jump >= 0) jump else position + 1;
            r = if (patternBreak in 0..63) patternBreak else 0
        } else {
            p = if (row < 63) position else position + 1;
            r = if (row < 63) row + 1 else 0
        };
        return if (p >= length) null else Position(p,r)
    }
    fun reachable(song: SongParser.Song): Set<Int> {
        val seen = mutableSetOf<Int>();
        var position: Position? = Position(0,0);
        while (position != null) {
            val current = position;
            if (!seen.add(current.order * 64 + current.row)) break;
            position = next(current.order,current.row,song.patterns.getValue(song.order[current.order])[current.row],song.order.size)
        };
        return seen
    }
}
