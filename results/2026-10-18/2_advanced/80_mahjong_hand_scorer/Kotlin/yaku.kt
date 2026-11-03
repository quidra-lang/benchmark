object Yaku {
    data class Definition(val name: String,val closed: Int,val opened: Int)
    data class Item(val name: String,val value: Int)
    val yaku=listOf(Definition("riichi",1,0),Definition("double_riichi",2,0),Definition("ippatsu",1,0),
        Definition("menzen_tsumo",1,0),Definition("pinfu",1,0),Definition("tanyao",1,1),Definition("iipeikou",
        1,0),Definition("haku",1,1),Definition("hatsu",1,1),Definition("chun",1,1),Definition("jikaze",
        1,1),Definition("bakaze",1,1),Definition("haitei",1,1),Definition("houtei",1,1),Definition("rinshan",
        1,1),Definition("chankan",1,1),Definition("chiitoitsu",2,0),Definition("toitoi",2,2),Definition("sanankou",
        2,2),Definition("sanshoku_doujun",2,1),Definition("sanshoku_doukou",2,2),Definition("ittsu",2,
        1),Definition("chanta",2,1),Definition("sankantsu",2,2),Definition("shousangen",2,2),Definition("honroutou",
        2,2),Definition("honitsu",3,2),Definition("junchan",3,2),Definition("ryanpeikou",3,0),Definition("chinitsu",
        6,5))
    val yakuman=listOf(Item("tenhou",1),Item("chiihou",1),Item("kokushi",1),Item("kokushi_13",2),Item("suuankou",
        1),Item("suuankou_tanki",2),Item("daisangen",1),Item("shousuushii",1),Item("daisuushii",2),Item("tsuuiisou",
        1),Item("chinroutou",1),Item("ryuuiisou",1),Item("chuuren",1),Item("junsei_chuuren",2),Item("suukantsu",
        1))
    val flags=listOf("riichi","double_riichi","ippatsu","haitei","houtei","rinshan","chankan","tenhou","chiihou");
    val categories=listOf("none","mangan","haneman","baiman","sanbaiman","kazoe_yakuman","yakuman")
    fun ordinary(names: Set<String>,closed: Boolean)=yaku.filter {
        it.name in names&&(closed||it.opened>0)
    }.map {
        Item(it.name,if(closed)it.closed else it.opened)
    }
    fun yakuman(names: Set<String>,doubled: Boolean)=yakuman.filter {
        it.name in names
    }.map {
        Item(it.name,if(doubled)it.value else 1)
    }
}
