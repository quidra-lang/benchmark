object Tiles {
    data class Tile(val kind: Int,val red: Boolean)
    const val suits="mpsz";
    const val winds="ESWN";
    val yaochuuKinds=listOf(0,8,9,17,18,26,27,28,29,30,31,32,33);
    val green=setOf(19,20,21,23,25,32)
    fun parse(text: String,allowEmpty: Boolean=false): List<Tile>? {
        if(text=="-")return if(allowEmpty)emptyList() else null;
        val result=mutableListOf<Tile>();
        val digits=mutableListOf<Int>();
        for(c in text)if(c in '0'..'9')digits.add(c-'0') else {
            val suit=suits.indexOf(c);
            if(suit<0||digits.isEmpty())return null;
            for(digit in digits) {
                if(suit==3&&digit !in 1..7)return null;
                result.add(Tile(suit*9+(if(digit==0)5 else digit)-1,digit==0))
            };
            digits.clear()
        };
        return if(result.isEmpty()||digits.isNotEmpty())null else result
    }
    fun name(kind: Int)="${kind%9+1}${suits[kind/9]}"
    fun block(kinds: List<Int>)=kinds.sorted().joinToString("") {
        (it%9+1).toString()
    }+suits[kinds.first()/9]
    fun counts(tiles: Collection<Tile>): IntArray {
        val result=IntArray(34);
        for(tile in tiles)result[tile.kind]++;
        return result
    }
    fun honor(kind: Int)=kind>=27
    fun terminal(kind: Int)=kind<27&&kind%9 in listOf(0,8)
    fun yaochuu(kind: Int)=honor(kind)||terminal(kind)
    fun nextDora(kind: Int)=if(kind<27)kind/9*9+(kind%9+1)%9 else if(kind<31)27+(kind-26)%4 else 31+(kind-30)%3
    fun windTile(wind: String)=27+winds.indexOf(wind)
    fun key(counts: IntArray)=counts.map {
        ('0'.code+it).toChar()
    }.joinToString("")
}
