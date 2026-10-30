private val formats=listOf("first_price","second_price","english","dutch","all_pay")
private val outcomes=listOf("vcg","greedy","critical","saa")
private val mechanisms=listOf("vcg","pay_as_bid","greedy","critical","saa")
private val bidForm=Regex("[a-z]+(?:\\+[a-z]+)*:(?:0|[1-9][0-9]{0,4})")
private val ctrForm=Regex("[1-9][0-9]*/[1-9][0-9]*")
private fun numbers(values:Collection<Int>)=if(values.isEmpty())"-" else values.sorted().joinToString("+")
private fun count(counters:MutableMap<String,Long>,name:String,amount:Long) {
    counters[name]=counters.getOrDefault(name,0L)+amount
}
private fun get(counters:Map<String,Long>,name:String)=counters.getOrDefault(name,0L)
private data class Rejection(val number:Int,val name:String,val reason:String)
private data class Below(val bid:BidsIo.Bid,val reserve:Long)
private data class Parsed(val error:String?,val bundle:Int=0,val amount:Long=0)
private class Bidder(val name:String,val language:String) {
    val valid=mutableListOf<BidsIo.Bid>();
    val eligible=mutableListOf<BidsIo.Bid>()
}
private data class Allocation(val winning:List<BidsIo.Bid>,val owners:Map<Int,Int>,val unsold:List<Int>,
    val accepted:Long,val retained:Long,val welfare:Long)
private fun allocation(bids:List<BidsIo.Bid>,offered:List<Int>,items:List<BidsIo.Item>):Allocation {
    val winning=bids.sortedBy {
        it.number
    };
    val owners=mutableMapOf<Int,Int>();
    var accepted=0L;
    var retained=0L;
    for(bid in winning) {
        accepted+=bid.amount;
        for(item in offered)if((bid.bundle and (1 shl item))!=0)owners[item]=bid.bidder
    }
    val unsold=offered.filter {
        it !in owners
    };
    for(item in unsold)retained+=items[item].reserve;
    return Allocation(winning,owners,unsold,accepted,retained,accepted+retained)
}
private data class Ascending(val lines:List<String>,val payments:LongArray,val utilities:LongArray,val revenue:Long,
    val retained:Long,val welfare:Long,val rounds:Int,val reason:String,val exposure:Long,val exposed:Int)
