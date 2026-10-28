mod board;
mod dictionary_trie;
mod move_generator;
mod scoring;
mod game;
use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use board::Board;
use dictionary_trie::Trie;
use move_generator::Move;
fn text(bytes: &[u8]) -> String {
    String::from_utf8(bytes.to_vec()).unwrap()
}
fn collection(tiles: &[u8]) -> String {
    let mut sorted = tiles.to_vec();
    sorted.sort_unstable();
    if sorted.is_empty() {
        "-".to_owned()
    } else {
        text(&sorted)
    }
}
fn valid_name(name: &str) -> bool {
    !name.is_empty() && name.len() <= 20 && name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_')
}
fn valid_rack(rack: &str) -> bool {
    (1..=7).contains(&rack.len()) && rack.bytes().all(|b| b.is_ascii_uppercase() || b == b'?')
}
fn valid_strategy(strategy: &str) -> bool {
    ["score","tiles","equity"].contains(&strategy)
}
fn notation(movement: &Move) -> String {
    format!("{} {}",board::position(movement.row,movement.column,movement.down),text(&movement.word))
}
fn remaining(rack: &[u8], used: &[u8]) -> Vec<u8> {
    let mut result = rack.to_vec();
    for &tile in used {
        let at = result.iter().position(|&r| r == tile).unwrap();
        result.remove(at);
    }
    result
}
struct Scored {
    movement: Move,
    score: i64,
    tiles: usize,
    leave: Vec<u8>,
    value: i64,
    words: String,
    placement: Vec<(usize,usize,u8)>
}
struct Context {
    values: [i64;27],
    counts: [usize;27],
    weights: [i64;27],
    trie: Trie,
    words: Vec<String>,
    dictionary: Vec<String>
}
impl Context {
    fn read() -> Self {
        let mut values = [0;27];
        let mut counts = [0;27];
        let mut weights = [0;27];
        let mut index = 0;
        for line in fs::read_to_string("input/tiles.txt").unwrap().lines() {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let w: Vec<_> = line.split_whitespace().collect();
            values[index] = w[1].parse().unwrap();
            counts[index] = w[2].parse().unwrap();
            weights[index] = w[3].parse().unwrap();
            index += 1;
        }
        let mut trie = Trie::new();
        let mut words = Vec::new();
        let mut candidates = 0;
        let mut skipped = 0;
        let mut duplicates = 0;
        let mut lengths = BTreeMap::new();
        for line in fs::read_to_string("input/dictionary.txt").unwrap().lines() {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            candidates += 1;
            if !(2..=15).contains(&line.len()) || !line.bytes().all(|b| b.is_ascii_uppercase()) {
                skipped += 1;
            } else if !trie.insert(line.as_bytes()) {
                duplicates += 1;
            } else {
                words.push(line.to_owned());
                *lengths.entry(line.len()).or_insert(0) += 1;
            }
        }
        let dictionary = vec![format!("DICTIONARY lines={} words={} skipped={} duplicates={} nodes={}",candidates,words.len(),skipped,duplicates,trie.nodes.len()),format!("lengths{}",lengths.iter().map(|(k,n)| format!(" {}={}",k,n)).collect::<String>())];
        Self {
            values,
            counts,
            weights,
            trie,
            words,
            dictionary
        }
    }
    fn leave_value(&self, tiles: &[u8]) -> i64 {
        let mut counts = [0i64;27];
        for &tile in tiles {
            counts[game::index(tile)] += 1;
        }
        let mut value = 0;
        let mut vowels: i64 = 0;
        let mut consonants: i64 = 0;
        let mut duplicates = 0;
        for i in 0..27 {
            value += counts[i]*self.weights[i];
            if i < 26 {
                if counts[i] > 0 {
                    duplicates += counts[i]-1;
                }
                if b"AEIOU".contains(&(b'A'+i as u8)) {
                    vowels += counts[i];
                } else {
                    consonants += counts[i];
                }
            }
        }
        value-4*duplicates-3*((vowels-consonants).abs()-1).max(0)
    }
    fn best_leave(&self, rack: &[u8]) -> Vec<u8> {
        let mut seen = BTreeSet::new();
        let mut best = Vec::new();
        let mut best_value = self.leave_value(&best);
        for mask in 0..(1usize<<rack.len())-1 {
            let mut leave: Vec<_> = rack.iter().enumerate().filter(|(i,_)| mask&(1usize<<*i) != 0).map(|(_,&t)| t).collect();
            leave.sort_unstable();
            if !seen.insert(leave.clone()) {
                continue;
            }
            let value = self.leave_value(&leave);
            if value > best_value || (value == best_value && (leave.len() > best.len() || (leave.len() == best.len() && leave < best))) {
                best_value = value;
                best = leave;
            }
        }
        best
    }
    fn count_error(&self, board: &Board, rack: &[u8]) -> Option<String> {
        let mut used = [0usize;27];
        for (_,_,tile) in board::tiles(board) {
            used[game::index(tile)] += 1;
        }
        for &tile in rack {
            used[game::index(tile)] += 1;
        }
        (0..27).find(|&i| used[i] > self.counts[i]).map(|i| format!("too many {}",if i == 26 {
            '?'
        } else {
            (b'A'+i as u8) as char
        }))
    }
    fn unseen(&self, board: &Board, rack: &[u8]) -> Vec<u8> {
        let mut counts = self.counts;
        for (_,_,tile) in board::tiles(board) {
            counts[game::index(tile)] -= 1;
        }
        for &tile in rack {
            counts[game::index(tile)] -= 1;
        }
        let mut result = Vec::new();
        for (i,&count) in counts.iter().enumerate() {
            result.extend(std::iter::repeat(if i == 26 {
                b'?'
            } else {
                b'A'+i as u8
            }).take(count));
        }
        result
    }
    fn check_board(&self, lines: &[String], rack: &[u8]) -> Result<Board,String> {
        if lines.len() != 15 {
            return Err(format!("board rows {}",lines.len()));
        }
        let mut board = board::empty();
        for (i,line) in lines.iter().enumerate() {
            if line.len() != 15 || !line.bytes().all(|b| b == b'.' || b.is_ascii_alphabetic()) {
                return Err(format!("bad board row {}",i+1));
            }
            board[i].copy_from_slice(line.as_bytes());
        }
        if let Some(reason) = self.count_error(&board,rack) {
            return Err(reason);
        }
        if !board::tiles(&board).is_empty() && board[7][7] == b'.' {
            return Err("center empty".to_owned());
        }
        if !board::connected(&board) {
            return Err("disconnected".to_owned());
        }
        for word in board::words(&board) {
            if !self.trie.contains(&word.text) {
                return Err(format!("unknown word {} at {}",text(&word.text),board::position(word.row,word.column,word.down)));
            }
        }
        Ok(board)
    }
    fn scored(&self, board: &Board, rack: &[u8], movement: Move) -> Scored {
        let placement = scoring::placement(board,&movement);
        let used: Vec<_> = placement.iter().map(|&(_,_,tile)| if tile.is_ascii_lowercase() {
            b'?'
        } else {
            tile
        }).collect();
        let leave = remaining(rack,&used);
        let value = self.leave_value(&leave);
        let (score,tiles,words) = scoring::score(board,&movement,&self.values);
        Scored {
            movement,
            score,
            tiles,
            leave,
            value,
            words,
            placement
        }
    }
    fn moves(&self, board: &Board, rack: &[u8]) -> Vec<Scored> {
        let mut moves: Vec<_> = move_generator::generate(board,rack,&self.trie).into_iter().map(|m| self.scored(board,rack,m)).collect();
        moves.sort_by(|a,b| b.score.cmp(&a.score).then(a.movement.row.cmp(&b.movement.row)).then(a.movement.column.cmp(&b.movement.column)).then(a.movement.down.cmp(&b.movement.down)).then(a.movement.word.cmp(&b.movement.word)));
        moves
    }
    fn order(&self, moves: &[Scored], strategy: &str) -> Vec<usize> {
        let mut order: Vec<_> = (0..moves.len()).collect();
        if strategy == "tiles" {
            order.sort_by_key(|&i| std::cmp::Reverse(moves[i].tiles));
        } else if strategy == "equity" {
            order.sort_by_key(|&i| std::cmp::Reverse(moves[i].score+moves[i].value));
        }
        order
    }
    fn position_summary(&self, board: &Board) -> Vec<String> {
        let tiles = board::tiles(board);
        let words = board::words(board);
        let mut longest: Option<&board::Word> = None;
        for word in &words {
            if longest.map_or(true,|w| word.text.len() > w.text.len()) {
                longest = Some(word);
            }
        }
        let mut premiums = [0;4];
        for &(r,c,_) in &tiles {
            if let Some(i) = b"#*^+".iter().position(|&p| p == board::PREMIUM[r].as_bytes()[c]) {
                premiums[i] += 1;
            }
        }
        let mut lines = vec![format!("position tiles={} words={} longest={} blanks={} premiums=TW:{},DW:{},TL:{},DL:{}",tiles.len(),words.len(),longest.map_or_else(|| "-".to_owned(),|w| text(&w.text)),tiles.iter().filter(|t| t.2.is_ascii_lowercase()).count(),premiums[0],premiums[1],premiums[2],premiums[3])];
        lines.extend(board::display(board));
        lines
    }
    fn topn(&self, name: &str, count: usize, strategy: &str, rack: &[u8], board: &Board) -> (Vec<String>,usize,usize) {
        let moves = self.moves(board,rack);
        let order = self.order(&moves,strategy);
        let shown: Vec<_> = order.iter().take(count).copied().collect();
        let unseen = self.unseen(board,rack);
        let anchors = move_generator::anchors(board);
        let (_,across) = move_generator::checks(board,&self.trie);
        let (_,down) = move_generator::checks(&board::transpose(board),&self.trie);
        let vowels = rack.iter().filter(|t| b"AEIOU".contains(t)).count();
        let blanks = rack.iter().filter(|&&t| t == b'?').count();
        let bingos = moves.iter().filter(|m| m.tiles == 7).count();
        let keep = self.best_leave(rack);
        let mut lines = vec![format!("TOPN {} n={} order={} rack={}",name,count,strategy,collection(rack)),format!("board tiles={} anchors={}",board::tiles(board).len(),anchors.iter().flatten().filter(|&&a| a).count()),format!("unseen count={} tiles={}",unseen.len(),collection(&unseen)),format!("rack vowels={} consonants={} blanks={} value={}",vowels,rack.len()-vowels-blanks,blanks,game::value(rack,&self.values)),format!("checks across={},{},{} down={},{},{}",across[0],across[1],across[2],down[0],down[1],down[2]),format!("moves total={} across={} down={} bingos={} blanks={}",moves.len(),moves.iter().filter(|m| !m.movement.down).count(),moves.iter().filter(|m| m.movement.down).count(),bingos,moves.iter().filter(|m| m.placement.iter().any(|t| t.2.is_ascii_lowercase())).count())];
        lines.push(format!("best_by_tiles {}",(1..=7).map(|n| format!("{}={}",n,moves.iter().filter(|m| m.tiles == n).map(|m| m.score).max().map_or_else(|| "-".to_owned(),|s| s.to_string()))).collect::<Vec<_>>().join(" ")));
        lines.push(format!("exchange keep={} value={}",collection(&keep),self.leave_value(&keep)));
        let mut anagrams = self.trie.anagrams(rack);
        anagrams.sort_by(|a,b| b.len().cmp(&a.len()).then(a.cmp(b)));
        lines.push(format!("anagrams total={} top={}",anagrams.len(),if anagrams.is_empty() {
            "-".to_owned()
        } else {
            anagrams.iter().take(10).cloned().collect::<Vec<_>>().join(",")
        }));
        for word in board::words(board) {
            if word.text.len() < 3 {
                continue;
            }
            let uppercase: Vec<_> = word.text.iter().map(u8::to_ascii_uppercase).collect();
            let mut front = Vec::new();
            let mut back = Vec::new();
            for letter in b'A'..=b'Z' {
                let mut candidate = vec![letter];
                candidate.extend(&uppercase);
                if self.trie.contains(&candidate) {
                    front.push(letter);
                }
                let mut candidate = uppercase.clone();
                candidate.push(letter);
                if self.trie.contains(&candidate) {
                    back.push(letter);
                }
            }
            if !front.is_empty() || !back.is_empty() {
                lines.push(format!("hook {} {} front={} back={}",board::position(word.row,word.column,word.down),text(&word.text),if front.is_empty() {
                    "-".to_owned()
                } else {
                    text(&front)
                },if back.is_empty() {
                    "-".to_owned()
                } else {
                    text(&back)
                }));
            }
        }
        let mut nets = Vec::new();
        if (1..=7).contains(&unseen.len()) && !shown.is_empty() {
            for &i in &shown {
                let after = scoring::apply(board,&moves[i].movement);
                let replies = self.moves(&after,&unseen);
                nets.push(moves[i].score-replies.first().map_or(0,|m| m.score));
            }
            let mut best = 0;
            for i in 1..nets.len() {
                if nets[i] > nets[best] {
                    best = i;
                }
            }
            lines.push(format!("endgame opponent={} best={} net={}",collection(&unseen),best+1,nets[best]));
        }
        for (k,&i) in shown.iter().enumerate() {
            let m = &moves[i];
            lines.push(format!("{} {} score={} tiles={} leave={} value={}{} words={}",k+1,notation(&m.movement),m.score,m.tiles,collection(&m.leave),m.value,if nets.is_empty() {
                String::new()
            } else {
                format!(" net={}",nets[k])
            },m.words));
        }
        (lines,moves.len(),bingos)
    }
    fn check_move(&self, board: &Board, rack: &[u8], position: &str, word: &str) -> Result<Move,String> {
        let (row,column,down) = board::parse_position(position).ok_or_else(|| "bad position".to_owned())?;
        if !(2..=15).contains(&word.len()) || !word.bytes().all(|b| b.is_ascii_alphabetic()) {
            return Err("bad word".to_owned());
        }
        let movement = Move {
            row,
            column,
            down,
            word: word.as_bytes().to_vec()
        };
        if row+if down {
            word.len()
        } else {
            1
        }
        > 15 || column+if down {
            1
        } else {
            word.len()
        }
        > 15 {
            return Err("off board".to_owned());
        }
        let squares = scoring::squares(&movement);
        for &(r,c,tile) in &squares {
            if board[r][c] != b'.' && board[r][c] != tile {
                return Err(format!("mismatch at {}",board::square(r,c)));
            }
        }
        let before = if down {
            row > 0 && board[row-1][column] != b'.'
        } else {
            column > 0 && board[row][column-1] != b'.'
        };
        let (last_r,last_c,_) = *squares.last().unwrap();
        let after = if down {
            last_r+1 < 15 && board[last_r+1][last_c] != b'.'
        } else {
            last_c+1 < 15 && board[last_r][last_c+1] != b'.'
        };
        if before || after {
            return Err("not whole word".to_owned());
        }
        let new: Vec<_> = squares.iter().copied().filter(|&(r,c,_)| board[r][c] == b'.').collect();
        if new.is_empty() {
            return Err("no new tiles".to_owned());
        }
        let mut remaining = rack.to_vec();
        for &(_,_,tile) in &new {
            let used = if tile.is_ascii_lowercase() {
                b'?'
            } else {
                tile
            };
            if let Some(i) = remaining.iter().position(|&t| t == used) {
                remaining.remove(i);
            } else {
                return Err(format!("rack lacks {}",used as char));
            }
        }
        if board::tiles(board).is_empty() {
            if !new.iter().any(|&(r,c,_)| (r,c) == board::CENTER) {
                return Err("center not covered".to_owned());
            }
        } else if !new.iter().any(|&(r,c,_)| board::neighbors(r,c).iter().any(|&(a,b)| board[a][b] != b'.')) {
            return Err("not connected".to_owned());
        }
        for word in scoring::words(board,&movement) {
            if !self.trie.contains(&word.text) {
                return Err(format!("unknown word {} at {}",text(&word.text),board::position(word.row,word.column,word.down)));
            }
        }
        Ok(movement)
    }
    fn validate(&self, name: &str, mut board: Board, records: &[String]) -> (Vec<String>,[i64;6]) {
        let mut lines = vec![format!("VALIDATE {}",name)];
        let mut players = Vec::<(String,[i64;4])>::new();
        let mut totals = [0i64;6];
        totals[0] = records.len() as i64;
        for (k,line) in records.iter().enumerate() {
            let w: Vec<_> = line.split_whitespace().collect();
            let player = w[1];
            let rack = w[2];
            let mut reason = None;
            let mut movement = None;
            let mut player_index = None;
            if !valid_name(player) {
                reason = Some("bad player".to_owned());
            } else {
                let index = if let Some(i) = players.iter().position(|p| p.0 == player) {
                    i
                } else {
                    players.push((player.to_owned(),[0;4]));
                    players.len()-1
                };
                players[index].1[0] += 1;
                player_index = Some(index);
            }
            if reason.is_none() {
                if !valid_rack(rack) {
                    reason = Some("bad rack".to_owned());
                } else {
                    reason = self.count_error(&board,rack.as_bytes());
                }
            }
            if reason.is_none() && w.len() == 5 && w[3] == "EXCHANGE" {
                if !valid_rack(w[4]) {
                    reason = Some("bad exchange".to_owned());
                } else {
                    for tile in w[4].bytes() {
                        let needed = w[4].bytes().filter(|&t| t == tile).count();
                        let available = rack.bytes().filter(|&t| t == tile).count();
                        if needed > available {
                            reason = Some(format!("rack lacks {}",tile as char));
                            break;
                        }
                    }
                }
            } else if reason.is_none() && w.len() == 5 {
                match self.check_move(&board,rack.as_bytes(),w[3],w[4]) {
                    Ok(m) => movement = Some(m),Err(error) => reason = Some(error)
                }
            }
            let mut output = format!("move {} {} {}",k+1,player,w[3..].join(" "));
            if let Some(reason) = reason {
                output.push_str(&format!(" invalid {}",reason));
                totals[2] += 1;
            } else {
                let moves = self.moves(&board,rack.as_bytes());
                let best = moves.first().map_or(0,|m| m.score);
                let mut score = 0;
                let index = player_index.unwrap();
                if let Some(movement) = movement {
                    let scored = self.scored(&board,rack.as_bytes(),movement);
                    let rank = moves.iter().position(|m| m.placement == scored.placement).unwrap()+1;
                    score = scored.score;
                    players[index].1[2] += score;
                    output.push_str(&format!(" score={} total={} tiles={} rank={}/{} best={} words={}",score,players[index].1[2],scored.tiles,rank,moves.len(),best,scored.words));
                    board = scoring::apply(&board,&scored.movement);
                } else {
                    output.push_str(&format!(" score=0 total={} moves={} best={}",players[index].1[2],moves.len(),best));
                }
                players[index].1[1] += 1;
                players[index].1[3] += best-score;
                totals[1] += 1;
                totals[3] += score;
                totals[4] += best;
                totals[5] += best-score;
            }
            lines.push(output);
        }
        for (name,p) in players {
            lines.push(format!("player {} moves={} valid={} score={} loss={}",name,p[0],p[1],p[2],p[3]));
        }
        lines.push(format!("total valid={} invalid={} score={} best={} loss={}",totals[1],totals[2],totals[3],totals[4],totals[5]));
        lines.extend(self.position_summary(&board));
        (lines,totals)
    }
    fn play_game(&self, name: &str, seed: i64, definitions: &[Vec<String>], duplicate: bool) -> (Vec<String>,[usize;7]) {
        let n = definitions.len();
        let mut generator = game::Generator {
            state: seed
        };
        let mut bag = game::bag(&self.counts,&mut generator);
        let mut board = board::empty();
        let mut lines = vec![format!("{} {} seed={} players={}",if duplicate {
            "DUPLICATE"
        } else {
            "GAME"
        },name,seed,n)];
        let mut summary = [0usize;7];
        for (i,w) in definitions.iter().enumerate() {
            lines.push(format!("player {} {} strategy={}{}",i+1,w[1],w[2],if duplicate {
                String::new()
            } else {
                format!(" threshold={}",w[3])
            }));
        }
        if duplicate {
            let mut rack = game::draw(&mut bag,7);
            let mut scores = vec![0i64;n];
            let mut master = 0;
            let mut rounds = 0;
            let reason;
            loop {
                let moves = self.moves(&board,&rack);
                if moves.is_empty() {
                    reason = "stuck";
                    break;
                }
                rounds += 1;
                let mut picks = Vec::new();
                for (i,w) in definitions.iter().enumerate() {
                    let chosen = self.order(&moves,&w[2])[0];
                    scores[i] += moves[chosen].score;
                    picks.push(moves[chosen].score.to_string());
                }
                master += moves[0].score;
                lines.push(format!("round {} rack={} moves={} master {} score={} picks={}",rounds,collection(&rack),moves.len(),notation(&moves[0].movement),moves[0].score,picks.join(",")));
                board = scoring::apply(&board,&moves[0].movement);
                rack = moves[0].leave.clone();
                rack.extend(game::draw(&mut bag,7-rack.len()));
                if rack.is_empty() {
                    reason = "out";
                    break;
                }
            }
            lines.push(format!("end reason={} rounds={}{}",reason,rounds,if reason == "stuck" {
                format!(" rack={}",collection(&rack))
            } else {
                String::new()
            }));
            lines.push(format!("master total={}",master));
            for (w,&score) in definitions.iter().zip(&scores) {
                lines.push(format!("final {} total={} percent={}",w[1],score,if master > 0 {
                    100*score/master
                } else {
                    0
                }));
            }
            let best = *scores.iter().max().unwrap();
            lines.push(format!("winner {}",definitions.iter().zip(scores).filter(|(_,score)| *score == best).map(|(w,_)| w[1].as_str()).collect::<Vec<_>>().join(",")));
            summary[1] = rounds;
        } else {
            let mut racks: Vec<_> = (0..n).map(|_| game::draw(&mut bag,7)).collect();
            let mut scores = vec![0i64;n];
            let mut stats = vec![[0i64;6];n];
            let mut turn = 0;
            let mut scoreless = 0;
            let mut out = None;
            let mut highlight: Option<(usize,usize,String,i64)> = None;
            loop {
                let player = turn%n;
                turn += 1;
                let moves = self.moves(&board,&racks[player]);
                let order = self.order(&moves,&definitions[player][2]);
                let candidate = order.first().map(|&i| &moves[i]);
                let threshold = definitions[player][3].parse::<i64>().unwrap();
                let mut line = format!("turn {} {} rack={} moves={}",turn,definitions[player][1],collection(&racks[player]),moves.len());
                if let Some(chosen) = candidate.filter(|m| !(m.score < threshold && bag.len() >= 7)) {
                    scores[player] += chosen.score;
                    stats[player][0] += 1;
                    stats[player][1] += i64::from(chosen.tiles == 7);
                    stats[player][4] = stats[player][4].max(chosen.score);
                    stats[player][5] += moves[0].score-chosen.score;
                    board = scoring::apply(&board,&chosen.movement);
                    racks[player] = chosen.leave.clone();
                    let drawn = game::draw(&mut bag,7-racks[player].len());
                    racks[player].extend(&drawn);
                    scoreless = 0;
                    line.push_str(&format!(" best={} play {} score={} total={} draw={} bag={}",moves[0].score,notation(&chosen.movement),chosen.score,scores[player],collection(&drawn),bag.len()));
                    if highlight.as_ref().map_or(true,|h| chosen.score > h.3) {
                        highlight = Some((turn,player,notation(&chosen.movement),chosen.score));
                    }
                    if racks[player].is_empty() && bag.is_empty() {
                        out = Some(player);
                    }
                } else if bag.len() >= 7 {
                    let keep = self.best_leave(&racks[player]);
                    let returned = remaining(&racks[player],&keep);
                    let drawn = game::exchange(&mut bag,&returned,&mut generator);
                    racks[player] = keep.clone();
                    racks[player].extend(&drawn);
                    stats[player][2] += 1;
                    scoreless += 1;
                    line.push_str(&format!(" exchange keep={} draw={} bag={}",collection(&keep),collection(&drawn),bag.len()));
                } else {
                    stats[player][3] += 1;
                    scoreless += 1;
                    line.push_str(&format!(" pass bag={}",bag.len()));
                }
                lines.push(line);
                if out.is_some() || scoreless == 6 {
                    break;
                }
            }
            if let Some(player) = out {
                lines.push(format!("end reason=out player={} turns={}",definitions[player][1],turn));
            } else {
                lines.push(format!("end reason=scoreless turns={}",turn));
            }
            let mut adjustments: Vec<_> = racks.iter().map(|rack| -game::value(rack,&self.values)).collect();
            if let Some(player) = out {
                adjustments[player] = -adjustments.iter().enumerate().filter(|(i,_)| *i != player).map(|(_,v)| *v).sum::<i64>();
            }
            let totals: Vec<_> = scores.iter().zip(&adjustments).map(|(s,a)| s+a).collect();
            for i in 0..n {
                lines.push(format!("final {} score={} rack={} adjust={} total={}",definitions[i][1],scores[i],collection(&racks[i]),if adjustments[i] > 0 {
                    format!("+{}",adjustments[i])
                } else {
                    adjustments[i].to_string()
                },totals[i]));
            }
            let mut standings: Vec<_> = (0..n).collect();
            standings.sort_by(|&a,&b| totals[b].cmp(&totals[a]).then(a.cmp(&b)));
            for (rank,&i) in standings.iter().enumerate() {
                let s = stats[i];
                lines.push(format!("standing {} {} total={} plays={} bingos={} exchanges={} passes={} top={} loss={}",rank+1,definitions[i][1],totals[i],s[0],s[1],s[2],s[3],s[4],s[5]));
            }
            let best = *totals.iter().max().unwrap();
            lines.push(format!("winner {}",definitions.iter().zip(&totals).filter(|(_,score)| **score == best).map(|(w,_)| w[1].as_str()).collect::<Vec<_>>().join(",")));
            if let Some((turn,player,movement,score)) = highlight {
                lines.push(format!("highlight turn={} player={} play {} score={}",turn,definitions[player][1],movement,score));
            }
            summary[0] = turn;
            summary[2] = stats.iter().map(|s| s[0] as usize).sum();
            summary[3] = stats.iter().map(|s| s[2] as usize).sum();
            summary[4] = stats.iter().map(|s| s[3] as usize).sum();
            summary[5] = stats.iter().map(|s| s[1] as usize).sum();
        }
        lines.extend(self.position_summary(&board));
        (lines,summary)
    }
}
fn main() {
    let context = Context::read();
    let mut blocks = Vec::<Vec<String>>::new();
    let mut current = Vec::new();
    for line in fs::read_to_string("input/jobs.txt").unwrap().lines() {
        if current.is_empty() && (line.is_empty() || line.starts_with('#')) {
            continue;
        }
        if line == "END" {
            blocks.push(std::mem::take(&mut current));
        } else {
            current.push(line.to_owned());
        }
    }
    let mut moves = vec![context.dictionary.clone()];
    let mut validation = Vec::new();
    let mut games = Vec::new();
    let mut names = BTreeSet::new();
    let mut top_totals = [0usize;4];
    let mut validation_totals = [0i64;6];
    let mut game_totals = [0usize;9];
    for block in blocks {
        let header: Vec<_> = block[0].split_whitespace().collect();
        let kind = header[0];
        let name = header[1];
        let mut reason = if !valid_name(name) {
            Some("bad name".to_owned())
        } else if names.contains(name) {
            Some("duplicate name".to_owned())
        } else {
            None
        };
        names.insert(name.to_owned());
        let mut board = board::empty();
        let mut records = Vec::new();
        let mut rack = String::new();
        let mut players = Vec::new();
        let mut count = 0;
        let mut seed = 0;
        if kind == "TOPN" || kind == "VALIDATE" {
            if kind == "TOPN" {
                rack = block[1].split_whitespace().nth(1).unwrap().to_owned();
                if reason.is_none() {
                    if let Some(n) = board::number(header[2],1,99) {
                        count = n as usize;
                    } else {
                        reason = Some("bad count".to_owned());
                    }
                }
                if reason.is_none() && !valid_strategy(header[3]) {
                    reason = Some("bad order".to_owned());
                }
                if reason.is_none() && !valid_rack(&rack) {
                    reason = Some("bad rack".to_owned());
                }
            }
            let first = if kind == "TOPN" {
                3
            } else {
                2
            };
            let end = (first..block.len()).find(|&i| block[i].starts_with("MOVE")).unwrap_or(block.len());
            records = block[end..].to_vec();
            if reason.is_none() {
                match context.check_board(&block[first..end],rack.as_bytes()) {
                    Ok(value) => board = value,Err(error) => reason = Some(error)
                }
            }
        } else {
            players = block[1..].iter().map(|line| line.split_whitespace().map(str::to_owned).collect::<Vec<_>>()).collect::<Vec<_>>();
            if reason.is_none() {
                if let Some(value) = board::number(header[2],1,2147483646) {
                    seed = value;
                } else {
                    reason = Some("bad seed".to_owned());
                }
            }
            if reason.is_none() && !(2..=4).contains(&players.len()) {
                reason = Some(format!("bad player count {}",players.len()));
            }
            let mut player_names = BTreeSet::new();
            if reason.is_none() {
                for (i,w) in players.iter().enumerate() {
                    if !valid_name(&w[1]) || !valid_strategy(&w[2]) || (kind == "GAME" && board::number(&w[3],0,99).is_none()) {
                        reason = Some(format!("bad player {}",i+1));
                        break;
                    }
                    if !player_names.insert(w[1].clone()) {
                        reason = Some(format!("duplicate player {}",i+1));
                        break;
                    }
                }
            }
        }
        let error = reason.map(|reason| vec![format!("{} {}",kind,name),format!("error {}",reason)]);
        match kind {
            "TOPN" => {
                top_totals[0] += 1;
                if let Some(error) = error {
                    top_totals[1] += 1;
                    moves.push(error);
                } else {
                    let (lines,total,bingos) = context.topn(name,count,header[3],rack.as_bytes(),&board);
                    top_totals[2] += total;
                    top_totals[3] += bingos;
                    moves.push(lines);
                }
            }
            "VALIDATE" => {
                validation_totals[0] += 1;
                if let Some(error) = error {
                    validation_totals[1] += 1;
                    validation.push(error);
                } else {
                    let (lines,totals) = context.validate(name,board,&records);
                    validation_totals[2] += totals[0];
                    validation_totals[3] += totals[1];
                    validation_totals[4] += totals[2];
                    validation_totals[5] += totals[5];
                    validation.push(lines);
                }
            }
            _ => {
                game_totals[usize::from(kind == "DUPLICATE")] += 1;
                if let Some(error) = error {
                    game_totals[2] += 1;
                    games.push(error);
                } else {
                    let (lines,totals) = context.play_game(name,seed,&players,kind == "DUPLICATE");
                    game_totals[3] += totals[0];
                    game_totals[4] += totals[1];
                    game_totals[5] += totals[2];
                    game_totals[6] += totals[3];
                    game_totals[7] += totals[4];
                    game_totals[8] += totals[5];
                    games.push(lines);
                }
            }
        }
    }
    moves.push(vec![format!("SUMMARY jobs={} errors={} moves={} bingos={}",top_totals[0],top_totals[1],top_totals[2],top_totals[3])]);
    validation.push(vec![format!("SUMMARY jobs={} errors={} moves={} valid={} invalid={} loss={}",validation_totals[0],validation_totals[1],validation_totals[2],validation_totals[3],validation_totals[4],validation_totals[5])]);
    games.push(vec![format!("SUMMARY games={} duplicates={} errors={} turns={} rounds={} plays={} exchanges={} passes={} bingos={}",game_totals[0],game_totals[1],game_totals[2],game_totals[3],game_totals[4],game_totals[5],game_totals[6],game_totals[7],game_totals[8])]);
    fs::create_dir_all("output").unwrap();
    for (name,paragraphs) in [("moves.txt",moves),("validation.txt",validation),("game.txt",games)] {
        fs::write(format!("output/{}",name),paragraphs.iter().map(|p| p.join("\n")).collect::<Vec<_>>().join("\n\n")+"\n").unwrap();
    }
}
