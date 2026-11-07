object WdpSolver {
    data class Share(val item:Int,val amount:Report.Rational,val source:Int?)
    data class Improvement(val nodes:Int,val welfare:Long,val numbers:List<Int>)
    class Result {
        var welfare:Long?=null;
        var numbers=listOf<Int>();
        val winning=mutableListOf<BidsIo.Bid>();
        var nodes=0;
        var pruned=0;
        var leaves=0;
        val improvements=mutableListOf<Improvement>();
        var shares=listOf<Share>();
        var bound=Report.Rational(0)
    }
    fun shares(offered:List<Int>,items:List<BidsIo.Item>,bids:List<BidsIo.Bid>):List<Share> {
        val result=mutableListOf<Share>();
        for(item in offered) {
            var share=Report.Rational(items[item].reserve);
            var source:Int?=null;
            for(bid in bids)if((bid.bundle and (1 shl item))!=0) {
                val candidate=Report.Rational(bid.amount,bid.size.toLong());
                if(candidate>share) {
                    share=candidate;
                    source=bid.number
                }
            }
            result.add(Share(item,share,source))
        }
        return result
    }
    fun compareNumbers(a:List<Int>,b:List<Int>):Int {
        for(i in 0 until minOf(a.size,b.size)) {
            val c=a[i].compareTo(b[i]);
            if(c!=0)return c
        }
        return a.size.compareTo(b.size)
    }
    private class Search(val offered:List<Int>,val items:List<BidsIo.Item>,inputBids:List<BidsIo.Bid>) {
        val bids=inputBids.sortedBy {
            it.number
        };
        val all=offered.fold(0) {
            mask,i->mask or (1 shl i)
        };
        val result=Result()
        init {
            result.shares=shares(offered,items,bids);
            for(share in result.shares)result.bound=result.bound+share.amount
        }
        fun visit(decided:Int,used:Int,welfare:Long,chosen:List<Int>) {
            result.nodes++;
            if(decided==all) {
                result.leaves++;
                val numbers=chosen.sorted();
                val incumbent=result.welfare;
                if(incumbent==null||welfare>incumbent||welfare==incumbent&&compareNumbers(numbers,result.numbers)<0) {
                    result.welfare=welfare;
                    result.numbers=numbers;
                    result.improvements.add(Improvement(result.nodes,welfare,numbers))
                }
                return
            }
            val available=bids.filter {
                (it.bundle and decided)==0&&(!it.xor||(used and (1 shl it.bidder))==0)
            };
            val remaining=offered.filter {
                (decided and (1 shl it))==0
            };
            var bound=Report.Rational(welfare);
            for(share in shares(remaining,items,available))bound=bound+share.amount;
            val incumbent=result.welfare;
            if(incumbent!=null&&bound<Report.Rational(incumbent)) {
                result.pruned++;
                return
            }
            val first=remaining.first();
            for(bid in available)if((bid.bundle and (1 shl first))!=0)visit(decided or bid.bundle,if(bid.xor)used or (1 shl bid.bidder) else used,
                welfare+bid.amount,chosen+bid.number);
            visit(decided or (1 shl first),used,welfare+items[first].reserve,chosen)
        }
    }
    fun solve(offered:List<Int>,items:List<BidsIo.Item>,bids:List<BidsIo.Bid>):Result {
        val search=Search(offered,items,bids);
        search.visit(0,0,0L,emptyList());
        for(number in search.result.numbers)search.result.winning.add(bids.first {
            it.number==number
        });
        return search.result
    }
    fun greedyOrder(bids:List<BidsIo.Bid>)=bids.sortedWith {
        a,b->val left=a.amount*a.amount*b.size;
        val right=b.amount*b.amount*a.size;
        val c=right.compareTo(left);
        if(c!=0)c else a.number.compareTo(b.number)
    }
    fun greedySelect(bids:List<BidsIo.Bid>):List<BidsIo.Bid> {
        val chosen=mutableListOf<BidsIo.Bid>();
        var occupied=0;
        var used=0;
        for(bid in bids)if((bid.bundle and occupied)==0&&(!bid.xor||(used and (1 shl bid.bidder))==0)) {
            chosen.add(bid);
            occupied=occupied or bid.bundle;
            if(bid.xor)used=used or (1 shl bid.bidder)
        }
        return chosen
    }
}
