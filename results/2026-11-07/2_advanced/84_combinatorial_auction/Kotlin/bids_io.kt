import java.io.File
class BidsIo {
    data class Item(val name:String,val reserve:Long)
    data class Bid(val number:Int,val bidder:Int,val bundle:Int,val amount:Long,val xor:Boolean) {
        val size get()=bundle.countOneBits()
    }
    data class Participant(val name:String,val value:Long,val bid:Long)
    data class BidderLine(val name:String,val language:String,val bids:List<String>)
    class RawAuction(val name:String,val items:List<String>) {
        val lines=mutableListOf<BidderLine>()
    }
    class Group(f:List<String>) {
        val kind=f[0];
        val name=f[1];
        val arguments=f.drop(2);
        val participants=mutableListOf<Participant>()
    }
    val items=mutableListOf<Item>();
    val auctions=linkedMapOf<String,RawAuction>();
    val groups=mutableListOf<Group>();
    var runs=listOf<String>();
    val params=mutableMapOf<String,Long>()
    init {
        for(line in lines("items.txt")) {
            val f=line.split(' ');
            items.add(Item(f[0],f[1].toLong()))
        }
        var auction:RawAuction?=null;
        for(line in lines("bids.txt")) {
            val f=line.split(' ');
            if(f[0]=="auction") {
                val next=RawAuction(f[1],f.drop(2));
                auctions[next.name]=next;
                auction=next
            }else auction!!.lines.add(BidderLine(f[1],f[2],f.drop(3)))
        }
        var group:Group?=null;
        for(line in lines("single_item.txt")) {
            val f=line.split(' ');
            if(f[0] in listOf("lot","slots")) {
                val next=Group(f);
                groups.add(next);
                group=next
            }else group!!.participants.add(Participant(f[1],f[2].toLong(),f[3].toLong()))
        }
        for(line in lines("params.txt")) {
            val f=line.split(' ');
            if(f[0]=="run")runs=f.drop(1) else params[f[0]]=f[1].toLong()
        }
    }
    companion object {
        fun lines(name:String)=File("input",name).readLines(Charsets.US_ASCII)
    }
}
