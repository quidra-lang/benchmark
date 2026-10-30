object Game {
    const val TILE_ORDER="ABCDEFGHIJKLMNOPQRSTUVWXYZ?"
    class Minstd(seed: Int) {
        var state=seed.toLong();
        fun next(): Int {
            state=state*48271%2147483647;
            return state.toInt()
        }
    }
    fun shuffle(bag: MutableList<Char>,random: Minstd) {
        for(i in bag.lastIndex downTo 1) {
            val j=random.next()%(i+1);
            val tile=bag[i];
            bag[i]=bag[j];
            bag[j]=tile
        }
    }
    fun bag(counts: IntArray,random: Minstd): MutableList<Char> {
        val result=mutableListOf<Char>();
        for(tile in TILE_ORDER)repeat(counts[tile.code]) {
            result.add(tile)
        };
        shuffle(result,random);
        return result
    }
    fun draw(bag: MutableList<Char>,count: Int): String {
        val result=StringBuilder();
        repeat(minOf(count,bag.size)) {
            result.append(bag.removeAt(bag.lastIndex))
        };
        return result.toString()
    }
    fun exchange(bag: MutableList<Char>,returned: String,random: Minstd): String {
        val drawn=draw(bag,returned.length);
        bag.addAll(returned.toList().sorted());
        shuffle(bag,random);
        return drawn
    }
    fun points(collection: String,values: IntArray)=collection.sumOf {
        values[it.code]
    }
}
