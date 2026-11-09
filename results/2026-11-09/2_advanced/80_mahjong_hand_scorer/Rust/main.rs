mod tiles;
mod decomposition;
mod yaku;
mod scoring;
mod shanten;
use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use tiles::Tile;
use decomposition::Set;
struct Row {
    label: String,
    fields: BTreeMap<String,String>
}
fn rows(name: &str) -> Vec<Row> {
    fs::read_to_string(format!("input/{}.txt",name)).unwrap().lines().map(|line| {
        let w: Vec<_> = line.split_whitespace().collect();
        Row {
            label: w[0].to_owned(),
            fields: w[1..].iter().map(|word| {
                let (key,value) = word.split_once('=').unwrap();
                (key.to_owned(),value.to_owned())
            }).collect()
        }
    }).collect()
}
struct Rule {
    name: String,
    open: bool,
    red: bool,
    double: bool,
    kazoe: bool,
    kiriage: bool,
    honba: i64
}
fn rules() -> Vec<Rule> {
    rows("rules").iter().map(|row| Rule {
        name: row.label.clone(),
        open: row.fields["open_tanyao"] == "yes",
        red: row.fields["red_fives"] == "yes",
        double: row.fields["double_yakuman"] == "yes",
        kazoe: row.fields["kazoe_yakuman"] == "yes",
        kiriage: row.fields["kiriage"] == "yes",
        honba: row.fields["honba"].parse().unwrap()
    }).collect()
}
fn wind(source: &str) -> usize {
    b"ESWN".iter().position(|&w| w == source.as_bytes()[0]).unwrap()
}
#[derive(Clone)] struct Meld {
    kind: u8,
    tiles: Vec<Tile>
}
#[derive(Clone)] struct Situation {
    hand: Vec<Tile>,
    melds: Vec<Meld>,
    win: Tile,
    ron: bool,
    seat: usize,
    from: Option<usize>,
    round: usize,
    flags: BTreeSet<String>,
    dora: Vec<Tile>,
    ura: Vec<Tile>,
    discards: Vec<Tile>,
    honba: i64,
    sticks: i64
}
impl Situation {
    fn closed(&self) -> bool {
        self.melds.iter().all(|m| m.kind == b'A')
    }
    fn all(&self) -> Vec<Tile> {
        self.hand.iter().copied().chain(std::iter::once(self.win)).chain(self.melds.iter().flat_map(|m| m.tiles.iter().copied())).collect()
    }
    fn concealed(&self) -> [u8;34] {
        let mut counts = tiles::counts(&self.hand);
        counts[self.win.kind] += 1;
        counts
    }
}
fn parse(source: &str, empty: bool) -> Result<Vec<Tile>,String> {
    tiles::parse(source,empty).ok_or_else(|| "bad tile notation".to_owned())
}
fn copy_error(all: &[Tile], rule: &Rule) -> Option<String> {
    if !rule.red && all.iter().any(|t| t.red) {
        return Some("red five not allowed".to_owned());
    }
    let mut counts = [0usize;34];
    let mut reds = [0usize;3];
    for tile in all {
        counts[tile.kind] += 1;
        if tile.red {
            reds[tile.kind/9] += 1;
        }
    }
    if let Some(kind) = counts.iter().position(|&n| n >= 5) {
        return Some(format!("too many copies of {}",tiles::name(kind)));
    }
    reds.iter().position(|&n| n >= 2).map(|suit| format!("too many copies of 0{}",b"mps"[suit] as char))
}
fn check(row: &Row, rule: &Rule) -> Result<Situation,String> {
    let f = &row.fields;
    let hand = parse(&f["hand"],false)?;
    let win = parse(&f["win"],false)?;
    let dora = parse(&f["dora"],false)?;
    let ura = parse(&f["ura"],true)?;
    let discards = parse(&f["discards"],true)?;
    let mut melds = Vec::new();
    if f["melds"] != "-" {
        for raw in f["melds"].split(',') {
            melds.push(Meld {
                kind: raw.as_bytes()[0],
                tiles: parse(&raw[1..],false)?
            });
        }
    }
    if win.len() != 1 {
        return Err("bad tile notation".to_owned());
    }
    if melds.len() >= 5 || melds.iter().any(|meld| {
        let mut kinds: Vec<_> = meld.tiles.iter().map(|t| t.kind).collect();
        kinds.sort_unstable();
        match meld.kind {
            b'C' => kinds.len() != 3 || kinds[0] >= 27 || kinds[0]%9 > 6 || kinds != [kinds[0],kinds[0]+1,kinds[0]+2],b'P' => kinds.len() != 3 || kinds.iter().any(|&k| k != kinds[0]),b'K' | b'A' => kinds.len() != 4 || kinds.iter().any(|&k| k != kinds[0]),_ => true
        }
    }) {
        return Err("bad meld".to_owned());
    }
    if hand.len() != 13-3*melds.len() {
        return Err("wrong tile count".to_owned());
    }
    let all: Vec<_> = hand.iter().chain(&win).chain(melds.iter().flat_map(|m| m.tiles.iter())).chain(&dora).chain(&ura).chain(&discards).copied().collect();
    if let Some(error) = copy_error(&all,rule) {
        return Err(error);
    }
    let ron = f["by"] == "ron";
    let seat = wind(&f["seat"]);
    let from = if f["from"] == "-" {
        None
    } else {
        Some(wind(&f["from"]))
    };
    if (!ron && from.is_some()) || (ron && (from.is_none() || from == Some(seat))) {
        return Err("invalid discarder".to_owned());
    }
    let flags: BTreeSet<_> = if f["flags"] == "-" {
        BTreeSet::new()
    } else {
        f["flags"].split(',').map(str::to_owned).collect()
    };
    let has = |name: &str| flags.contains(name);
    let closed = melds.iter().all(|m| m.kind == b'A');
    let riichi = has("riichi") || has("double_riichi");
    let kans = melds.iter().filter(|m| m.kind == b'K' || m.kind == b'A').count();
    for flag in yaku::FLAGS {
        if !has(flag) {
            continue;
        }
        let valid = match flag {
            "riichi" => closed,"double_riichi" => closed && !has("riichi"),"ippatsu" => riichi && !has("rinshan"),"haitei" => !ron && !has("rinshan"),"houtei" => ron && !has("chankan"),"rinshan" => !ron && kans > 0,"chankan" => ron,"tenhou" => seat == 0 && !ron && melds.is_empty() && flags.len() == 1,_ => seat != 0 && !ron && melds.is_empty() && flags.len() == 1
        };
        if !valid {
            return Err(format!("invalid flag {}",flag));
        }
    }
    if dora.len() != 1+kans {
        return Err("invalid dora indicators".to_owned());
    }
    if (riichi && ura.len() != dora.len()) || (!riichi && !ura.is_empty()) {
        return Err("invalid ura indicators".to_owned());
    }
    let sticks: i64 = f["sticks"].parse().unwrap();
    if riichi && sticks == 0 {
        return Err("invalid sticks".to_owned());
    }
    let situation = Situation {
        hand,
        melds,
        win: win[0],
        ron,
        seat,
        from,
        round: wind(&f["round"]),
        flags,
        dora,
        ura,
        discards,
        honba: f["honba"].parse().unwrap(),
        sticks
    };
    if !decomposition::winning(&situation.concealed(),situation.melds.len()) {
        return Err("not a winning hand".to_owned());
    }
    Ok(situation)
}
struct Form {
    kind: usize,
    pair: usize,
    sets: Vec<Set>,
    winning: usize,
    notation: String,
    wait: &'static str
}
fn forms(s: &Situation) -> Vec<Form> {
    let counts = s.concealed();
    let mut forms = Vec::new();
    for decomposition in decomposition::standard(&counts,s.melds.len()) {
        let mut winning = Vec::new();
        if decomposition.pair == s.win.kind {
            winning.push(0);
        }
        let mut seen = BTreeSet::new();
        for (i,set) in decomposition.sets.iter().enumerate() {
            if set.kinds().contains(&s.win.kind) && seen.insert(*set) {
                winning.push(i+1);
            }
        }
        for winning in winning {
            let mut parts = vec!["standard".to_owned(),format!("{}{}",tiles::block(&[decomposition.pair;2]),if winning == 0 {
                "*"
            } else {
                ""
            })];
            for (i,set) in decomposition.sets.iter().enumerate() {
                parts.push(format!("{}{}",tiles::block(&set.kinds()),if winning == i+1 {
                    "*"
                } else {
                    ""
                }));
            }
            for meld in &s.melds {
                parts.push(format!("{}{}",meld.kind as char,tiles::block(&meld.tiles.iter().map(|t| t.kind).collect::<Vec<_>>())));
            }
            let wait = decomposition::shape(if winning == 0 {
                None
            } else {
                Some(decomposition.sets[winning-1])
            },s.win.kind);
            forms.push(Form {
                kind: 0,
                pair: decomposition.pair,
                sets: decomposition.sets.clone(),
                winning,
                notation: parts.join(" "),
                wait
            });
        }
    }
    if decomposition::chiitoitsu(&counts,s.melds.len()) {
        let mut parts = vec!["chiitoitsu".to_owned()];
        for k in 0..34 {
            if counts[k] == 2 {
                parts.push(format!("{}{}",tiles::block(&[k,k]),if k == s.win.kind {
                    "*"
                } else {
                    ""
                }));
            }
        }
        forms.push(Form {
            kind: 1,
            pair: 0,
            sets: Vec::new(),
            winning: 0,
            notation: parts.join(" "),
            wait: "tanki"
        });
    }
    if decomposition::kokushi(&counts,s.melds.len()) {
        let mut parts = vec!["kokushi".to_owned()];
        for k in 0..34 {
            if counts[k] > 0 {
                parts.push(format!("{}{}",tiles::block(&vec![k;counts[k] as usize]),if k == s.win.kind {
                    "*"
                } else {
                    ""
                }));
            }
        }
        let hand = tiles::counts(&s.hand);
        let thirteen = (0..34).all(|k| hand[k] == u8::from(tiles::yaochuu(k)));
        forms.push(Form {
            kind: 2,
            pair: 0,
            sets: Vec::new(),
            winning: 0,
            notation: parts.join(" "),
            wait: if thirteen {
                "thirteen"
            } else {
                "single"
            }
        });
    }
    forms.sort_by(|a,b| a.notation.cmp(&b.notation));
    forms
}
struct Candidate {
    form: Form,
    yakus: Vec<(usize,i64)>,
    yakuman: Vec<(usize,i64)>,
    fu: scoring::Fu,
    dora: [i64;3],
    han: i64,
    multiplier: i64,
    category: usize,
    base: i64
}
fn evaluate(form: Form, s: &Situation, rule: &Rule) -> Candidate {
    let all = s.all();
    let counts = tiles::counts(&all);
    let hand_counts = tiles::counts(&s.hand);
    let closed = s.closed();
    let mut holds = [false;30];
    let mut yakuman = [false;15];
    let mut triplets = Vec::new();
    let mut sequences = BTreeSet::new();
    let mut sequence_counts = BTreeMap::<usize,usize>::new();
    let number_suits: BTreeSet<_> = all.iter().filter(|t| t.kind < 27).map(|t| t.kind/9).collect();
    let honors = all.iter().any(|t| t.kind >= 27);
    let pure = number_suits.len() == 1 && !honors;
    for (index,name) in [(0,"riichi"),(1,"double_riichi"),(2,"ippatsu"),(12,"haitei"),(13,"houtei"),(14,"rinshan"),(15,"chankan")].iter().copied() {
        holds[index] = s.flags.contains(name);
    }
    holds[3] = closed && !s.ron;
    holds[5] = all.iter().all(|t| !tiles::yaochuu(t.kind)) && (closed || rule.open);
    holds[25] = all.iter().all(|t| tiles::yaochuu(t.kind));
    holds[26] = number_suits.len() == 1 && honors;
    holds[29] = pure;
    holds[16] = form.kind == 1;
    yakuman[0] = s.flags.contains("tenhou");
    yakuman[1] = s.flags.contains("chiihou");
    yakuman[9] = all.iter().all(|t| t.kind >= 27);
    yakuman[10] = all.iter().all(|t| tiles::terminal(t.kind));
    yakuman[11] = all.iter().all(|t| tiles::green(t.kind));
    if form.kind == 2 {
        yakuman[if form.wait == "thirteen" {
            3
        } else {
            2
        }] = true;
    }
    if s.melds.is_empty() && pure {
        let first = *number_suits.first().unwrap()*9;
        if counts[first] >= 3 && counts[first+8] >= 3 && (first+1..first+8).all(|k| counts[k] >= 1) {
            let exact = (0..9).all(|i| hand_counts[first+i] == if i == 0 || i == 8 {
                3
            } else {
                1
            });
            yakuman[if exact {
                13
            } else {
                12
            }] = true;
        }
    }
    if form.kind == 0 {
        for (i,set) in form.sets.iter().enumerate() {
            if set.sequence {
                sequences.insert(set.start);
                *sequence_counts.entry(set.start).or_insert(0) += 1;
            } else {
                triplets.push(scoring::Block {
                    kind: set.start,
                    notation: tiles::block(&set.kinds()),
                    kan: false,
                    concealed: !s.ron || form.winning != i+1
                });
            }
        }
        for meld in &s.melds {
            let first = meld.tiles.iter().map(|t| t.kind).min().unwrap();
            if meld.kind == b'C' {
                sequences.insert(first);
            } else {
                triplets.push(scoring::Block {
                    kind: first,
                    notation: tiles::block(&meld.tiles.iter().map(|t| t.kind).collect::<Vec<_>>()),
                    kan: meld.kind == b'K' || meld.kind == b'A',
                    concealed: meld.kind == b'A'
                });
            }
        }
        let pair_yakuhai = form.pair >= 31 || form.pair == 27+s.seat || form.pair == 27+s.round;
        holds[4] = closed && s.melds.is_empty() && form.sets.iter().all(|set| set.sequence) && !pair_yakuhai && form.wait == "ryanmen";
        holds[28] = closed && form.sets.len() == 4 && form.sets.iter().all(|set| set.sequence) && sequence_counts.values().all(|n| n%2 == 0);
        holds[6] = closed && !holds[28] && sequence_counts.values().any(|&n| n >= 2);
        let has = |kind: usize| triplets.iter().any(|b| b.kind == kind);
        for i in 0..3 {
            holds[7+i] = has(31+i);
        }
        holds[10] = has(27+s.seat);
        holds[11] = has(27+s.round);
        holds[17] = triplets.len() == 4;
        let concealed = triplets.iter().filter(|b| b.concealed).count();
        holds[18] = concealed == 3;
        holds[19] = (0..7).any(|start| (0..3).all(|suit| sequences.contains(&(9*suit+start))));
        holds[20] = (0..9).any(|number| (0..3).all(|suit| has(9*suit+number)));
        holds[21] = (0..3).any(|suit| [0,3,6].iter().all(|&first| sequences.contains(&(9*suit+first))));
        let outer = !sequences.is_empty() && tiles::yaochuu(form.pair) && triplets.iter().all(|b| tiles::yaochuu(b.kind)) && sequences.iter().all(|&start| start%9 == 0 || start%9 == 6);
        holds[if honors {
            22
        } else {
            27
        }] = outer;
        let kans = triplets.iter().filter(|b| b.kan).count();
        holds[23] = kans == 3;
        let dragons = triplets.iter().filter(|b| b.kind >= 31).count();
        let winds = triplets.iter().filter(|b| (27..31).contains(&b.kind)).count();
        holds[24] = dragons == 2 && form.pair >= 31;
        if concealed == 4 {
            yakuman[if form.wait == "tanki" {
                5
            } else {
                4
            }] = true;
        }
        yakuman[6] = dragons == 3;
        yakuman[7] = winds == 3 && (27..31).contains(&form.pair);
        yakuman[8] = winds == 4;
        yakuman[14] = kans == 4;
    }
    let yakuman = yaku::yakuman(&yakuman,rule.double);
    let multiplier = yakuman.iter().map(|y| y.1).sum();
    if !yakuman.is_empty() {
        return Candidate {
            form,
            yakus: Vec::new(),
            yakuman,
            fu: scoring::Fu {
                items: Vec::new(),
                total: 0,
                rounded: 0
            },
            dora: [0;3],
            han: 0,
            multiplier,
            category: 6,
            base: 8000*multiplier
        };
    }
    let yakus = yaku::ordinary(&holds,closed);
    let count = |indicators: &[Tile]| indicators.iter().map(|t| counts[tiles::next(t.kind)] as i64).sum::<i64>();
    let dora = [count(&s.dora),all.iter().filter(|t| t.red).count() as i64,count(&s.ura)];
    let han = yakus.iter().map(|y| y.1).sum::<i64>()+dora.iter().sum::<i64>();
    let fu = scoring::fu(form.kind == 1,closed,s.ron,holds[4],form.pair,s.seat,s.round,&triplets,form.wait);
    let (category,base) = if yakus.is_empty() {
        (0,0)
    } else {
        scoring::base(han,fu.rounded,rule.kazoe,rule.kiriage)
    };
    Candidate {
        form,
        yakus,
        yakuman,
        fu,
        dora,
        han,
        multiplier: 0,
        category,
        base
    }
}
fn candidates(s: &Situation, rule: &Rule) -> Vec<Candidate> {
    forms(s).into_iter().map(|form| evaluate(form,s,rule)).collect()
}
fn best(candidates: &[Candidate]) -> Option<usize> {
    let mut chosen = None;
    let key = |c: &Candidate| (c.base,!c.yakuman.is_empty(),if c.yakuman.is_empty() {
        c.han
    } else {
        0
    },if c.yakuman.is_empty() {
        c.fu.rounded
    } else {
        0
    });
    for (i,c) in candidates.iter().enumerate() {
        if c.base > 0 && chosen.map_or(true,|j| key(c) > key(&candidates[j])) {
            chosen = Some(i);
        }
    }
    chosen
}
fn names(candidate: &Candidate, delimiter: &str) -> String {
    if candidate.yakuman.is_empty() {
        candidate.yakus.iter().map(|&(i,_)| yaku::NAMES[i]).collect::<Vec<_>>().join(delimiter)
    } else {
        candidate.yakuman.iter().map(|&(i,_)| yaku::YAKUMAN[i]).collect::<Vec<_>>().join(delimiter)
    }
}
fn waiting(s: &Situation) -> Vec<usize> {
    let melds: Vec<_> = s.melds.iter().flat_map(|m| m.tiles.iter().copied()).collect();
    decomposition::waiting(&tiles::counts(&s.hand),&tiles::counts(&melds),s.melds.len())
}
fn signed(value: i64) -> String {
    if value > 0 {
        format!("+{}",value)
    } else {
        value.to_string()
    }
}
fn write(name: &str, lines: &[String]) {
    let content = if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n")+"\n"
    };
    fs::write(format!("output/{}",name),content).unwrap();
}
fn main() {
    let rules = rules();
    let situations = rows("hands");
    let wait_hands = rows("waits");
    let mut scores = Vec::new();
    let mut summary = vec!["hand,han,fu,points,yaku".to_owned()];
    let mut statuses = [0usize;4];
    let mut win_types = [0usize;4];
    let mut waits_count = [0usize;7];
    let mut han_count = BTreeMap::<i64,usize>::new();
    let mut fu_count = BTreeMap::<i64,usize>::new();
    let mut limits = [0usize;7];
    let mut yaku_count = [0usize;45];
    let mut points_total = 0;
    let mut maximum = (0i64,"-".to_owned());
    let mut rule_counts = vec![[0i64;3];rules.len()];
    for row in &situations {
        let rule_index = rules.iter().position(|r| r.name == row.fields["rules"]).unwrap();
        let rule = &rules[rule_index];
        rule_counts[rule_index][0] += 1;
        scores.push(format!("HAND {}",row.label));
        let s = match check(row,rule) {
            Ok(s) => s,Err(error) => {
                statuses[3] += 1;
                scores.push(format!("ERROR {}",error));
                summary.push(format!("{},-,-,0,ERROR",row.label));
                continue;
            }
        };
        let waiting = waiting(&s);
        let candidates = candidates(&s,rule);
        scores.push(format!("WAITS {}",waiting.iter().map(|&k| tiles::name(k)).collect::<Vec<_>>().join(" ")));
        for c in &candidates {
            let evaluation = if !c.yakuman.is_empty() {
                format!("yakuman {} base {} yaku {}",c.multiplier,c.base,names(c,","))
            } else if c.base == 0 {
                "no_yaku".to_owned()
            } else {
                format!("han {} fu {} base {} yaku {}",c.han,c.fu.rounded,c.base,names(c,","))
            };
            scores.push(format!("CANDIDATE {} = {} {}",c.form.notation,c.form.wait,evaluation));
        }
        if s.ron && s.discards.iter().any(|t| waiting.contains(&t.kind)) {
            statuses[1] += 1;
            scores.push("RESULT furiten".to_owned());
            summary.push(format!("{},-,-,0,FURITEN",row.label));
            continue;
        }
        let Some(chosen) = best(&candidates) else {
            statuses[2] += 1;
            scores.push("RESULT no_yaku".to_owned());
            summary.push(format!("{},-,-,0,NO_YAKU",row.label));
            continue;
        };
        let c = &candidates[chosen];
        statuses[0] += 1;
        win_types[2*usize::from(s.seat != 0)+usize::from(!s.ron)] += 1;
        waits_count[yaku::WAITS.iter().position(|&w| w == c.form.wait).unwrap()] += 1;
        limits[c.category] += 1;
        scores.push(format!("FORM {}",c.form.notation));
        scores.push(format!("WAIT {}",c.form.wait));
        if !c.yakuman.is_empty() {
            for &(i,multiplier) in &c.yakuman {
                yaku_count[30+i] += 1;
                scores.push(format!("YAKUMAN {} {}",yaku::YAKUMAN[i],multiplier));
            }
            scores.push(format!("SCORE yakuman {} base {}",c.multiplier,c.base));
        } else {
            *han_count.entry(c.han).or_insert(0) += 1;
            *fu_count.entry(c.fu.rounded).or_insert(0) += 1;
            for &(i,han) in &c.yakus {
                yaku_count[i] += 1;
                scores.push(format!("YAKU {} {}",yaku::NAMES[i],han));
            }
            scores.push(format!("DORA dora {} aka {} ura {}",c.dora[0],c.dora[1],c.dora[2]));
            for (item,value) in &c.fu.items {
                scores.push(format!("FU {} {}",item,value));
            }
            scores.push(format!("FU total {} {}",c.fu.total,c.fu.rounded));
            scores.push(format!("SCORE han {} fu {} limit {} base {}",c.han,c.fu.rounded,yaku::CATEGORIES[c.category],c.base));
        }
        let payment = scoring::payments(c.base,s.seat == 0,s.ron);
        scores.push(if s.ron {
            format!("PAY ron {}",payment.first)
        } else if s.seat == 0 {
            format!("PAY tsumo all {}",payment.first)
        } else {
            format!("PAY tsumo dealer {} nondealer {}",payment.first,payment.second)
        });
        let honba = s.honba*rule.honba;
        let sticks = 1000*s.sticks;
        let gain = payment.total+honba+sticks;
        let mut delta = [0i64;4];
        delta[s.seat] = gain;
        if s.ron {
            delta[s.from.unwrap()] = -(payment.first+honba);
        } else {
            for payer in 0..4 {
                if payer != s.seat {
                    delta[payer] = -(if s.seat == 0 || payer == 0 {
                        payment.first
                    } else {
                        payment.second
                    })-honba/3;
                }
            }
        }
        scores.push(format!("BONUS honba {} sticks {}",honba,sticks));
        scores.push(format!("TOTAL points {} gain {}",payment.total,gain));
        scores.push(format!("DELTA E {} S {} W {} N {}",signed(delta[0]),signed(delta[1]),signed(delta[2]),signed(delta[3])));
        points_total += payment.total;
        if payment.total > maximum.0 {
            maximum = (payment.total,row.label.clone());
        }
        rule_counts[rule_index][1] += 1;
        rule_counts[rule_index][2] += payment.total;
        summary.push(if c.yakuman.is_empty() {
            format!("{},{},{},{},{}",row.label,c.han,c.fu.rounded,payment.total,names(c,";"))
        } else {
            format!("{},Y{},-,{},{}",row.label,c.multiplier,payment.total,names(c,";"))
        });
    }
    scores.push(format!("STATS hands {} wins {} furiten {} no_yaku {} errors {}",situations.len(),statuses[0],statuses[1],statuses[2],statuses[3]));
    scores.push(format!("WINS dealer_ron {} dealer_tsumo {} nondealer_ron {} nondealer_tsumo {}",win_types[0],win_types[1],win_types[2],win_types[3]));
    scores.push(format!("WAIT_COUNT {}",yaku::WAITS.iter().zip(waits_count.iter()).map(|(name,count)| format!("{} {}",name,count)).collect::<Vec<_>>().join(" ")));
    for (han,count) in han_count {
        scores.push(format!("HAN_COUNT {} {}",han,count));
    }
    for (fu,count) in fu_count {
        scores.push(format!("FU_COUNT {} {}",fu,count));
    }
    for i in 0..7 {
        scores.push(format!("LIMIT {} {}",yaku::CATEGORIES[i],limits[i]));
    }
    for i in 0..45 {
        if yaku_count[i] > 0 {
            scores.push(format!("YAKU_COUNT {} {}",if i < 30 {
                yaku::NAMES[i]
            } else {
                yaku::YAKUMAN[i-30]
            },yaku_count[i]));
        }
    }
    scores.push(format!("POINTS total {} max {} hand {}",points_total,maximum.0,maximum.1));
    for (rule,counts) in rules.iter().zip(&rule_counts) {
        scores.push(format!("RULE {} hands {} wins {} points {}",rule.name,counts[0],counts[1],counts[2]));
    }
    let mut wait_lines = Vec::new();
    let mut wait_errors = 0;
    let mut tenpai = 0;
    let mut furiten_count = 0;
    let mut shanten_counts = [0usize;7];
    for row in &wait_hands {
        wait_lines.push(format!("HAND {}",row.label));
        let f = &row.fields;
        let rule = &rules[rules.iter().position(|r| r.name == f["rules"]).unwrap()];
        let parsed = (|| -> Result<(Vec<Tile>,Vec<Tile>,Vec<Tile>,Vec<Tile>),String> {
            let hand = parse(&f["hand"],false)?;
            let dora = parse(&f["dora"],false)?;
            let discards = parse(&f["discards"],true)?;
            let visible = parse(&f["visible"],true)?;
            if hand.len() != 13 {
                return Err("wrong tile count".to_owned());
            }
            let all: Vec<_> = hand.iter().chain(&dora).chain(&discards).chain(&visible).copied().collect();
            if let Some(error) = copy_error(&all,rule) {
                return Err(error);
            }
            Ok((hand,dora,discards,visible))
        })();
        let (hand,dora,discards,visible) = match parsed {
            Ok(values) => values,Err(error) => {
                wait_errors += 1;
                wait_lines.push(format!("ERROR {}",error));
                continue;
            }
        };
        let counts = tiles::counts(&hand);
        let all: Vec<_> = hand.iter().chain(&dora).chain(&discards).chain(&visible).copied().collect();
        let used = tiles::counts(&all);
        let shanten = shanten::calculate(&counts);
        let minimum = *shanten.iter().min().unwrap();
        shanten_counts[minimum as usize] += 1;
        wait_lines.push(format!("SHANTEN standard {} chiitoitsu {} kokushi {}",shanten[0],shanten[1],shanten[2]));
        let mut acceptance = Vec::new();
        for kind in 0..34 {
            if counts[kind] <= 3 {
                let mut trial = counts;
                trial[kind] += 1;
                if *shanten::calculate(&trial).iter().min().unwrap() < minimum {
                    acceptance.push((kind,4-used[kind]));
                }
            }
        }
        let remaining: usize = acceptance.iter().map(|a| a.1 as usize).sum();
        if minimum > 0 {
            let tiles = acceptance.iter().map(|&(k,n)| format!("{}:{}",tiles::name(k),n)).collect::<Vec<_>>().join(" ");
            wait_lines.push(format!("ACCEPT kinds {} tiles {}{}",acceptance.len(),remaining,if tiles.is_empty() {
                String::new()
            } else {
                format!(" {}",tiles)
            }));
            continue;
        }
        tenpai += 1;
        let furiten = discards.iter().any(|t| acceptance.iter().any(|a| a.0 == t.kind));
        furiten_count += usize::from(furiten);
        wait_lines.push(format!("TENPAI kinds {} tiles {} furiten {}",acceptance.len(),remaining,if furiten {
            "yes"
        } else {
            "no"
        }));
        let mut best_waits: [Option<(usize,i64)>;2] = [None,None];
        for (kind,left) in acceptance {
            let mut values = Vec::new();
            for method in 0..2 {
                if method == 0 && furiten {
                    values.push("furiten".to_owned());
                    continue;
                }
                let mut flags = BTreeSet::new();
                if f["riichi"] == "yes" {
                    flags.insert("riichi".to_owned());
                }
                let s = Situation {
                    hand: hand.clone(),
                    melds: Vec::new(),
                    win: Tile {
                        kind,
                        red: false
                    },
                    ron: method == 0,
                    seat: wind(&f["seat"]),
                    from: None,
                    round: wind(&f["round"]),
                    flags,
                    dora: dora.clone(),
                    ura: Vec::new(),
                    discards: Vec::new(),
                    honba: 0,
                    sticks: 0
                };
                let candidates = candidates(&s,rule);
                if let Some(best) = best(&candidates) {
                    let points = scoring::payments(candidates[best].base,s.seat == 0,s.ron).total;
                    values.push(points.to_string());
                    if best_waits[method].map_or(true,|(_,p)| points > p) {
                        best_waits[method] = Some((kind,points));
                    }
                } else {
                    values.push("no_yaku".to_owned());
                }
            }
            wait_lines.push(format!("WAIT {} left {} ron {} tsumo {}",tiles::name(kind),left,values[0],values[1]));
        }
        wait_lines.push(format!("BEST ron {} tsumo {}",best_waits[0].map_or_else(|| "none".to_owned(),|(k,p)| format!("{} {}",tiles::name(k),p)),best_waits[1].map_or_else(|| "none".to_owned(),|(k,p)| format!("{} {}",tiles::name(k),p))));
    }
    wait_lines.push(format!("STATS hands {} errors {} tenpai {} furiten {}",wait_hands.len(),wait_errors,tenpai,furiten_count));
    for (k,count) in shanten_counts.iter().enumerate() {
        wait_lines.push(format!("SHANTEN_COUNT {} {}",k,count));
    }
    fs::create_dir_all("output").unwrap();
    write("scores.txt",&scores);
    write("waits.txt",&wait_lines);
    write("summary.csv",&summary);
}
