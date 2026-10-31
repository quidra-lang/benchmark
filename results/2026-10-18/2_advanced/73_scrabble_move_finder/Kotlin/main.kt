import java.io.File
import kotlin.math.abs
object Scrabble {
    val values=IntArray(128);
    val counts=IntArray(128);
    val weights=IntArray(128);
    val trie=DictionaryTrie();
    val topTotals=mutableMapOf<String,Int>();
    val validationTotals=mutableMapOf<String,Int>();
    val gameTotals=mutableMapOf<String,Int>();
    const val VOWELS="AEIOU";
    val strategies=setOf("score","tiles","equity")
    data class Evaluated(val move: Board.Move,val score: Int,val tiles: List<Board.Tile>,val words: String,
        val leave: String,val value: Int)
    data class Checked(val error: String?=null,val move: Board.Move?=null)
    class Statistics {
        var moves=0;
        var valid=0;
        var score=0;
        var loss=0;
        var plays=0;
        var bingos=0;
        var exchanges=0;
        var passes=0;
        var top=0
    }
    class Player(val name: String,val strategy: String,val threshold: Int=0,var rack: String="") {
        var score=0;
        val statistics=Statistics()
    }
    data class Highlight(val turn: Int,val player: String,val move: Evaluated)
    val standard=compareByDescending<Evaluated> {
        it.score
    }.thenBy {
        it.move.row
    }.thenBy {
        it.move.column
    }.thenBy {
        it.move.direction
    }.thenBy {
        it.move.word
    }
    fun validName(text: String)=text.matches(Regex("[a-z0-9_]{1,20}"))
    fun validNumber(text: String,low: Int,high: Int)=text.length<=10&&text.matches(Regex("0|[1-9][0-9]*"))&&text.toLong() in low.toLong()..high.toLong()
    fun validRack(text: String)=text.matches(Regex("[A-Z?]{1,7}"))
    fun collection(text: String)=text.toList().sorted().joinToString("").ifEmpty {
        "-"
    }
    fun tileKind(letter: Char)=if(letter in 'A'..'Z')letter else '?'
    fun removeTiles(rack: String,removed: String): String {
        val remaining=IntArray(128);
        for(c in rack)remaining[c.code]++;
        for(c in removed)remaining[c.code]--;
        return buildString {
            for(c in remaining.indices)repeat(remaining[c]) {
                append(c.toChar())
            }
        }
    }
    fun notation(move: Evaluated)=Board.position(move.move)+" "+move.move.word
    fun strategy(name: String)=when(name) {
        "tiles"->compareByDescending<Evaluated> {
            it.tiles.size
        }.then(standard);
        "equity"->compareByDescending<Evaluated> {
            it.score+it.value
        }.then(standard);
        else->standard
    }
    fun add(totals: MutableMap<String,Int>,key: String,value: Int) {
        totals[key]=totals.getOrDefault(key,0)+value
    }
    fun used(board: Array<CharArray>,rack: String): IntArray {
        val result=IntArray(128);
        for(tile in Board.tiles(board))result[tileKind(tile.letter).code]++;
        for(c in rack)result[c.code]++;
        return result
    }
    fun tileError(board: Array<CharArray>,rack: String): String? {
        val used=used(board,rack);
        for(letter in Game.TILE_ORDER)if(used[letter.code]>counts[letter.code])return "too many $letter";
        return null
    }
    fun unseen(board: Array<CharArray>,rack: String): String {
        val used=used(board,rack);
        return buildString {
            for(letter in Game.TILE_ORDER)repeat(counts[letter.code]-used[letter.code]) {
                append(letter)
            }
        }
    }
    fun board(rows: List<String>)=rows.map {
        it.toCharArray()
    }.toTypedArray()
    fun boardError(board: Array<CharArray>,rack: String): String? {
        if(board.size!=15)return "board rows ${board.size}";
        for((i,row) in board.withIndex())if(row.size!=15||row.any {
            it!='.'&&it !in 'A'..'Z'&&it !in 'a'..'z'
        })return "bad board row ${i+1}";
        val error=tileError(board,rack);
        if(error!=null)return error;
        if(Board.tiles(board).isNotEmpty()&&board[7][7]=='.')return "center empty";
        if(!Board.connected(board))return "disconnected";
        for(word in Board.words(board))if(!trie.contains(word.word.uppercase()))return "unknown word ${word.word} at ${Board.position(word)}";
        return null
    }
    fun jobError(job: List<String>,seen: Set<String>): String? {
        val fields=job.first().split(' ');
        val kind=fields[0];
        val name=fields[1];
        if(!validName(name))return "bad name";
        if(name in seen)return "duplicate name";
        if(kind=="TOPN") {
            if(!validNumber(fields[2],1,99))return "bad count";
            if(fields[3] !in strategies)return "bad order";
            val rack=job[1].split(' ')[1];
            if(!validRack(rack))return "bad rack";
            return boardError(board(job.drop(3)),rack)
        };
        if(kind=="VALIDATE")return boardError(board(job.drop(2).takeWhile {
            !it.startsWith("MOVE")
        }),"");
        if(!validNumber(fields[2],1,2147483646))return "bad seed";
        if(job.size-1 !in 2..4)return "bad player count ${job.size-1}";
        val names=mutableSetOf<String>();
        for(i in 1 until job.size) {
            val player=job[i].split(' ');
            if(!validName(player[1])||player[2] !in strategies||kind=="GAME"&&!validNumber(player[3],
                0,99))return "bad player $i";
            if(!names.add(player[1]))return "duplicate player $i"
        };
        return null
    }
    fun leaveValue(rack: String): Int {
        val counts=IntArray(128);
        var value=0;
        var vowels=0;
        var consonants=0;
        for(c in rack) {
            counts[c.code]++;
            value+=weights[c.code];
            if(c in VOWELS)vowels++ else if(c!='?')consonants++
        };
        var duplicates=0;
        for(c in MoveGenerator.LETTERS)duplicates+=maxOf(0,counts[c.code]-1);
        return value-4*duplicates-3*maxOf(0,abs(vowels-consonants)-1)
    }
    fun bestLeave(rack: String): String {
        var best="";
        var bestValue=0;
        for(mask in 0 until (1 shl rack.length)-1) {
            val candidate=buildString {
                for(i in rack.indices)if((mask and (1 shl i))!=0)append(rack[i])
            }.toList().sorted().joinToString("");
            val value=leaveValue(candidate);
            if(value>bestValue||value==bestValue&&(candidate.length>best.length||candidate.length==best.length&&candidate<best)) {
                best=candidate;
                bestValue=value
            }
        };
        return best
    }
    fun evaluate(board: Array<CharArray>,rack: String,move: Board.Move): Evaluated {
        val score=Scoring.evaluate(board,move,values);
        val leave=removeTiles(rack,score.tiles.map {
            tileKind(it.letter)
        }.joinToString(""));
        val words=score.words.joinToString(",") {
            "${it.word.word}:${it.score}"
        };
        return Evaluated(move,score.score,score.tiles,words,leave,leaveValue(leave))
    }
    fun legal(board: Array<CharArray>,rack: String)=MoveGenerator.generate(board,rack,trie).map {
        evaluate(board,rack,it)
    }.sortedWith(standard)
    fun positionSummary(board: Array<CharArray>): String {
        val words=Board.words(board);
        val tiles=Board.tiles(board);
        val longest=words.maxByOrNull {
            it.word.length
        }?.word?:"-";
        val blanks=tiles.count {
            it.letter in 'a'..'z'
        };
        val premiums=IntArray(128);
        for(tile in tiles)premiums[Board.premiums[tile.row][tile.column].code]++;
        return "position tiles=${tiles.size} words=${words.size} longest=$longest blanks=$blanks premiums=TW:${premiums['#'.code]},DW:${premiums['*'.code]},TL:${premiums['^'.code]},DL:${premiums['+'.code]}"
    }
    fun checksStatistics(checks: Array<IntArray>): String {
        var count=0;
        var dead=0;
        var total=0;
        for(row in checks)for(mask in row)if(mask!=-1) {
            count++;
            if(mask==0)dead++;
            total+=mask.countOneBits()
        };
        return "$count,$dead,$total"
    }
    fun topn(job: List<String>): List<String> {
        val header=job.first().split(' ');
        val name=header[1];
        val count=header[2].toInt();
        val order=header[3];
        val rack=job[1].split(' ')[1];
        val board=board(job.drop(3));
        val moves=legal(board,rack);
        val shown=moves.sortedWith(strategy(order)).take(count);
        val unseen=unseen(board,rack);
        val anchors=MoveGenerator.anchors(board);
        val anchorCount=anchors.sumOf {
            it.count {
                value->value
            }
        };
        val vowels=rack.count {
            it in VOWELS
        };
        val blanksRack=rack.count {
            it=='?'
        };
        val consonants=rack.length-vowels-blanksRack;
        val across=moves.count {
            it.move.direction==0
        };
        val bingos=moves.count {
            it.tiles.size==7
        };
        val blanks=moves.count {
            it.tiles.any {
                tile->tileKind(tile.letter)=='?'
            }
        };
        val lines=mutableListOf("TOPN $name n=$count order=$order rack=${collection(rack)}","board tiles=${Board.tiles(board).size} anchors=$anchorCount",
            "unseen count=${unseen.length} tiles=${collection(unseen)}","rack vowels=$vowels consonants=$consonants blanks=$blanksRack value=${Game.points(rack,values)}",
            "checks across=${checksStatistics(MoveGenerator.checks(board,trie))} down=${checksStatistics(MoveGenerator.checks(Board.transpose(board),trie))}",
            "moves total=${moves.size} across=$across down=${moves.size-across} bingos=$bingos blanks=$blanks");
        lines.add("best_by_tiles"+(1..7).joinToString("") {
            number->" $number=${moves.filter{it.tiles.size==number}.maxOfOrNull{it.score}?.toString()?:"-"}"
        });
        val keep=bestLeave(rack);
        lines.add("exchange keep=${collection(keep)} value=${leaveValue(keep)}");
        val anagrams=trie.anagrams(rack).sortedWith(compareByDescending<String> {
            it.length
        }.thenBy {
            it
        });
        lines.add("anagrams total=${anagrams.size} top=${anagrams.take(10).joinToString(",").ifEmpty{"-"}}");
        for(word in Board.words(board))if(word.word.length>=3) {
            val upper=word.word.uppercase();
            val front=MoveGenerator.LETTERS.filter {
                trie.contains(it+upper)
            };
            val back=MoveGenerator.LETTERS.filter {
                trie.contains(upper+it)
            };
            if(front.isNotEmpty()||back.isNotEmpty())lines.add("hook ${Board.position(word)} ${word.word} front=${front.ifEmpty{"-"}} back=${back.ifEmpty{"-"}}")
        };
        val nets=if(unseen.length in 1..7&&shown.isNotEmpty())shown.map {
            move->val replies=legal(Scoring.apply(board,move.tiles),unseen);
            move.score-(replies.firstOrNull()?.score?:0)
        } else null;
        if(nets!=null) {
            val best=nets.indices.maxBy {
                nets[it]
            };
            lines.add("endgame opponent=${collection(unseen)} best=${best+1} net=${nets[best]}")
        };
        for((i,move) in shown.withIndex()) {
            val net=if(nets==null)"" else " net=${nets[i]}";
            lines.add("${i+1} ${notation(move)} score=${move.score} tiles=${move.tiles.size} leave=${collection(move.leave)} value=${move.value}$net words=${move.words}")
        };
        add(topTotals,"moves",moves.size);
        add(topTotals,"bingos",bingos);
        return lines
    }
    fun recordError(board: Array<CharArray>,player: String,rack: String,action: List<String>): Checked {
        if(!validName(player))return Checked("bad player");
        if(!validRack(rack))return Checked("bad rack");
        val error=tileError(board,rack);
        if(error!=null)return Checked(error);
        if(action.size==1&&action.first()=="PASS")return Checked();
        if(action.first()=="EXCHANGE") {
            val returned=action[1];
            if(!validRack(returned))return Checked("bad exchange");
            val available=rack.groupingBy {
                it
            }.eachCount();
            val requested=returned.groupingBy {
                it
            }.eachCount();
            for(c in returned)if(requested.getValue(c)>available.getOrDefault(c,0))return Checked("rack lacks $c");
            return Checked()
        };
        val word=action[1];
        val move=Board.parse(action.first(),word)?:return Checked("bad position");
        if(!word.matches(Regex("[A-Za-z]{2,15}")))return Checked("bad word");
        val cells=Scoring.squares(move);
        if(cells.any {
            !Board.inside(it.row,it.column)
        })return Checked("off board");
        for(tile in cells)if(board[tile.row][tile.column]!='.'&&board[tile.row][tile.column]!=tile.letter)return Checked("mismatch at ${Board.square(tile.row,tile.column)}");
        val dr=move.direction;
        val dc=1-dr;
        val br=move.row-dr;
        val bc=move.column-dc;
        val ar=move.row+dr*word.length;
        val ac=move.column+dc*word.length;
        if(Board.inside(br,bc)&&board[br][bc]!='.'||Board.inside(ar,ac)&&board[ar][ac]!='.')return Checked("not whole word");
        val tiles=Scoring.placement(board,move);
        if(tiles.isEmpty())return Checked("no new tiles");
        val available=IntArray(128);
        for(c in rack)available[c.code]++;
        for(tile in tiles) {
            val kind=tileKind(tile.letter);
            if(available[kind.code]==0)return Checked("rack lacks $kind");
            available[kind.code]--
        };
        if(Board.tiles(board).isEmpty()) {
            if(tiles.none {
                it.row==7&&it.column==7
            })return Checked("center not covered")
        } else if(tiles.none {
            tile->Board.neighbors(tile.row,tile.column).any {
                board[it.row][it.column]!='.'
            }
        })return Checked("not connected");
        for(formed in listOf(move)+Scoring.crosses(board,move))if(!trie.contains(formed.word.uppercase()))return Checked("unknown word ${formed.word} at ${Board.position(formed)}");
        return Checked(move=move)
    }
    fun validate(job: List<String>): List<String> {
        val name=job.first().split(' ')[1];
        var board=board(job.subList(2,17));
        val records=job.drop(17);
        val lines=mutableListOf("VALIDATE $name");
        val players=linkedMapOf<String,Statistics>();
        var valid=0;
        var invalid=0;
        var scoreTotal=0;
        var bestTotal=0;
        var lossTotal=0;
        for((i,line) in records.withIndex()) {
            val fields=line.split(' ');
            val player=fields[1];
            val rack=fields[2];
            val action=fields.drop(3);
            val prefix="move ${i+1} $player "+action.joinToString(" ");
            val checked=recordError(board,player,rack,action);
            if(checked.error!="bad player")players.getOrPut(player) {
                Statistics()
            }.moves++;
            if(checked.error!=null) {
                invalid++;
                lines.add("$prefix invalid ${checked.error}");
                continue
            };
            val legal=legal(board,rack);
            val best=legal.firstOrNull()?.score?:0;
            val evaluated=checked.move?.let {
                evaluate(board,rack,it)
            };
            val score=evaluated?.score?:0;
            val rank=if(evaluated==null)0 else legal.indexOfFirst {
                it.tiles==evaluated.tiles
            }+1;
            val statistics=players.getValue(player);
            statistics.valid++;
            statistics.score+=score;
            statistics.loss+=best-score;
            valid++;
            scoreTotal+=score;
            bestTotal+=best;
            lossTotal+=best-score;
            if(evaluated==null)lines.add("$prefix score=0 total=${statistics.score} moves=${legal.size} best=$best") else {
                lines.add("$prefix score=$score total=${statistics.score} tiles=${evaluated.tiles.size} rank=$rank/${legal.size} best=$best words=${evaluated.words}");
                board=Scoring.apply(board,evaluated.tiles)
            }
        };
        for((player,statistics) in players)lines.add("player $player moves=${statistics.moves} valid=${statistics.valid} score=${statistics.score} loss=${statistics.loss}");
        lines.add("total valid=$valid invalid=$invalid score=$scoreTotal best=$bestTotal loss=$lossTotal");
        lines.add(positionSummary(board));
        lines.addAll(Board.display(board));
        add(validationTotals,"moves",records.size);
        add(validationTotals,"valid",valid);
        add(validationTotals,"invalid",invalid);
        add(validationTotals,"loss",lossTotal);
        return lines
    }
    fun ordinary(job: List<String>): List<String> {
        val header=job.first().split(' ');
        val name=header[1];
        val seed=header[2].toInt();
        val random=Game.Minstd(seed);
        val bag=Game.bag(counts,random);
        var board=Board.empty();
        val players=mutableListOf<Player>();
        val lines=mutableListOf("GAME $name seed=$seed players=${job.size-1}");
        for(i in 1 until job.size) {
            val fields=job[i].split(' ');
            val player=Player(fields[1],fields[2],fields[3].toInt(),Game.draw(bag,7));
            players.add(player);
            lines.add("player $i ${player.name} strategy=${player.strategy} threshold=${player.threshold}")
        };
        var turn=0;
        var consecutive=0;
        var outgoing=-1;
        var highlight: Highlight?=null;
        while(true) {
            val index=turn%players.size;
            val player=players[index];
            turn++;
            val rack=player.rack;
            val statistics=player.statistics;
            val legal=legal(board,rack);
            val candidate=legal.minWithOrNull(strategy(player.strategy));
            val prefix="turn $turn ${player.name} rack=${collection(rack)} moves=${legal.size}";
            if(candidate!=null&&!(candidate.score<player.threshold&&bag.size>=7)) {
                val best=legal.first().score;
                board=Scoring.apply(board,candidate.tiles);
                player.score+=candidate.score;
                val drawn=Game.draw(bag,7-candidate.leave.length);
                player.rack=candidate.leave+drawn;
                statistics.plays++;
                if(candidate.tiles.size==7)statistics.bingos++;
                statistics.top=maxOf(statistics.top,candidate.score);
                statistics.loss+=best-candidate.score;
                consecutive=0;
                val old=highlight;
                if(old==null||candidate.score>old.move.score)highlight=Highlight(turn,player.name,candidate);
                lines.add("$prefix best=$best play ${notation(candidate)} score=${candidate.score} total=${player.score} draw=${collection(drawn)} bag=${bag.size}");
                if(player.rack.isEmpty()&&bag.isEmpty()) {
                    outgoing=index;
                    break
                }
            } else if(bag.size>=7) {
                val keep=bestLeave(rack);
                val returned=removeTiles(rack,keep);
                val drawn=Game.exchange(bag,returned,random);
                player.rack=keep+drawn;
                statistics.exchanges++;
                consecutive++;
                lines.add("$prefix exchange keep=${collection(keep)} draw=${collection(drawn)} bag=${bag.size}")
            } else {
                statistics.passes++;
                consecutive++;
                lines.add("$prefix pass bag=${bag.size}")
            };
            if(consecutive==6)break
        };
        lines.add(if(outgoing<0)"end reason=scoreless turns=$turn" else "end reason=out player=${players[outgoing].name} turns=$turn");
        val adjustment=IntArray(players.size) {
            -Game.points(players[it].rack,values)
        };
        if(outgoing>=0)adjustment[outgoing]=players.indices.filter {
            it!=outgoing
        }.sumOf {
            Game.points(players[it].rack,values)
        };
        val totals=IntArray(players.size) {
            players[it].score+adjustment[it]
        };
        for((i,player) in players.withIndex())lines.add("final ${player.name} score=${player.score} rack=${collection(player.rack)} adjust=${if(adjustment[i]>0)"+" else ""}${adjustment[i]} total=${totals[i]}");
        val standings=players.indices.sortedWith(compareByDescending<Int> {
            totals[it]
        }.thenBy {
            it
        });
        for((rank,i) in standings.withIndex()) {
            val player=players[i];
            val s=player.statistics;
            lines.add("standing ${rank+1} ${player.name} total=${totals[i]} plays=${s.plays} bingos=${s.bingos} exchanges=${s.exchanges} passes=${s.passes} top=${s.top} loss=${s.loss}")
        };
        val maximum=totals.max();
        lines.add("winner "+players.indices.filter {
            totals[it]==maximum
        }.joinToString(",") {
            players[it].name
        });
        val bestHighlight=highlight;
        if(bestHighlight!=null)lines.add("highlight turn=${bestHighlight.turn} player=${bestHighlight.player} play ${notation(bestHighlight.move)} score=${bestHighlight.move.score}");
        lines.add(positionSummary(board));
        lines.addAll(Board.display(board));
        add(gameTotals,"turns",turn);
        for(player in players) {
            val s=player.statistics;
            add(gameTotals,"plays",s.plays);
            add(gameTotals,"exchanges",s.exchanges);
            add(gameTotals,"passes",s.passes);
            add(gameTotals,"bingos",s.bingos)
        };
        return lines
    }
    fun duplicate(job: List<String>): List<String> {
        val header=job.first().split(' ');
        val name=header[1];
        val seed=header[2].toInt();
        val random=Game.Minstd(seed);
        val bag=Game.bag(counts,random);
        var board=Board.empty();
        var rack=Game.draw(bag,7);
        val players=mutableListOf<Player>();
        val lines=mutableListOf("DUPLICATE $name seed=$seed players=${job.size-1}");
        for(i in 1 until job.size) {
            val fields=job[i].split(' ');
            players.add(Player(fields[1],fields[2]));
            lines.add("player $i ${fields[1]} strategy=${fields[2]}")
        };
        var rounds=0;
        var masterTotal=0;
        var reason="stuck";
        while(true) {
            val legal=legal(board,rack);
            if(legal.isEmpty())break;
            rounds++;
            val master=legal.first();
            val picks=players.map {
                player->val move=legal.minWith(strategy(player.strategy));
                player.score+=move.score;
                move.score
            };
            masterTotal+=master.score;
            lines.add("round $rounds rack=${collection(rack)} moves=${legal.size} master ${notation(master)} score=${master.score} picks=${picks.joinToString(",")}");
            board=Scoring.apply(board,master.tiles);
            rack=master.leave+Game.draw(bag,7-master.leave.length);
            if(rack.isEmpty()) {
                reason="out";
                break
            }
        };
        lines.add("end reason=$reason rounds=$rounds"+if(reason=="stuck")" rack=${collection(rack)}" else "");
        lines.add("master total=$masterTotal");
        for(player in players) {
            val percent=if(masterTotal>=1)100*player.score/masterTotal else 0;
            lines.add("final ${player.name} total=${player.score} percent=$percent")
        };
        val maximum=players.maxOf {
            it.score
        };
        lines.add("winner "+players.filter {
            it.score==maximum
        }.joinToString(",") {
            it.name
        });
        lines.add(positionSummary(board));
        lines.addAll(Board.display(board));
        add(gameTotals,"rounds",rounds);
        return lines
    }
    fun summary(totals: Map<String,Int>,vararg keys: String)="SUMMARY "+keys.joinToString(" ") {
        "$it=${totals.getOrDefault(it,0)}"
    }
    fun write(name: String,blocks: List<List<String>>) {
        File("output",name).writeText(blocks.joinToString("\n\n") {
            it.joinToString("\n")
        }+"\n")
    }
    fun run() {
        for(line in File("input/tiles.txt").readLines())if(line.isNotEmpty()&&!line.startsWith('#')) {
            val fields=line.split(' ');
            val tile=fields[0][0].code;
            values[tile]=fields[1].toInt();
            counts[tile]=fields[2].toInt();
            weights[tile]=fields[3].toInt()
        };
        var candidates=0;
        var skipped=0;
        var duplicates=0;
        val lengths=IntArray(16);
        for(line in File("input/dictionary.txt").readLines()) {
            if(line.isEmpty()||line.startsWith('#'))continue;
            candidates++;
            if(!line.matches(Regex("[A-Z]{2,15}")))skipped++ else if(trie.add(line))lengths[line.length]++ else duplicates++
        };
        val histogram="lengths"+(2..15).filter {
            lengths[it]>0
        }.joinToString("") {
            " $it=${lengths[it]}"
        };
        val dictionary=listOf("DICTIONARY lines=$candidates words=${trie.words} skipped=$skipped duplicates=$duplicates nodes=${trie.nodes}",
            histogram);
        val jobs=mutableListOf<List<String>>();
        var current: MutableList<String>?=null;
        for(line in File("input/jobs.txt").readLines()) {
            val block=current;
            if(block==null) {
                if(line.isNotEmpty()&&!line.startsWith('#'))current=mutableListOf(line)
            } else if(line=="END") {
                jobs.add(block);
                current=null
            } else block.add(line)
        };
        val moves=mutableListOf(dictionary);
        val validation=mutableListOf<List<String>>();
        val games=mutableListOf<List<String>>();
        val seen=mutableSetOf<String>();
        for(job in jobs) {
            val header=job.first().split(' ');
            val kind=header[0];
            val name=header[1];
            val destination=when(kind) {
                "TOPN"->moves;
                "VALIDATE"->validation;
                else->games
            };
            val totals=when(kind) {
                "TOPN"->topTotals;
                "VALIDATE"->validationTotals;
                else->gameTotals
            };
            add(totals,when(kind) {
                "GAME"->"games";
                "DUPLICATE"->"duplicates";
                else->"jobs"
            },1);
            val error=jobError(job,seen);
            seen.add(name);
            if(error!=null) {
                destination.add(listOf("$kind $name","error $error"));
                add(totals,"errors",1)
            } else destination.add(when(kind) {
                "TOPN"->topn(job);
                "VALIDATE"->validate(job);
                "GAME"->ordinary(job);
                else->duplicate(job)
            })
        };
        moves.add(listOf(summary(topTotals,"jobs","errors","moves","bingos")));
        validation.add(listOf(summary(validationTotals,"jobs","errors","moves","valid","invalid","loss")));
        games.add(listOf(summary(gameTotals,"games","duplicates","errors","turns","rounds","plays","exchanges",
            "passes","bingos")));
        File("output").mkdirs();
        write("moves.txt",moves);
        write("validation.txt",validation);
        write("game.txt",games)
    }
}
fun main()=Scrabble.run()
