object Auctions {
    data class Candidate(val number:Int,val bundle:Int,val value:Long)
    data class Clock(val winner:Int?,val price:Long,val steps:Int,val drops:List<Long?>)
    fun candidates(bids:List<BidsIo.Bid>,xor:Boolean):List<Candidate> {
        val result=mutableListOf<Candidate>();
        for(number in 1 until (1 shl bids.size)) {
            if(xor&&number.countOneBits()!=1)continue;
            var bundle=0;
            var value=0L;
            var valid=true;
            for(i in bids.indices)if((number and (1 shl i))!=0) {
                val bid=bids[i];
                if((bundle and bid.bundle)!=0) {
                    valid=false;
                    break
                }
                bundle=bundle or bid.bundle;
                value+=bid.amount
            }
            if(valid)result.add(Candidate(number,bundle,value))
        }
        return result
    }
    fun valueOf(candidates:List<Candidate>,items:Int)=candidates.filter {
        (it.bundle and items)==it.bundle
    }.maxOfOrNull {
        it.value
    }?:0L
    fun english(participants:List<BidsIo.Participant>,reserve:Long,increment:Long):Clock {
        var price=reserve;
        var paid=0L;
        var steps=0;
        var winner:Int?=null;
        var remaining=participants.indices.filter {
            participants[it].value>=price
        };
        while(remaining.size>=2) {
            val previous=remaining;
            price+=increment;
            steps++;
            remaining=participants.indices.filter {
                participants[it].value>=price
            };
            if(remaining.isEmpty()) {
                winner=previous.first();
                paid=price-increment;
                break
            }
        }
        if(remaining.isNotEmpty()) {
            winner=remaining.first();
            paid=price
        }
        val drops=participants.map {
            val drop=if(it.value<reserve)reserve else reserve+((it.value-reserve)/increment+1)*increment;
            if(drop<=price)drop else null
        };
        return Clock(winner,paid,steps,drops)
    }
    fun dutch(participants:List<BidsIo.Participant>,reserve:Long,start:Long,decrement:Long):Clock {
        var price=start;
        var steps=0;
        while(price>=reserve) {
            val winner=participants.indices.filter {
                participants[it].bid>=price
            }.maxByOrNull {
                participants[it].bid
            };
            if(winner!=null)return Clock(winner,price,steps,emptyList());
            price-=decrement;
            steps++
        }
        return Clock(null,0,steps,emptyList())
    }
}
