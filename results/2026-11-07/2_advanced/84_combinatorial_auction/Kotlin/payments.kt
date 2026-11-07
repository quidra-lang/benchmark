object Payments {
    data class Vcg(val payment:Long,val alternative:WdpSolver.Result)
    data class Critical(val payment:Long,val rival:BidsIo.Bid?)
    data class Coalition(val mask:Int,val members:List<Int>,val welfare:Long,val numbers:List<Int>)
    data class Block(val coalition:Coalition,val payoff:Long,val deficit:Long)
    data class Blocking(val all:List<Block>,val minimal:List<Block>)
    fun vcg(offered:List<Int>,items:List<BidsIo.Item>,bids:List<BidsIo.Bid>,optimal:WdpSolver.Result,
        count:Int):Map<Int,Vcg> {
        val results=mutableMapOf<Int,Vcg>();
        for(bidder in 0 until count) {
            val value=optimal.winning.filter {
                it.bidder==bidder
            }.sumOf {
                it.amount
            };
            if(value==0L)continue;
            val alternative=WdpSolver.solve(offered,items,bids.filter {
                it.bidder!=bidder
            });
            results[bidder]=Vcg(alternative.welfare!!-(optimal.welfare!!-value),alternative)
        }
        return results
    }
    private fun earlier(amount:Long,bid:BidsIo.Bid,rival:BidsIo.Bid):Boolean {
        val left=amount*amount*rival.size;
        val right=rival.amount*rival.amount*bid.size;
        return left>right||left==right&&bid.number<rival.number
    }
    fun critical(order:List<BidsIo.Bid>,winning:List<BidsIo.Bid>,items:List<BidsIo.Item>):Map<Int,Critical> {
        val results=mutableMapOf<Int,Critical>();
        for(bid in winning) {
            val rival=WdpSolver.greedySelect(order.filter {
                it.number!=bid.number
            }).firstOrNull {
                (bid.bundle and it.bundle)!=0||bid.xor&&bid.bidder==it.bidder
            };
            var payment=items.indices.filter {
                (bid.bundle and (1 shl it))!=0
            }.sumOf {
                items[it].reserve
            };
            if(rival!=null) {
                var low=1L;
                var high=1L;
                while(!earlier(high,bid,rival))high*=2;
                while(low<high) {
                    val middle=(low+high)/2;
                    if(earlier(middle,bid,rival))high=middle else low=middle+1
                }
                payment=maxOf(payment,low)
            }
            results[bid.number]=Critical(payment,rival)
        }
        return results
    }
    private fun enumerate(output:MutableList<Coalition>,count:Int,left:Int,start:Int,mask:Int,members:List<Int>,
        offered:List<Int>,items:List<BidsIo.Item>,bids:List<BidsIo.Bid>) {
        if(left==0) {
            val result=WdpSolver.solve(offered,items,bids.filter {
                (mask and (1 shl it.bidder))!=0
            });
            output.add(Coalition(mask,members,result.welfare!!,result.numbers));
            return
        }
        for(id in start..count-left)enumerate(output,count,left-1,id+1,mask or (1 shl id),members+id,offered,items,bids)
    }
    fun coalitions(offered:List<Int>,items:List<BidsIo.Item>,bids:List<BidsIo.Bid>,count:Int):List<Coalition> {
        val output=mutableListOf<Coalition>();
        for(size in 0..count)enumerate(output,count,size,0,0,emptyList(),offered,items,bids);
        return output
    }
    fun blocking(coalitions:List<Coalition>,seller:Long,utilities:LongArray):Blocking {
        val all=mutableListOf<Block>();
        val minimal=mutableListOf<Block>();
        for(coalition in coalitions) {
            val payoff=seller+coalition.members.sumOf {
                utilities[it]
            };
            if(coalition.welfare>payoff) {
                val block=Block(coalition,payoff,coalition.welfare-payoff);
                if(all.none {
                    (it.coalition.mask and coalition.mask)==it.coalition.mask
                })minimal.add(block);
                all.add(block)
            }
        }
        return Blocking(all,minimal)
    }
    fun gspPrice(ranking:List<BidsIo.Participant>,rank:Int)=ranking.getOrNull(rank+1)?.bid?:0L
    fun slotVcg(ranking:List<BidsIo.Participant>,rates:List<Report.Rational>,rank:Int):Report.Rational {
        var payment=Report.Rational(0);
        for(t in rank+1 until minOf(ranking.size,rates.size+1)) {
            val next=rates.getOrNull(t)?:Report.Rational(0);
            payment=payment+(rates[t-1]-next)*ranking[t].value
        }
        return payment
    }
}
