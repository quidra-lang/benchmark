object Scoring {
    data class Triplet(val kinds: List<Int>,val concealed: Boolean,val kan: Boolean)
    data class Fu(val items: List<Yaku.Item>,val total: Int,val rounded: Int)
    data class Limit(val category: String,val base: Int)
    data class Payments(val ron: Int,val dealer: Int,val nondealer: Int,val points: Int)
    fun tripletFu(block: Triplet): Yaku.Item {
        val type=if(block.kan) {
            if(block.concealed)"closed_kan" else "open_kan"
        }else {
            if(block.concealed)"closed_triplet" else "open_triplet"
        };
        val value=if(block.kan) {
            if(block.concealed)16 else 8
        }else {
            if(block.concealed)4 else 2
        };
        return Yaku.Item("$type ${Tiles.block(block.kinds)}",value*if(Tiles.yaochuu(block.kinds.first()))2 else 1)
    }
    fun fuBreakdown(form: String,pair: Int,triplets: List<Triplet>,wait: String,closed: Boolean,method: String,
        seat: Int,round: Int,pinfu: Boolean): Fu {
        if(form=="chiitoitsu")return Fu(listOf(Yaku.Item("chiitoitsu",25)),25,25);
        val items=mutableListOf(Yaku.Item("base",20));
        if(closed&&method=="ron")items.add(Yaku.Item("closed_ron",10));
        if(method=="tsumo"&&!pinfu)items.add(Yaku.Item("tsumo",2));
        val pairValue=2*((if(pair>=31)1 else 0)+(if(pair==seat)1 else 0)+(if(pair==round)1 else 0));
        if(pairValue>0)items.add(Yaku.Item("pair "+Tiles.block(listOf(pair,pair)),pairValue));
        for(triplet in triplets)items.add(tripletFu(triplet));
        if(wait in listOf("kanchan","penchan","tanki"))items.add(Yaku.Item("wait $wait",2));
        var total=items.sumOf {
            it.value
        };
        if(!closed&&total==20) {
            items.add(Yaku.Item("open_pinfu",10));
            total+=10
        };
        return Fu(items,total,(total+9)/10*10)
    }
    fun limit(han: Int,fu: Int,rules: MahjongProgram.Rules): Limit {
        if(han>=13&&rules.kazoeYakuman)return Limit("kazoe_yakuman",8000);
        if(han>=11)return Limit("sanbaiman",6000);
        if(han>=8)return Limit("baiman",4000);
        if(han>=6)return Limit("haneman",3000);
        val base=fu*(1 shl (han+2));
        return if(han==5||base>=2000||rules.kiriage&&base==1920)Limit("mangan",2000) else Limit("none",base)
    }
    fun roundHundred(value: Int)=(value+99)/100*100
    fun payments(base: Int,dealer: Boolean,method: String): Payments {
        if(method=="ron") {
            val ron=roundHundred(base*if(dealer)6 else 4);
            return Payments(ron,0,0,ron)
        };
        if(dealer) {
            val amount=roundHundred(2*base);
            return Payments(0,0,amount,3*amount)
        };
        val dealerPayment=roundHundred(2*base);
        val nondealer=roundHundred(base);
        return Payments(0,dealerPayment,nondealer,dealerPayment+2*nondealer)
    }
}
