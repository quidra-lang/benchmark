import java.io.File
object MahjongProgram {
    val waitOrder=listOf("ryanmen","kanchan","penchan","shanpon","tanki","single","thirteen");
    val winOrder=listOf("dealer_ron","dealer_tsumo","nondealer_ron","nondealer_tsumo")
    data class Rules(val openTanyao: Boolean,val redFives: Boolean,val doubleYakuman: Boolean,val kazoeYakuman: Boolean,
        val kiriage: Boolean,val honba: Int)
    data class Record(val label: String,val fields: Map<String,String>)
    data class Facts(val triplets: List<Scoring.Triplet>,val sequences: List<Int>,val concealedSequences: List<List<Int>>)
    data class Winning(val lines: List<String>,val points: Int)
    data class Acceptance(val kind: Int,val remaining: Int)
    data class WaitScore(val kind: Int,val points: Int)
    fun readRecords(filename: String)=File("input/$filename").readLines(Charsets.US_ASCII).map {
        line->val parts=line.split(' ');
        Record(parts[0],parts.drop(1).associate {
            it.substringBefore('=') to it.substringAfter('=')
        })
    }
    fun readRules(): Map<String,Rules> {
        val rules=linkedMapOf<String,Rules>();
        for(record in readRecords("rules.txt")) {
            val f=record.fields;
            rules[record.label]=Rules(f.getValue("open_tanyao")=="yes",f.getValue("red_fives")=="yes",
                f.getValue("double_yakuman")=="yes",f.getValue("kazoe_yakuman")=="yes",f.getValue("kiriage")=="yes",
                f.getValue("honba").toInt())
        };
        return rules
    }
    class Meld(text: String) {
        val kind=text.take(1);
        val tiles=Tiles.parse(text.drop(1));
        val block=tiles?.map {
            it.kind
        }?.sorted()?:emptyList();
        fun valid(): Boolean {
            if(kind=="C")return block.size==3&&block.first()<27&&block.first()%9<=6&&block[1]==block.first()+1&&block[2]==block.first()+2;
            if(kind !in listOf("P","K","A"))return false;
            return block.size==(if(kind=="P")3 else 4)&&block.toSet().size==1
        }
    }
    class Situation(val label: String,fields: Map<String,String>,rules: Map<String,Rules>) {
        val ruleName=fields.getValue("rules");
        val rules=rules.getValue(ruleName);
        val hand=Tiles.parse(fields.getValue("hand"));
        val win=Tiles.parse(fields.getValue("win"));
        val melds=if(fields.getValue("melds")=="-")emptyList() else fields.getValue("melds").split(',').map {
            Meld(it)
        };
        val dora=Tiles.parse(fields.getValue("dora"));
        val ura=Tiles.parse(fields.getValue("ura"),true);
        val discards=Tiles.parse(fields.getValue("discards"),true);
        val by=fields.getValue("by");
        val seat=fields.getValue("seat");
        val discarder=fields.getValue("from");
        val round=fields.getValue("round");
        val seatTile=Tiles.windTile(seat);
        val roundTile=Tiles.windTile(round);
        val flags=if(fields.getValue("flags")=="-")emptySet() else fields.getValue("flags").split(',').toSet();
        val closed=melds.all {
            it.kind=="A"
        };
        val riichi="riichi" in flags||"double_riichi" in flags;
        val kanCount=melds.count {
            it.kind=="K"||it.kind=="A"
        };
        val honba=fields.getValue("honba").toInt();
        val sticks=fields.getValue("sticks").toInt();
        var winningTile=0;
        lateinit var handCounts: IntArray;
        lateinit var concealedCounts: IntArray;
        lateinit var meldCounts: IntArray;
        lateinit var allCounts: IntArray;
        lateinit var allTiles: List<Tiles.Tile>
        fun prepare() {
            winningTile=win!!.first().kind;
            handCounts=Tiles.counts(hand!!);
            val concealed=hand!!+win!!;
            concealedCounts=Tiles.counts(concealed);
            val meldTiles=melds.flatMap {
                it.tiles!!
            };
            meldCounts=Tiles.counts(meldTiles);
            allTiles=concealed+meldTiles;
            allCounts=Tiles.counts(allTiles)
        }
    }
    class WaitingHand(record: Record,rules: Map<String,Rules>) {
        val label=record.label;
        val fields=record.fields;
        val rules=rules.getValue(fields.getValue("rules"));
        val hand=Tiles.parse(fields.getValue("hand"));
        val dora=Tiles.parse(fields.getValue("dora"));
        val discards=Tiles.parse(fields.getValue("discards"),true);
        val visible=Tiles.parse(fields.getValue("visible"),true);
        lateinit var counts: IntArray;
        lateinit var knownCounts: IntArray
    }
    class Candidate(val formType: String,val pair: Int,val sets: List<List<Int>>,val winningBlock: List<Int>?,
        val form: String,val wait: String) {
        var category="none";
        var yaku: List<Yaku.Item> = emptyList();
        var yakuman: List<Yaku.Item> = emptyList();
        var fuItems: List<Yaku.Item> = emptyList();
        var multiplier=0;
        var han=0;
        var fu=0;
        var fuTotal=0;
        var base=0;
        var dora=0;
        var aka=0;
        var ura=0
    }
    fun copyError(allTiles: List<Tiles.Tile>,rules: Rules): String? {
        val reds=IntArray(3);
        for(tile in allTiles)if(tile.red)reds[tile.kind/9]++;
        if(!rules.redFives&&reds.any {
            it>0
        })return "red five not allowed";
        val counts=Tiles.counts(allTiles);
        for(kind in 0 until 34)if(counts[kind]>=5)return "too many copies of ${Tiles.name(kind)}";
        for(suit in 0..2)if(reds[suit]>=2)return "too many copies of 0${Tiles.suits[suit]}";
        return null
    }
    fun validateSituation(s: Situation): String? {
        if(s.hand==null||s.win==null||s.dora==null||s.ura==null||s.discards==null||s.melds.any {
            it.tiles==null
        }
        ||s.win.size!=1)return "bad tile notation";
        if(s.melds.size>=5||s.melds.any {
            !it.valid()
        })return "bad meld";
        if(s.hand.size!=13-3*s.melds.size)return "wrong tile count";
        s.prepare();
        val error=copyError(s.allTiles+s.dora+s.ura+s.discards,s.rules);
        if(error!=null)return error;
        if(s.by=="tsumo"&&s.discarder!="-"||s.by=="ron"&&(s.discarder=="-"||s.discarder==s.seat))return "invalid discarder";
        val f=s.flags;
        for(flag in Yaku.flags)if(flag in f) {
            val valid=when(flag) {
                "riichi"->s.closed;
                "double_riichi"->s.closed&&"riichi" !in f;
                "ippatsu"->s.riichi&&"rinshan" !in f;
                "haitei"->s.by=="tsumo"&&"rinshan" !in f;
                "houtei"->s.by=="ron"&&"chankan" !in f;
                "rinshan"->s.by=="tsumo"&&s.kanCount>=1;
                "chankan"->s.by=="ron";
                "tenhou"->s.seat=="E"&&s.by=="tsumo"&&s.melds.isEmpty()&&f.size==1;
                else->s.seat!="E"&&s.by=="tsumo"&&s.melds.isEmpty()&&f.size==1
            };
            if(!valid)return "invalid flag $flag"
        };
        if(s.dora.size!=1+s.kanCount)return "invalid dora indicators";
        if(s.riichi&&s.ura.size!=s.dora.size||!s.riichi&&s.ura.isNotEmpty())return "invalid ura indicators";
        if(s.riichi&&s.sticks==0)return "invalid sticks";
        if(!Decomposition.winning(s.concealedCounts,s.melds.size))return "not a winning hand";
        return null
    }
    fun validateWaiting(hand: WaitingHand): String? {
        if(hand.hand==null||hand.dora==null||hand.discards==null||hand.visible==null)return "bad tile notation";
        if(hand.hand.size!=13)return "wrong tile count";
        val observed=hand.hand+hand.dora+hand.discards+hand.visible;
        val error=copyError(observed,hand.rules);
        if(error==null) {
            hand.counts=Tiles.counts(hand.hand);
            hand.knownCounts=Tiles.counts(observed)
        };
        return error
    }
    fun candidates(s: Situation): List<Candidate> {
        val result=mutableListOf<Candidate>();
        val winning=s.winningTile;
        val counts=s.concealedCounts;
        for(split in Decomposition.standard(counts,s.melds.size)) {
            val blocks=listOf(listOf(split.pair,split.pair))+split.sets;
            val choices=blocks.filter {
                winning in it
            }.distinct();
            for(chosen in choices) {
                val parts=mutableListOf("standard");
                var marked=false;
                for(block in blocks) {
                    var notation=Tiles.block(block);
                    if(block==chosen&&!marked) {
                        notation+="*";
                        marked=true
                    };
                    parts.add(notation)
                };
                for(meld in s.melds)parts.add(meld.kind+Tiles.block(meld.block));
                val wait=Decomposition.waitShape("standard",chosen,winning,s.handCounts);
                result.add(Candidate("standard",split.pair,split.sets,chosen,parts.joinToString(" "),wait))
            }
        };
        if(s.melds.isEmpty()&&Decomposition.sevenPairs(counts)) {
            val parts=mutableListOf("chiitoitsu");
            for(kind in 0 until 34)if(counts[kind]>0)parts.add(Tiles.block(listOf(kind,kind))+if(kind==winning)"*" else "");
            result.add(Candidate("chiitoitsu",-1,emptyList(),null,parts.joinToString(" "),"tanki"))
        };
        if(s.melds.isEmpty()&&Decomposition.thirteenOrphans(counts)) {
            val parts=mutableListOf("kokushi");
            for(kind in Tiles.yaochuuKinds)parts.add(Tiles.block(List(counts[kind]) {
                kind
            })+if(kind==winning)"*" else "");
            val wait=Decomposition.waitShape("kokushi",null,winning,s.handCounts);
            result.add(Candidate("kokushi",-1,emptyList(),null,parts.joinToString(" "),wait))
        };
        return result.sortedBy {
            it.form
        }
    }
    fun blockFacts(s: Situation,candidate: Candidate): Facts {
        val triplets=mutableListOf<Scoring.Triplet>();
        val sequences=mutableListOf<Int>();
        val concealedSequences=mutableListOf<List<Int>>();
        for(block in candidate.sets)if(block.first()==block.last())triplets.add(Scoring.Triplet(block,
            s.by=="tsumo"||block!=candidate.winningBlock,false))else {
            sequences.add(block.first());
            concealedSequences.add(block)
        };
        for(meld in s.melds)if(meld.kind=="C")sequences.add(meld.block.first()) else triplets.add(Scoring.Triplet(meld.block,
            meld.kind=="A",meld.kind=="K"||meld.kind=="A"));
        return Facts(triplets,sequences,concealedSequences)
    }
    fun yakumanNames(s: Situation,candidate: Candidate,kinds: Set<Int>,triplets: List<Scoring.Triplet>): Set<String> {
        val names=s.flags.intersect(setOf("tenhou","chiihou")).toMutableSet();
        if(kinds.all {
            Tiles.honor(it)
        })names.add("tsuuiisou");
        if(kinds.all {
            Tiles.terminal(it)
        })names.add("chinroutou");
        if(kinds.all {
            it in Tiles.green
        })names.add("ryuuiisou");
        val suits=kinds.map {
            it/9
        }.toSet();
        if(s.melds.isEmpty()&&suits.size==1&&3 !in suits) {
            val start=suits.first()*9;
            if(s.allCounts[start]>=3&&s.allCounts[start+8]>=3&&(1..7).all {
                s.allCounts[start+it]>=1
            }) {
                val initial=s.handCounts.copyOfRange(start,start+9);
                names.add(if(initial.contentEquals(intArrayOf(3,1,1,1,1,1,1,1,3)))"junsei_chuuren" else "chuuren")
            }
        };
        if(candidate.formType=="kokushi")names.add(if(candidate.wait=="thirteen")"kokushi_13" else "kokushi");
        if(candidate.formType=="standard") {
            val concealed=triplets.count {
                it.concealed
            };
            val dragons=triplets.count {
                it.kinds.first()>=31
            };
            val winds=triplets.count {
                it.kinds.first() in 27..30
            };
            val kans=triplets.count {
                it.kan
            };
            if(concealed==4)names.add(if(candidate.wait=="tanki")"suuankou_tanki" else "suuankou");
            if(dragons==3)names.add("daisangen");
            if(winds==4)names.add("daisuushii");
            if(winds==3&&candidate.pair in 27..30)names.add("shousuushii");
            if(kans==4)names.add("suukantsu")
        };
        return names
    }
    fun ordinaryNames(s: Situation,c: Candidate,kinds: Set<Int>,facts: Facts): Set<String> {
        val names=s.flags.intersect(Yaku.flags.take(7).toSet()).toMutableSet();
        if(s.closed&&s.by=="tsumo")names.add("menzen_tsumo");
        if(kinds.all {
            !Tiles.yaochuu(it)
        }
        &&(s.closed||s.rules.openTanyao))names.add("tanyao");
        if(kinds.all {
            Tiles.yaochuu(it)
        })names.add("honroutou");
        val numberSuits=kinds.filter {
            it<27
        }.map {
            it/9
        }.toSet();
        val honors=kinds.any {
            Tiles.honor(it)
        };
        if(numberSuits.size==1)names.add(if(honors)"honitsu" else "chinitsu");
        if(c.formType=="chiitoitsu")names.add("chiitoitsu");
        if(c.formType!="standard")return names;
        val yakuhaiPair=c.pair>=31||c.pair==s.seatTile||c.pair==s.roundTile;
        if(s.closed&&s.melds.isEmpty()&&facts.concealedSequences.size==4&&!yakuhaiPair&&c.wait=="ryanmen")names.add("pinfu");
        val repeated=facts.concealedSequences.groupingBy {
            it
        }.eachCount();
        if(s.closed&&facts.concealedSequences.size==4&&repeated.values.sumOf {
            it/2
        }
        ==2)names.add("ryanpeikou") else if(s.closed&&repeated.values.any {
            it>=2
        })names.add("iipeikou");
        val tripletKinds=facts.triplets.map {
            it.kinds.first()
        }.toSet();
        val concealed=facts.triplets.count {
            it.concealed
        };
        val kans=facts.triplets.count {
            it.kan
        };
        val dragons=tripletKinds.count {
            it>=31
        };
        val valued=listOf(31 to "haku",32 to "hatsu",33 to "chun",s.seatTile to "jikaze",s.roundTile to "bakaze");
        for((kind,name) in valued)if(kind in tripletKinds)names.add(name);
        if(facts.triplets.size==4)names.add("toitoi");
        if(concealed==3)names.add("sanankou");
        val sequenceKinds=facts.sequences.toSet();
        if((0..6).any {
            start->(0..2).all {
                start+it*9 in sequenceKinds
            }
        })names.add("sanshoku_doujun");
        if((0..8).any {
            number->(0..2).all {
                number+it*9 in tripletKinds
            }
        })names.add("sanshoku_doukou");
        if((0..2).any {
            suit->listOf(0,3,6).all {
                suit*9+it in sequenceKinds
            }
        })names.add("ittsu");
        val blocks=listOf(listOf(c.pair,c.pair))+c.sets+s.melds.map {
            it.block
        };
        if(facts.sequences.isNotEmpty()&&blocks.all {
            block->block.any {
                Tiles.yaochuu(it)
            }
        })names.add(if(honors)"chanta" else "junchan");
        if(kans==3)names.add("sankantsu");
        if(dragons==2&&c.pair>=31)names.add("shousangen");
        return names
    }
    fun evaluateCandidate(s: Situation,candidate: Candidate): Candidate {
        val kinds=(0 until 34).filter {
            s.allCounts[it]>0
        }.toSet();
        val facts=blockFacts(s,candidate);
        var names=yakumanNames(s,candidate,kinds,facts.triplets);
        candidate.yakuman=Yaku.yakuman(names,s.rules.doubleYakuman);
        if(candidate.yakuman.isNotEmpty()) {
            candidate.multiplier=candidate.yakuman.sumOf {
                it.value
            };
            candidate.base=8000*candidate.multiplier;
            candidate.category="yakuman";
            return candidate
        };
        names=ordinaryNames(s,candidate,kinds,facts);
        candidate.yaku=Yaku.ordinary(names,s.closed);
        candidate.dora=s.dora!!.sumOf {
            s.allCounts[Tiles.nextDora(it.kind)]
        };
        candidate.ura=s.ura!!.sumOf {
            s.allCounts[Tiles.nextDora(it.kind)]
        };
        candidate.aka=s.allTiles.count {
            it.red
        };
        val fu=Scoring.fuBreakdown(candidate.formType,candidate.pair,facts.triplets,candidate.wait,s.closed,
            s.by,s.seatTile,s.roundTile,"pinfu" in names);
        candidate.fuItems=fu.items;
        candidate.fuTotal=fu.total;
        candidate.fu=fu.rounded;
        if(candidate.yaku.isNotEmpty()) {
            candidate.han=candidate.dora+candidate.aka+candidate.ura+candidate.yaku.sumOf {
                it.value
            };
            val limit=Scoring.limit(candidate.han,candidate.fu,s.rules);
            candidate.category=limit.category;
            candidate.base=limit.base
        };
        return candidate
    }
    fun evaluateCandidates(s: Situation)=candidates(s).map {
        evaluateCandidate(s,it)
    }
    fun compareCandidates(a: Candidate,b: Candidate): Int {
        var compared=b.base.compareTo(a.base);
        if(compared!=0)return compared;
        compared=b.yakuman.isNotEmpty().compareTo(a.yakuman.isNotEmpty());
        if(compared!=0)return compared;
        if(a.yakuman.isEmpty()&&b.yakuman.isEmpty()) {
            compared=b.han.compareTo(a.han);
            if(compared!=0)return compared;
            compared=b.fu.compareTo(a.fu);
            if(compared!=0)return compared
        };
        return a.form.compareTo(b.form)
    }
    fun bestCandidate(candidates: List<Candidate>)=candidates.filter {
        it.base>=1
    }.minWithOrNull(Comparator {
        a,b->compareCandidates(a,b)
    })
    fun names(items: List<Yaku.Item>,separator: String)=items.joinToString(separator) {
        it.name
    }
    fun candidateLine(c: Candidate): String {
        val evaluation=when {
            c.yakuman.isNotEmpty()->"yakuman ${c.multiplier} base ${c.base} yaku ${names(c.yakuman,",")}";
            c.yaku.isEmpty()->"no_yaku";
            else->"han ${c.han} fu ${c.fu} base ${c.base} yaku ${names(c.yaku,",")}"
        };
        return "CANDIDATE ${c.form} = ${c.wait} $evaluation"
    }
    fun winningLines(s: Situation,c: Candidate): Winning {
        val lines=mutableListOf("FORM ${c.form}","WAIT ${c.wait}");
        if(c.yakuman.isNotEmpty()) {
            for(item in c.yakuman)lines.add("YAKUMAN ${item.name} ${item.value}");
            lines.add("SCORE yakuman ${c.multiplier} base ${c.base}")
        }else {
            for(item in c.yaku)lines.add("YAKU ${item.name} ${item.value}");
            lines.add("DORA dora ${c.dora} aka ${c.aka} ura ${c.ura}");
            for(item in c.fuItems)lines.add("FU ${item.name} ${item.value}");
            lines.add("FU total ${c.fuTotal} ${c.fu}");
            lines.add("SCORE han ${c.han} fu ${c.fu} limit ${c.category} base ${c.base}")
        };
        val p=Scoring.payments(c.base,s.seat=="E",s.by);
        lines.add(if(s.by=="ron")"PAY ron ${p.ron}" else if(s.seat=="E")"PAY tsumo all ${p.nondealer}" else "PAY tsumo dealer ${p.dealer} nondealer ${p.nondealer}");
        val honba=s.honba*s.rules.honba;
        val sticks=s.sticks*1000;
        val gain=p.points+honba+sticks;
        lines.add("BONUS honba $honba sticks $sticks");
        lines.add("TOTAL points ${p.points} gain $gain");
        val delta=IntArray(4);
        if(s.by=="ron")delta[Tiles.winds.indexOf(s.discarder)]=-p.ron-honba else for(i in 0..3)if(i!=Tiles.winds.indexOf(s.seat))delta[i]=-(if(i==0)p.dealer else p.nondealer)-honba/3;
        delta[Tiles.winds.indexOf(s.seat)]=gain;
        lines.add("DELTA "+(0..3).joinToString(" ") {
            i->"${Tiles.winds[i]} "+(if(delta[i]>0)"+" else "")+delta[i]
        });
        return Winning(lines,p.points)
    }
    fun hypothetical(hand: WaitingHand,winning: Int,method: String,rules: Map<String,Rules>): Situation {
        val fields=hand.fields.toMutableMap();
        fields["melds"]="-";
        fields["win"]=Tiles.name(winning);
        fields["by"]=method;
        fields["from"]=if(method=="tsumo")"-" else if(fields.getValue("seat")=="E")"S" else "E";
        fields["flags"]=if(fields.getValue("riichi")=="yes")"riichi" else "-";
        fields["ura"]="-";
        fields["honba"]="0";
        fields["sticks"]="0";
        return Situation(hand.label,fields,rules).also {
            it.prepare()
        }
    }
    class Counts {
        val values=mutableMapOf<String,Int>();
        fun get(key: String)=values.getOrDefault(key,0);
        fun add(key: String,amount: Int) {
            values[key]=get(key)+amount
        };
        fun named(names: List<String>)=names.joinToString(" ") {
            "$it ${get(it)}"
        }
    }
    class Reports(val rules: Map<String,Rules>) {
        val situations=readRecords("hands.txt");
        val hands=readRecords("waits.txt");
        val stats=Counts();
        val winCounts=Counts();
        val waitCounts=Counts();
        val limitCounts=Counts();
        val yakuCounts=Counts();
        val hanCounts=sortedMapOf<Int,Int>();
        val fuCounts=sortedMapOf<Int,Int>();
        val ruleCounts=rules.keys.associateWith {
            Counts()
        };
        var maximum=0;
        var maximumHand="-";
        val summary=mutableListOf("hand,han,fu,points,yaku")
        fun recordWin(s: Situation,c: Candidate,points: Int) {
            stats.add("wins",1);
            stats.add("points",points);
            ruleCounts.getValue(s.ruleName).add("wins",1);
            ruleCounts.getValue(s.ruleName).add("points",points);
            winCounts.add((if(s.seat=="E")"dealer_" else "nondealer_")+s.by,1);
            waitCounts.add(c.wait,1);
            limitCounts.add(c.category,1);
            val selected=if(c.yakuman.isEmpty())c.yaku else c.yakuman;
            for(item in selected)yakuCounts.add(item.name,1);
            val han: String;
            val fu: String;
            if(c.yakuman.isNotEmpty()) {
                han="Y${c.multiplier}";
                fu="-"
            }else {
                han=c.han.toString();
                fu=c.fu.toString();
                hanCounts[c.han]=hanCounts.getOrDefault(c.han,0)+1;
                fuCounts[c.fu]=fuCounts.getOrDefault(c.fu,0)+1
            };
            summary.add("${s.label},$han,$fu,$points,"+names(selected,";"));
            if(points>maximum) {
                maximum=points;
                maximumHand=s.label
            }
        }
        fun scores(): List<String> {
            val lines=mutableListOf<String>();
            for(record in situations) {
                val s=Situation(record.label,record.fields,rules);
                ruleCounts.getValue(s.ruleName).add("hands",1);
                lines.add("HAND ${s.label}");
                val error=validateSituation(s);
                if(error!=null) {
                    stats.add("errors",1);
                    lines.add("ERROR $error");
                    summary.add("${s.label},-,-,0,ERROR");
                    continue
                };
                val waiting=Decomposition.waitingTiles(s.handCounts,s.meldCounts,s.melds.size);
                lines.add("WAITS "+waiting.joinToString(" ") {
                    Tiles.name(it)
                });
                val evaluated=evaluateCandidates(s);
                lines.addAll(evaluated.map {
                    candidateLine(it)
                });
                val furiten=s.by=="ron"&&s.discards!!.any {
                    it.kind in waiting
                };
                if(furiten) {
                    stats.add("furiten",1);
                    lines.add("RESULT furiten");
                    summary.add("${s.label},-,-,0,FURITEN");
                    continue
                };
                val best=bestCandidate(evaluated);
                if(best==null) {
                    stats.add("no_yaku",1);
                    lines.add("RESULT no_yaku");
                    summary.add("${s.label},-,-,0,NO_YAKU");
                    continue
                };
                val report=winningLines(s,best);
                lines.addAll(report.lines);
                recordWin(s,best,report.points)
            };
            lines.addAll(scoreStatistics());
            return lines
        }
        fun scoreStatistics(): List<String> {
            val lines=mutableListOf("STATS hands ${situations.size} wins ${stats.get("wins")} furiten ${stats.get("furiten")} no_yaku ${stats.get("no_yaku")} errors ${stats.get("errors")}",
                "WINS "+winCounts.named(winOrder),"WAIT_COUNT "+waitCounts.named(waitOrder));
            for((han,count) in hanCounts)lines.add("HAN_COUNT $han $count");
            for((fu,count) in fuCounts)lines.add("FU_COUNT $fu $count");
            for(category in Yaku.categories)lines.add("LIMIT $category ${limitCounts.get(category)}");
            val names=Yaku.yaku.map {
                it.name
            }+Yaku.yakuman.map {
                it.name
            };
            for(name in names)if(yakuCounts.get(name)>0)lines.add("YAKU_COUNT $name ${yakuCounts.get(name)}");
            lines.add("POINTS total ${stats.get("points")} max $maximum hand $maximumHand");
            for((name,count) in ruleCounts)lines.add("RULE $name "+count.named(listOf("hands","wins","points")));
            return lines
        }
        fun acceptance(hand: WaitingHand,current: Int): List<Acceptance> {
            val result=mutableListOf<Acceptance>();
            val counts=hand.counts.copyOf();
            for(kind in 0 until 34) {
                if(counts[kind]>=4)continue;
                counts[kind]++;
                val advancing=Shanten.numbers(counts).min()<current;
                counts[kind]--;
                if(advancing)result.add(Acceptance(kind,4-hand.knownCounts[kind]))
            };
            return result
        }
        fun tenpaiLines(hand: WaitingHand,waiting: List<Acceptance>,furiten: Boolean): List<String> {
            val lines=mutableListOf<String>();
            val methods=listOf("ron","tsumo");
            val best=arrayOfNulls<WaitScore>(2);
            for(tile in waiting) {
                val results=Array(2) {
                    ""
                };
                for(i in 0..1) {
                    if(i==0&&furiten) {
                        results[i]="furiten";
                        continue
                    };
                    val s=hypothetical(hand,tile.kind,methods[i],rules);
                    val candidate=bestCandidate(evaluateCandidates(s));
                    if(candidate==null) {
                        results[i]="no_yaku";
                        continue
                    };
                    val points=Scoring.payments(candidate.base,s.seat=="E",methods[i]).points;
                    results[i]=points.toString();
                    if(best[i]==null||points>best[i]!!.points)best[i]=WaitScore(tile.kind,points)
                };
                lines.add("WAIT ${Tiles.name(tile.kind)} left ${tile.remaining} ron ${results[0]} tsumo ${results[1]}")
            };
            val choices=best.map {
                if(it==null)"none" else "${Tiles.name(it.kind)} ${it.points}"
            };
            lines.add("BEST ron ${choices[0]} tsumo ${choices[1]}");
            return lines
        }
        fun waits(): List<String> {
            val lines=mutableListOf<String>();
            val statistics=Counts();
            val counts=IntArray(7);
            for(record in hands) {
                val hand=WaitingHand(record,rules);
                lines.add("HAND ${hand.label}");
                val error=validateWaiting(hand);
                if(error!=null) {
                    statistics.add("errors",1);
                    lines.add("ERROR $error");
                    continue
                };
                val numbers=Shanten.numbers(hand.counts);
                val current=numbers.min();
                counts[current]++;
                lines.add("SHANTEN standard ${numbers[0]} chiitoitsu ${numbers[1]} kokushi ${numbers[2]}");
                val accepted=acceptance(hand,current);
                val total=accepted.sumOf {
                    it.remaining
                };
                if(current!=0) {
                    val suffix=accepted.joinToString("") {
                        " ${Tiles.name(it.kind)}:${it.remaining}"
                    };
                    lines.add("ACCEPT kinds ${accepted.size} tiles $total$suffix");
                    continue
                };
                statistics.add("tenpai",1);
                val discarded=hand.discards!!.map {
                    it.kind
                }.toSet();
                val furiten=accepted.any {
                    it.kind in discarded
                };
                if(furiten)statistics.add("furiten",1);
                lines.add("TENPAI kinds ${accepted.size} tiles $total furiten "+if(furiten)"yes" else "no");
                lines.addAll(tenpaiLines(hand,accepted,furiten))
            };
            lines.add("STATS hands ${hands.size} errors ${statistics.get("errors")} tenpai ${statistics.get("tenpai")} furiten ${statistics.get("furiten")}");
            for(i in 0..6)lines.add("SHANTEN_COUNT $i ${counts[i]}");
            return lines
        }
        fun write() {
            val scores=scores();
            val waits=waits();
            File("output").mkdirs();
            for((name,lines) in listOf("scores.txt" to scores,"waits.txt" to waits,"summary.csv" to summary))File("output/$name").writeText(lines.joinToString("\n")+"\n",
                Charsets.US_ASCII)
        }
    }
    fun run() {
        Reports(readRules()).write()
    }
}
fun main() {
    MahjongProgram.run()
}