private class CombinatorialAuction(raw:BidsIo.RawAuction,val input:BidsIo) {
    val name=raw.name;
    val offered=mutableListOf<Int>();
    val itemIds=input.items.withIndex().associate {
        it.value.name to it.index
    };
    val bidders=mutableListOf<Bidder>();
    val names=mutableListOf<String>();
    val valid=mutableListOf<BidsIo.Bid>();
    val eligible=mutableListOf<BidsIo.Bid>();
    val below=mutableListOf<Below>();
    val rejected=mutableListOf<Rejection>();
    var bidCount=0;
    var offeredMask=0;
    val optimal:WdpSolver.Result;
    val exact:Allocation;
    val order:List<BidsIo.Bid>;
    val greedy:Allocation;
    val critical:Map<Int,Payments.Critical>;
    val vcgDetails:Map<Int,Payments.Vcg>;
    val values:LongArray;
    val greedyValues:LongArray;
    val vcgPaid:LongArray;
    val vcgUtilities:LongArray;
    val criticalPaid:LongArray;
    val criticalUtilities:LongArray;
    val vcgRevenue:Long;
    val criticalRevenue:Long;
    val saa:Ascending
    fun param(key:String)=input.params.getValue(key)
    init {
        for(item in raw.items) {
            val id=itemIds.getValue(item);
            offered.add(id);
            offeredMask=offeredMask or (1 shl id)
        }
        validate(raw.lines);
        names.addAll(bidders.map {
            it.name
        });
        optimal=WdpSolver.solve(offered,input.items,eligible);
        exact=allocation(optimal.winning,offered,input.items);
        order=WdpSolver.greedyOrder(eligible);
        greedy=allocation(WdpSolver.greedySelect(order),offered,input.items);
        critical=Payments.critical(order,greedy.winning,input.items);
        vcgDetails=Payments.vcg(offered,input.items,eligible,optimal,bidders.size);
        values=LongArray(bidders.size);
        greedyValues=LongArray(bidders.size);
        criticalPaid=LongArray(bidders.size);
        for(bid in exact.winning)values[bid.bidder]+=bid.amount;
        for(bid in greedy.winning) {
            greedyValues[bid.bidder]+=bid.amount;
            criticalPaid[bid.bidder]+=critical.getValue(bid.number).payment
        }
        vcgPaid=LongArray(bidders.size) {
            vcgDetails[it]?.payment?:0L
        };
        vcgUtilities=LongArray(bidders.size) {
            values[it]-vcgPaid[it]
        };
        criticalUtilities=LongArray(bidders.size) {
            greedyValues[it]-criticalPaid[it]
        };
        vcgRevenue=vcgPaid.sum();
        criticalRevenue=criticalPaid.sum();
        saa=ascending()
    }
    fun bidError(text:String,bidder:Bidder):Parsed {
        if(!bidForm.matches(text))return Parsed("malformed bid");
        val parts=text.split(':');
        val itemNames=parts[0].split('+');
        var mask=0;
        for(name in itemNames) {
            val id=itemIds[name]?:return Parsed("unknown item $name");
            val bit=1 shl id;
            if((offeredMask and bit)==0)return Parsed("item not offered $name");
            if((mask and bit)!=0)return Parsed("duplicate item $name");
            mask=mask or bit
        }
        if(itemNames.size>param("max_bundle_size"))return Parsed("bundle too large");
        val amount=parts[1].toLong();
        if(amount==0L)return Parsed("zero value");
        for(earlier in bidder.valid)if(earlier.bundle==mask)return Parsed("duplicate bundle ${earlier.number}");
        if(bidder.valid.size>=param("max_bids_per_bidder"))return Parsed("too many bids");
        return Parsed(null,mask,amount)
    }
    fun validate(lines:List<BidsIo.BidderLine>) {
        val seen=mutableSetOf<String>();
        for(line in lines) {
            var error=if(seen.add(line.name))null else "duplicate bidder";
            if(error==null&&line.language !in listOf("XOR","OR"))error="bad language ${line.language}";
            val id=bidders.size;
            val bidder=if(error==null)Bidder(line.name,line.language) else null;
            if(bidder!=null)bidders.add(bidder);
            for(text in line.bids) {
                bidCount++;
                if(error!=null) {
                    rejected.add(Rejection(bidCount,line.name,error));
                    continue
                }
                val parsed=bidError(text,bidder!!);
                val errorMessage=parsed.error;
                if(errorMessage!=null) {
                    rejected.add(Rejection(bidCount,line.name,errorMessage));
                    continue
                }
                val bid=BidsIo.Bid(bidCount,id,parsed.bundle,parsed.amount,line.language=="XOR");
                bidder.valid.add(bid);
                valid.add(bid);
                val reserve=offered.filter {
                    (bid.bundle and (1 shl it))!=0
                }.sumOf {
                    input.items[it].reserve
                };
                if(bid.amount>=reserve) {
                    eligible.add(bid);
                    bidder.eligible.add(bid)
                }else below.add(Below(bid,reserve))
            }
        }
    }
    fun ascending():Ascending {
        val bidderCount=bidders.size;
        val itemCount=input.items.size;
        val increment=param("saa_increment");
        val choices=bidders.map {
            Auctions.candidates(it.valid,it.language=="XOR")
        };
        val eligibility=IntArray(bidderCount) {
            id->choices[id].maxOfOrNull {
                it.bundle.countOneBits()
            }?:0
        };
        val prices=LongArray(itemCount);
        val holders=IntArray(itemCount) {
            -1
        };
        val bidCounts=IntArray(itemCount);
        val bidRounds=IntArray(itemCount);
        val lastRounds=IntArray(itemCount);
        for(item in offered)prices[item]=input.items[item].reserve;
        var state=param("seed");
        val lines=mutableListOf("AUCTION $name increment $increment");
        var round=0;
        var reason="";
        for(r in 1..param("round_cap").toInt()) {
            round=r;
            val activities=IntArray(bidderCount);
            val newByBidder=IntArray(bidderCount);
            val newByItem=List(itemCount) {
                mutableListOf<Int>()
            };
            var demand=0;
            for(id in 0 until bidderCount) {
                var held=0;
                for(item in offered)if(holders[item]==id)held=held or (1 shl item);
                var chosen:Auctions.Candidate?=null;
                var bestSurplus=0L;
                for(candidate in choices[id])if((candidate.bundle or held).countOneBits()<=eligibility[id]) {
                    var surplus=candidate.value;
                    for(item in offered)if((candidate.bundle and (1 shl item))!=0)surplus-=prices[item]+if(holders[item]!=-1&&holders[item]!=id)increment else 0L;
                    if(surplus>bestSurplus) {
                        chosen=candidate;
                        bestSurplus=surplus
                    }
                }
                val demanded=chosen?.bundle?:0;
                activities[id]=(demanded or held).countOneBits();
                newByBidder[id]=demanded and held.inv();
                demand+=newByBidder[id].countOneBits();
                for(item in offered)if((newByBidder[id] and (1 shl item))!=0)newByItem[item].add(id)
            }
            if(demand>0) {
                val line=StringBuilder("ROUND $round demand $demand");
                for(id in 0 until bidderCount)if(newByBidder[id]!=0)line.append(' ').append(names[id]).append(':').append(Report.bundle(newByBidder[id],
                    input.items));
                lines.add(line.toString());
                for(item in offered) {
                    val competing=newByItem[item];
                    if(competing.isEmpty())continue;
                    var selected=0;
                    if(competing.size>=2) {
                        state=48271*state%2147483647;
                        selected=(state%competing.size).toInt()
                    }
                    if(holders[item]!=-1)prices[item]+=increment;
                    holders[item]=competing[selected];
                    bidCounts[item]+=competing.size;
                    bidRounds[item]++;
                    lastRounds[item]=round
                }
                val standing=StringBuilder("STANDING");
                for(item in offered)standing.append(' ').append(input.items[item].name).append('=').append(prices[item]).append('@').append(if(holders[item]==-1)"-" else names[holders[item]]);
                lines.add(standing.toString())
            }else lines.add("ROUND $round none");
            val changed=mutableListOf<String>();
            for(id in 0 until bidderCount)if(activities[id]<eligibility[id]) {
                eligibility[id]=activities[id];
                changed.add("${names[id]}=${eligibility[id]}")
            }
            if(changed.isNotEmpty())lines.add("ELIGIBILITY "+changed.joinToString(" "));
            if(demand==0||round.toLong()==param("round_cap")) {
                reason=if(demand==0)"quiet" else "cap";
                break
            }
        }
        lines.add("END rounds $round $reason");
        var retained=0L;
        for(item in offered) {
            val record=input.items[item];
            if(holders[item]==-1) {
                retained+=record.reserve;
                lines.add("ITEM ${record.name} unsold reserve ${record.reserve}")
            }else lines.add("ITEM ${record.name} price ${prices[item]} holder ${names[holders[item]]} bids ${bidCounts[item]} rounds ${bidRounds[item]} last ${lastRounds[item]}")
        }
        val payments=LongArray(bidderCount);
        val utilities=LongArray(bidderCount);
        var totalValue=0L;
        var exposure=0L;
        var exposed=0;
        for(id in 0 until bidderCount) {
            var won=0;
            for(item in offered)if(holders[item]==id) {
                won=won or (1 shl item);
                payments[id]+=prices[item]
            }
            val value=Auctions.valueOf(choices[id],won);
            utilities[id]=value-payments[id];
            totalValue+=value;
            if(utilities[id]<0) {
                exposure-=utilities[id];
                exposed++
            }
            lines.add("BIDDER ${names[id]} won ${Report.bundle(won,input.items)} paid ${payments[id]} value $value utility ${utilities[id]} eligibility ${eligibility[id]}"+if(utilities[id]<0)" exposed" else "")
        }
        val revenue=payments.sum();
        val welfare=totalValue+retained;
        lines.add("TOTAL revenue $revenue welfare $welfare efficiency ${Report.Rational(welfare,exact.welfare)} exposure $exposure exposed $exposed");
        return Ascending(lines,payments,utilities,revenue,retained,welfare,round,reason,exposure,exposed)
    }
    fun unsold(items:List<Int>)=if(items.isEmpty())"-" else items.joinToString(" ") {
        input.items[it].name
    }
    fun wdpReport():List<String> {
        val lines=mutableListOf("AUCTION $name items ${offered.size} bidders ${bidders.size} bids $bidCount valid ${valid.size} eligible ${eligible.size}");
        for(bidder in bidders)lines.add("BIDDER ${bidder.name} ${bidder.language} valid ${bidder.valid.size} eligible ${bidder.eligible.size}");
        for(rejection in rejected)lines.add("REJECT ${rejection.number} ${rejection.name} ${rejection.reason}");
        for(record in below) {
            val bid=record.bid;
            lines.add("BELOW_RESERVE ${bid.number} ${names[bid.bidder]} value ${bid.amount} reserve ${record.reserve}")
        }
        for(share in optimal.shares)lines.add("SHARE ${input.items[share.item].name} ${share.amount} "+if(share.source==null)"reserve" else "bid ${share.source}");
        lines.add("ROOT_BOUND ${optimal.bound}");
        for(record in optimal.improvements)lines.add("IMPROVE ${record.nodes} welfare ${record.welfare} bids ${numbers(record.numbers)}");
        lines.add("OPTIMAL welfare ${exact.welfare} accepted ${exact.accepted} retained ${exact.retained} winners ${exact.winning.size}");
        for(bid in exact.winning)lines.add("WIN ${bid.number} ${names[bid.bidder]} ${Report.bundle(bid.bundle,input.items)} ${bid.amount}");
        lines.add("UNSOLD "+unsold(exact.unsold));
        lines.add("SEARCH nodes ${optimal.nodes} pruned ${optimal.pruned} leaves ${optimal.leaves} improvements ${optimal.improvements.size}");
        lines.add("GREEDY_ORDER "+if(order.isEmpty())"-" else order.joinToString(" ") {
            it.number.toString()
        });
        lines.add("GREEDY welfare ${greedy.welfare} accepted ${greedy.accepted} retained ${greedy.retained} winners ${greedy.winning.size} efficiency ${Report.Rational(greedy.welfare,exact.welfare)}");
        for(bid in greedy.winning) {
            val payment=critical.getValue(bid.number);
            lines.add("GWIN ${bid.number} ${names[bid.bidder]} ${Report.bundle(bid.bundle,input.items)} ${bid.amount} critical ${payment.payment} against ${payment.rival?.number?:"-"}")
        }
        lines.add("GUNSOLD "+unsold(greedy.unsold));
        for(item in offered) {
            val demand=eligible.count {
                (it.bundle and (1 shl item))!=0
            };
            val exactOwner=exact.owners[item];
            val greedyOwner=greedy.owners[item];
            lines.add("ITEM ${input.items[item].name} reserve ${input.items[item].reserve} demand $demand optimal ${exactOwner?.let {names[it]}?:"-"} greedy ${greedyOwner?.let {names[it]}?:"-"}")
        }
        return lines
    }
    fun vcgReport():List<String> {
        val lines=mutableListOf("AUCTION $name welfare ${exact.welfare}");
        for(id in names.indices) {
            val detail=vcgDetails[id];
            if(detail==null) {
                lines.add("BIDDER ${names[id]} lost");
                continue
            }
            val won=exact.winning.filter {
                it.bidder==id
            }.map {
                it.number
            };
            lines.add("BIDDER ${names[id]} won ${numbers(won)} value ${values[id]} without ${detail.alternative.welfare} alternative ${numbers(detail.alternative.numbers)} payment ${detail.payment} utility ${vcgUtilities[id]}")
        }
        lines.add("TOTAL revenue $vcgRevenue pay_as_bid ${exact.accepted} retained ${exact.retained} seller ${vcgRevenue+exact.retained} bidders ${vcgUtilities.sum()}");
        for(id in names.indices)lines.add("PAYMENTS ${names[id]} vcg ${vcgPaid[id]} pay_as_bid ${values[id]} greedy ${greedyValues[id]} critical ${criticalPaid[id]} saa ${saa.payments[id]}");
        for(id in names.indices)lines.add("UTILITIES ${names[id]} vcg ${vcgUtilities[id]} critical ${criticalUtilities[id]} saa ${saa.utilities[id]}");
        return lines
    }
    fun coalitionName(coalition:Payments.Coalition)=if(coalition.members.isEmpty())"-" else coalition.members.joinToString("+") {
        names[it]
    }
    fun coreReport(totals:MutableMap<String,Long>):List<String> {
        val lines=mutableListOf("AUCTION $name bidders ${bidders.size}");
        if(bidders.size>param("core_max_bidders")) {
            lines.add("SKIPPED");
            count(totals,"skipped",1);
            return lines
        }
        count(totals,"checked",1);
        val coalitions=Payments.coalitions(offered,input.items,eligible,bidders.size);
        lines.add("COALITIONS ${coalitions.size}");
        val sellers=longArrayOf(vcgRevenue+exact.retained,greedy.welfare,criticalRevenue+greedy.retained,
            saa.revenue+saa.retained);
        val utilities=listOf(vcgUtilities,LongArray(bidders.size),criticalUtilities,saa.utilities);
        for(outcome in outcomes.indices) {
            val outcomeName=outcomes[outcome];
            lines.add("OUTCOME $outcomeName seller ${sellers[outcome]} utilities ${utilities[outcome].joinToString(" ")}");
            val blocking=Payments.blocking(coalitions,sellers[outcome],utilities[outcome]);
            for(block in blocking.minimal) {
                val coalition=block.coalition;
                lines.add("BLOCK ${coalitionName(coalition)} welfare ${coalition.welfare} payoff ${block.payoff} deficit ${block.deficit} bids ${numbers(coalition.numbers)}")
            }
            if(blocking.all.isEmpty()) {
                lines.add("RESULT core");
                count(totals,outcomeName,1)
            }else {
                val worst=blocking.all.maxBy {
                    it.deficit
                };
                lines.add("RESULT blocked ${blocking.all.size} minimal ${blocking.minimal.size} max_deficit ${worst.deficit} by ${coalitionName(worst.coalition)}")
            }
        }
        return lines
    }
}
private data class Rates(val error:String?,val values:List<Report.Rational>?)
private data class Mechanism(val winner:Int?,val price:Long,val steps:Int?)
private data class LotResult(val name:String,val utilities:LongArray,val revenue:Long)
private class Laboratory {
    val input=BidsIo();
    val wdpLines=mutableListOf<String>();
    val vcgLines=mutableListOf<String>();
    val coreLines=mutableListOf<String>();
    val ascendingLines=mutableListOf<String>();
    val singleLines=mutableListOf<String>();
    val summaryLines=mutableListOf("mechanism,revenue,welfare,efficiency");
    val wdpTotals=mutableMapOf<String,Long>();
    val vcgTotals=mutableMapOf<String,Long>();
    val coreTotals=mutableMapOf<String,Long>();
    val ascendingTotals=mutableMapOf<String,Long>();
    val groupTotals=mutableMapOf<String,Long>()
    fun param(key:String)=input.params.getValue(key)
    fun summaryRow(name:String,mechanism:String,revenue:Report.Rational,welfare:Report.Rational,efficiency:Report.Rational) {
        summaryLines.add("$name/$mechanism,$revenue,$welfare,$efficiency")
    }
    fun processAuctions() {
        for(name in input.runs) {
            val auction=CombinatorialAuction(input.auctions.getValue(name),input);
            wdpLines.addAll(auction.wdpReport());
            vcgLines.addAll(auction.vcgReport());
            coreLines.addAll(auction.coreReport(coreTotals));
            ascendingLines.addAll(auction.saa.lines);
            count(wdpTotals,"auctions",1);
            count(wdpTotals,"bids",auction.bidCount.toLong());
            count(wdpTotals,"valid",auction.valid.size.toLong());
            count(wdpTotals,"eligible",auction.eligible.size.toLong());
            count(wdpTotals,"nodes",auction.optimal.nodes.toLong());
            count(wdpTotals,"greedy_optimal",if(auction.greedy.welfare==auction.exact.welfare)1 else 0);
            val revenues=longArrayOf(auction.vcgRevenue,auction.exact.accepted,auction.greedy.accepted,
                auction.criticalRevenue,auction.saa.revenue);
            for(i in mechanisms.indices) {
                val mechanism=mechanisms[i];
                count(vcgTotals,mechanism,revenues[i]);
                val welfare=if(i<=1)auction.exact.welfare else if(i==4)auction.saa.welfare else auction.greedy.welfare;
                summaryRow(name,mechanism,Report.Rational(revenues[i]),Report.Rational(welfare),Report.Rational(welfare,
                    auction.exact.welfare))
            }
            count(ascendingTotals,"auctions",1);
            count(ascendingTotals,"rounds",auction.saa.rounds.toLong());
            count(ascendingTotals,"capped",if(auction.saa.reason=="cap")1 else 0);
            count(ascendingTotals,"exposed",auction.saa.exposed.toLong());
            count(ascendingTotals,"exposure",auction.saa.exposure)
        }
    }
    fun duplicate(participants:List<BidsIo.Participant>):String? {
        val seen=mutableSetOf<String>();
        for(participant in participants)if(!seen.add(participant.name))return participant.name;
        return null
    }
    fun validateLot(group:BidsIo.Group):String? {
        if(group.participants.isEmpty())return "no bidders";
        val duplicate=duplicate(group.participants);
        if(duplicate!=null)return "duplicate bidder $duplicate";
        for(participant in group.participants)if(participant.bid>participant.value)return "bid above value ${participant.name}";
        return null
    }
    fun validateSlots(group:BidsIo.Group):Rates {
        val rates=mutableListOf<Report.Rational>();
        for(text in group.arguments) {
            if(!ctrForm.matches(text))return Rates("bad ctr $text",null);
            val f=text.split('/');
            val rate=Report.Rational(f[0].toLong(),f[1].toLong());
            if(rate>Report.Rational(1)||rates.isNotEmpty()&&rate>=rates.last())return Rates("bad ctr $text",null);
            rates.add(rate)
        }
        if(group.participants.isEmpty())return Rates("no advertisers",null);
        val duplicate=duplicate(group.participants);
        if(duplicate!=null)return Rates("duplicate advertiser $duplicate",null);
        return Rates(null,rates)
    }
    fun lot(group:BidsIo.Group):List<String> {
        val participants=group.participants;
        val reserve=group.arguments.first().toLong();
        val eligible=participants.indices.filter {
            participants[it].bid>=reserve
        };
        val first=eligible.maxByOrNull {
            participants[it].bid
        };
        val bestValue=participants.indices.maxBy {
            participants[it].value
        };
        val optimum=maxOf(reserve,participants[bestValue].value);
        val efficient=if(participants[bestValue].value>=reserve)bestValue else null;
        val lines=mutableListOf("LOT ${group.name} reserve $reserve bidders ${participants.size} efficient ${efficient?.let {participants[it].name}?:"-"} optimum $optimum");
        val firstPrice=first?.let {
            participants[it].bid
        }?:0L;
        var secondPrice=if(efficient==null)0L else reserve;
        if(efficient!=null)for(i in participants.indices)if(i!=efficient&&participants[i].value>=reserve)secondPrice=maxOf(secondPrice,
            participants[i].value);
        val ascending=Auctions.english(participants,reserve,param("english_increment"));
        val descending=Auctions.dutch(participants,reserve,param("dutch_start"),param("dutch_decrement"));
        val options=listOf(Mechanism(first,firstPrice,null),Mechanism(efficient,secondPrice,null),Mechanism(ascending.winner,
            ascending.price,ascending.steps),Mechanism(descending.winner,descending.price,descending.steps),
            Mechanism(first,firstPrice,null));
        val results=mutableListOf<LotResult>();
        for(i in formats.indices) {
            val name=formats[i];
            val mechanism=options[i];
            val winner=mechanism.winner;
            val price=mechanism.price;
            var revenue=price;
            val utilities=LongArray(participants.size);
            if(name=="all_pay") {
                revenue=0;
                for(index in eligible) {
                    utilities[index]=-participants[index].bid;
                    revenue+=participants[index].bid
                }
            }
            val welfare:Long;
            var line:String;
            if(winner==null) {
                welfare=reserve;
                line=name.uppercase()+" unsold"
            }else {
                utilities[winner]=participants[winner].value-price;
                welfare=participants[winner].value;
                line="${name.uppercase()} winner ${participants[winner].name} price $price utility ${utilities[winner]}"
            }
            if(mechanism.steps!=null)line+=" steps ${mechanism.steps}";
            val efficiency=Report.Rational(welfare,optimum);
            lines.add("$line revenue $revenue welfare $welfare efficiency $efficiency");
            if(name=="english") {
                val drops=StringBuilder("ENGLISH_DROPS");
                for(j in participants.indices)drops.append(' ').append(participants[j].name).append('=').append(ascending.drops[j]?.toString()?:"-");
                lines.add(drops.toString())
            }
            results.add(LotResult(name,utilities,revenue));
            summaryRow(group.name,name,Report.Rational(revenue),Report.Rational(welfare),efficiency)
        }
        for(i in participants.indices)lines.add("UTILITY ${participants[i].name} "+results.joinToString(" ") {
            it.utilities[i].toString()
        });
        lines.add("RANKING "+results.sortedByDescending {
            it.revenue
        }.joinToString(" ") {
            it.name
        });
        return lines
    }
    fun slots(group:BidsIo.Group,rates:List<Report.Rational>):List<String> {
        val rankedBids=group.participants.sortedByDescending {
            it.bid
        };
        val rankedValues=group.participants.sortedByDescending {
            it.value
        };
        val bidderCount=group.participants.size;
        val slotCount=rates.size;
        val lines=mutableListOf("SLOTS ${group.name} slots $slotCount advertisers $bidderCount");
        var gspRevenue=Report.Rational(0);
        var gspWelfare=Report.Rational(0);
        var vcgRevenue=Report.Rational(0);
        var optimum=Report.Rational(0);
        for(rank in 0 until minOf(bidderCount,slotCount)) {
            val bidder=rankedBids[rank];
            val rate=rates[rank];
            val price=Payments.gspPrice(rankedBids,rank);
            val payment=rate*price;
            val utility=rate*(bidder.value-price);
            gspRevenue=gspRevenue+payment;
            gspWelfare=gspWelfare+rate*bidder.value;
            optimum=optimum+rate*rankedValues[rank].value;
            lines.add("GSP ${rank+1} ${bidder.name} ctr $rate bid ${bidder.bid} price $price payment $payment utility $utility")
        }
        val efficiency=gspWelfare/optimum;
        lines.add("GSP_TOTAL revenue $gspRevenue welfare $gspWelfare efficiency $efficiency");
        for(rank in 0 until minOf(bidderCount,slotCount)) {
            val bidder=rankedValues[rank];
            val rate=rates[rank];
            val payment=Payments.slotVcg(rankedValues,rates,rank);
            vcgRevenue=vcgRevenue+payment;
            val utility=rate*bidder.value-payment;
            lines.add("VCG ${rank+1} ${bidder.name} ctr $rate value ${bidder.value} payment $payment price ${payment/rate} utility $utility")
        }
        lines.add("VCG_TOTAL revenue $vcgRevenue welfare $optimum efficiency 1");
        var violations=0;
        for(rank in 1 until minOf(bidderCount,slotCount+1)) {
            val bidder=rankedBids[rank];
            val rate=rates.getOrNull(rank)?:Report.Rational(0);
            val stay=rate*(bidder.value-Payments.gspPrice(rankedBids,rank));
            val swap=rates[rank-1]*(bidder.value-bidder.bid);
            val violated=stay<swap;
            if(violated)violations++;
            lines.add("ENVY ${rank+1} ${bidder.name} stay $stay swap $swap ${if(violated)"violated" else "ok"}")
        }
        lines.add(if(violations==0)"ENVY_FREE yes" else "ENVY_FREE no violations $violations");
        var deviations=0;
        for(rank in 0 until bidderCount) {
            val bidder=rankedBids[rank];
            val rate=rates.getOrNull(rank)?:Report.Rational(0);
            val current=rate*(bidder.value-Payments.gspPrice(rankedBids,rank));
            for(target in 0 until slotCount) {
                if(target==rank)continue;
                val price=if(target<rank)rankedBids.getOrNull(target)?.bid?:0L else Payments.gspPrice(rankedBids,target);
                val payoff=rates[target]*(bidder.value-price);
                if(payoff>current) {
                    deviations++;
                    lines.add("DEVIATE ${bidder.name} from ${rank+1} to ${target+1} gain ${payoff-current}")
                }
            }
        }
        lines.add(if(deviations==0)"NASH yes" else "NASH no deviations $deviations");
        val equilibrium=violations==0&&deviations==0;
        lines.add("EQUILIBRIUM ${if(equilibrium)"yes" else "no"}");
        count(groupTotals,"envy_free",if(violations==0)1 else 0);
        count(groupTotals,"nash",if(deviations==0)1 else 0);
        count(groupTotals,"equilibria",if(equilibrium)1 else 0);
        summaryRow(group.name,"gsp",gspRevenue,gspWelfare,efficiency);
        summaryRow(group.name,"vcg",vcgRevenue,optimum,Report.Rational(1));
        return lines
    }
    fun processGroups() {
        for(group in input.groups) {
            val isLot=group.kind=="lot";
            count(groupTotals,if(isLot)"lots" else "slot_groups",1);
            val error:String?;
            var rates:List<Report.Rational>?=null;
            if(isLot)error=validateLot(group) else {
                val result=validateSlots(group);
                error=result.error;
                rates=result.values
            }
            if(error!=null) {
                singleLines.add("${group.kind.uppercase()} ${group.name} ERROR $error");
                count(groupTotals,"errors",1);
                continue
            }
            singleLines.addAll(if(isLot)lot(group) else slots(group,rates!!))
        }
    }
    fun totals(prefix:String,totals:Map<String,Long>,names:List<String>)=prefix+names.joinToString("") {
        " $it ${get(totals,it)}"
    }
    fun totalLines() {
        wdpLines.add(totals("TOTAL",wdpTotals,listOf("auctions","bids","valid","eligible","nodes","greedy_optimal")));
        vcgLines.add(totals("OVERALL",vcgTotals,mechanisms));
        coreLines.add(totals("SUMMARY",coreTotals,listOf("checked","skipped")+outcomes));
        ascendingLines.add(totals("SUMMARY",ascendingTotals,listOf("auctions","rounds","capped","exposed","exposure")));
        singleLines.add(totals("SUMMARY",groupTotals,listOf("lots","slot_groups","errors","envy_free","nash","equilibria")))
    }
    fun run() {
        processAuctions();
        processGroups();
        totalLines();
        Report.write("wdp.txt",wdpLines);
        Report.write("vcg.txt",vcgLines);
        Report.write("core_check.txt",coreLines);
        Report.write("ascending_log.txt",ascendingLines);
        Report.write("single_item.txt",singleLines);
        Report.write("summary.csv",summaryLines)
    }
}
fun main() {
    Laboratory().run()
}
