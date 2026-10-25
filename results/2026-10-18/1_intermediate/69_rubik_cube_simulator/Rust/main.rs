use std::collections::BTreeMap;
use std::convert::TryInto;
use std::io::{self, Read};
const FACES: &str = "URFDLB";
const COLORS: &[u8] = b"WRGYOB";
const LETTERS: &str = "URFDLBMESudfblrxyz";
const CORNERS: [&str; 8] = ["URF","UFL","ULB","UBR","DFR","DLF","DBL","DRB"];
const EDGES: [&str; 12] = ["UR","UF","UL","UB","DR","DF","DL","DB","FR","FL","BL","BR"];
const CORNER_STICKERS: [[usize; 3]; 8] = [[8,9,20],[6,18,38],[0,36,47],[2,45,11],[29,26,15],[27,44,24],[33,53,42],[35,17,51]];
const EDGE_STICKERS: [[usize; 2]; 12] = [[5,10],[7,19],[3,37],[1,46],[32,16],[28,25],[30,43],[34,52],[23,12],[21,41],[50,39],[48,14]];
#[derive(Clone,Copy,PartialEq,Eq)]
struct Move {
    letter:u8, amount:usize
}
impl Move {
    fn text(self) -> String {
        format!("{}{}",self.letter as char,match self.amount {
            2=>"2",3=>"'",_=>""
        })
    }
    fn inverse(self) -> Self {
        Self {
            amount:4-self.amount,..self
        }
    }
}
type Permutation = [usize; 54];
type State = [u8; 54];
fn identity() -> Permutation {
    std::array::from_fn(|i|i)
}
fn solved_state() -> State {
    std::array::from_fn(|i|COLORS[i/9])
}
fn compose(a: &Permutation,b: &Permutation) -> Permutation {
    std::array::from_fn(|i|b[a[i]])
}
fn inverse_permutation(a: &Permutation) -> Permutation {
    let mut out=identity();
    for i in 0..54 {
        out[a[i]]=i;
    }
    out
}
fn apply(state: &State,p: &Permutation) -> State {
    let mut out=*state;
    for i in 0..54 {
        out[p[i]]=state[i];
    }
    out
}
fn inverse(sequence: &[Move]) -> Vec<Move> {
    sequence.iter().rev().map(|m|m.inverse()).collect()
}
fn notation(sequence: &[Move]) -> String {
    if sequence.is_empty() {
        "0".into()
    } else {
        format!("{} {}",sequence.len(),sequence.iter().map(|m|m.text()).collect::<Vec<_>>().join(" "))
    }
}
fn axis(m:u8) -> u8 {
    if b"RLMrlx".contains(&m) {
        b'x'
    } else if b"UDEudy".contains(&m) {
        b'y'
    } else {
        b'z'
    }
}
fn solved(state: &State) -> bool {
    (0..54).all(|i|state[i]==state[(i/9)*9+4])
}
fn simplify(mut sequence:Vec<Move>) -> Vec<Move> {
    loop {
        let mut out=Vec::new();
        let mut at=0;
        while at<sequence.len() {
            let a=axis(sequence[at].letter);
            let mut run:Vec<Move>=Vec::new();
            while at<sequence.len() && axis(sequence[at].letter)==a {
                let m=sequence[at];
                if let Some(old)=run.iter_mut().find(|n|n.letter==m.letter) {
                    old.amount=(old.amount+m.amount)%4;
                } else {
                    run.push(m);
                }
                at+=1;
            }
            out.extend(run.into_iter().filter(|m|m.amount!=0));
        }
        if out==sequence {
            return out;
        }
        sequence=out;
    }
}
fn number(s:&str) -> Option<u64> {
    if s.is_empty() || s.len()>10 || (s.len()>1 && s.starts_with('0')) || !s.bytes().all(|c|c.is_ascii_digit()) {
        None
    } else {
        s.parse().ok()
    }
}
fn name(s:&str) -> bool {
    (1..=8).contains(&s.len()) && s.bytes().all(|c|c.is_ascii_lowercase())
}
struct SequenceParser<'a> {
    line:&'a [u8],at:usize,macros:&'a BTreeMap<String,Vec<Move>>
}
impl SequenceParser<'_> {
    fn current(&self) -> Option<u8> {
        self.line.get(self.at).copied()
    }
    fn skip(&mut self) {
        while self.current()==Some(b' ') {
            self.at+=1;
        }
    }
    fn syntax(&self) -> String {
        format!("error: syntax at {}",(self.at+1).min(self.line.len()+1))
    }
    fn power(&mut self,sequence:Vec<Move>) -> Vec<Move> {
        let mut count=1;
        if self.current().is_some_and(|c|(b'1'..=b'9').contains(&c)) {
            count=(self.line[self.at]-b'0') as usize;
            self.at+=1;
            if self.current().is_some_and(|c|c.is_ascii_digit()) {
                count=count*10+(self.line[self.at]-b'0') as usize;
                self.at+=1;
            }
        }
        let invert=self.current()==Some(b'\'');
        if invert {
            self.at+=1;
        }
        let result=sequence.repeat(count);
        if invert {
            inverse(&result)
        } else {
            result
        }
    }
    fn sequence(&mut self) -> Result<Vec<Move>,String> {
        let mut out=Vec::new();
        loop {
            self.skip();
            let Some(c)=self.current() else {
                break;
            };
            let next=if LETTERS.as_bytes().contains(&c) {
                self.at+=1;
                let amount=match self.current() {
                    Some(b'2')=>{
                        self.at+=1;
                        2
                    },Some(b'\'')=>{
                        self.at+=1;
                        3
                    },_=>1
                };
                vec![Move {
                    letter:c,amount
                }]
            } else if c==b'(' {
                self.at+=1;
                let sequence=self.sequence()?;
                self.skip();
                if self.current()!=Some(b')') {
                    return Err(self.syntax());
                }
                self.at+=1;
                self.power(sequence)
            } else if c==b'[' {
                self.at+=1;
                let a=self.sequence()?;
                self.skip();
                let separator=self.current();
                if separator!=Some(b',') && separator!=Some(b':') {
                    return Err(self.syntax());
                }
                self.at+=1;
                let b=self.sequence()?;
                self.skip(); if self.current()!=Some(b']') {
                    return Err(self.syntax());
                }
                self.at+=1;
                let mut sequence=a.clone();
                sequence.extend(&b);
                sequence.extend(inverse(&a));
                if separator==Some(b',') {
                    sequence.extend(inverse(&b));
                }
                self.power(sequence)
            } else if c==b'{' {
                self.at+=1;
                let start=self.at;
                while self.current().is_some_and(|c|c.is_ascii_lowercase()) {
                    self.at+=1;
                }
                if self.at==start || self.current()!=Some(b'}') {
                    return Err(self.syntax());
                }
                let name=std::str::from_utf8(&self.line[start..self.at]).unwrap();
                let sequence=self.macros.get(name).ok_or_else(||format!("error: undefined {name}"))?.clone();
                self.at+=1;
                self.power(sequence)
            } else {
                break;
            };
            out.extend(next);
        }
        Ok(out)
    }
    fn whole(&mut self) -> Result<Vec<Move>,String> {
        let sequence=self.sequence()?;
        self.skip();
        if self.current().is_some() {
            Err(self.syntax())
        } else if sequence.len()>500 {
            Err("error: too long".into())
        } else {
            Ok(sequence)
        }
    }
}
struct Cube {
    state:State,history:Vec<Move>,redo:Vec<Move>,macros:BTreeMap<String,Vec<Move>>,saves:BTreeMap<String,(State,Vec<Move>)>,moves:Vec<(Move,Permutation)>,rotations:Vec<(Vec<Move>,Permutation)>,
}
impl Cube {
    fn new() -> Self {
        fn index(face:u8,row:usize,col:usize) -> usize {
            FACES.as_bytes().iter().position(|&f|f==face).unwrap()*9+row*3+col
        }
        let mut basics=BTreeMap::new();
        for &letter in b"URFDLBMES" {
            let mut p=identity();
            if FACES.as_bytes().contains(&letter) {
                for i in 0..3 {
                    for j in 0..3 {
                        p[index(letter,i,j)]=index(letter,j,2-i);
                    }
                }
            }
            let mut link=|f,r,c,g,s,d| {
                p[index(f,r,c)]=index(g,s,d);
            };
            for i in 0..3 {
                match letter {
                    b'U'=>{
                        link(b'F',0,i,b'L',0,i);
                        link(b'L',0,i,b'B',0,i);
                        link(b'B',0,i,b'R',0,i);
                        link(b'R',0,i,b'F',0,i);
                    }
                    b'R'=>{
                        link(b'F',i,2,b'U',i,2);
                        link(b'U',i,2,b'B',2-i,0);
                        link(b'B',i,0,b'D',2-i,2);
                        link(b'D',i,2,b'F',i,2);
                    }
                    b'F'=>{
                        link(b'U',2,i,b'R',i,0);
                        link(b'R',i,0,b'D',0,2-i);
                        link(b'D',0,i,b'L',i,2);
                        link(b'L',i,2,b'U',2,2-i);
                    }
                    b'D'=>{
                        link(b'F',2,i,b'R',2,i);
                        link(b'R',2,i,b'B',2,i);
                        link(b'B',2,i,b'L',2,i);
                        link(b'L',2,i,b'F',2,i);
                    }
                    b'L'=>{
                        link(b'U',i,0,b'F',i,0);
                        link(b'F',i,0,b'D',i,0);
                        link(b'D',i,0,b'B',2-i,2);
                        link(b'B',i,2,b'U',2-i,0);
                    }
                    b'B'=>{
                        link(b'U',0,i,b'L',2-i,0);
                        link(b'L',i,0,b'D',2,i);
                        link(b'D',2,i,b'R',2-i,2);
                        link(b'R',i,2,b'U',0,i);
                    }
                    b'M'=>{
                        link(b'U',i,1,b'F',i,1);
                        link(b'F',i,1,b'D',i,1);
                        link(b'D',i,1,b'B',2-i,1);
                        link(b'B',i,1,b'U',2-i,1);
                    }
                    b'E'=>{
                        link(b'F',1,i,b'R',1,i);
                        link(b'R',1,i,b'B',1,i);
                        link(b'B',1,i,b'L',1,i);
                        link(b'L',1,i,b'F',1,i);
                    }
                    _=>{
                        link(b'U',1,i,b'R',i,1);
                        link(b'R',i,1,b'D',1,2-i);
                        link(b'D',1,i,b'L',i,1);
                        link(b'L',i,1,b'U',1,2-i);
                    }
                }
            }
            basics.insert(letter,p);
        }
        for (letter,components) in [(b'r',"RM'"),(b'l',"LM"),(b'u',"UE'"),(b'd',"DE"),(b'f',"FS"),(b'b',"BS'"),(b'x',"RM'L'"),(b'y',"UE'D'"),(b'z',"FSB'")] {
            let mut p=identity();
            let b=components.as_bytes();
            let mut at=0;
            while at<b.len() {
                let base=basics[&b[at]];
                at+=1;
                let n=if b.get(at)==Some(&b'\'') {
                    at+=1;
                    3
                } else {
                    1
                };
                for _ in 0..n {
                    p=compose(&p,&base);
                }
            }
            basics.insert(letter,p);
        }
        let mut cube=Self {
            state:solved_state(),history:Vec::new(),redo:Vec::new(),macros:BTreeMap::new(),saves:BTreeMap::new(),moves:Vec::new(),rotations:Vec::new()
        };
        for letter in LETTERS.bytes() {
            let mut p=identity();
            for amount in 1..=3 {
                p=compose(&p,&basics[&letter]);
                cube.moves.push((Move {
                    letter,amount
                },p));
            }
        }
        for base in [None,Some(Move {
            letter:b'x',amount:1
        }),Some(Move {
            letter:b'x',amount:2
        }),Some(Move {
            letter:b'x',amount:3
        }),Some(Move {
            letter:b'z',amount:1
        }),Some(Move {
            letter:b'z',amount:3
        })] {
            for y in [0,1,2,3] {
                let mut sequence=base.into_iter().collect::<Vec<_>>();
                if y!=0 {
                    sequence.push(Move {
                        letter:b'y',amount:y
                    });
                }
                let p=cube.effect(&sequence);
                cube.rotations.push((sequence,p));
            }
        }
        cube
    }
    fn permutation(&self,m:Move) -> &Permutation {
        &self.moves.iter().find(|(n,_)|*n==m).unwrap().1
    }
    fn effect(&self,sequence:&[Move]) -> Permutation {
        sequence.iter().fold(identity(),|p,&m|compose(&p,self.permutation(m)))
    }
    fn apply_sequence(&self,state:&State,sequence:&[Move]) -> State {
        apply(state,&self.effect(sequence))
    }
    fn conjugate(&self,p:&Permutation,m:Move,outer:bool) -> Move {
        let effect=compose(&compose(p,self.permutation(m)),&inverse_permutation(p));
        self.moves.iter().find(|(n,q)|(!outer || FACES.as_bytes().contains(&n.letter)) && *q==effect).unwrap().0
    }
    fn normalized(&self,state:&State) -> Option<(Vec<Move>,State)> {
        self.rotations.iter().find_map(|(sequence,p)| {
            let s=apply(state,p);
            (0..6).all(|f|s[f*9+4]==COLORS[f]).then_some((sequence.clone(),s))
        })
    }
    fn pieces<const N:usize>(state:&State,positions:&[[usize; N]]) -> Vec<Option<(usize,usize)>> {
        let solved=solved_state();
        positions.iter().map(|position|positions.iter().enumerate().find_map(|(piece,colors)| (0..N).find(|&t|(0..N).all(|j|state[position[(t+j)%N]]==solved[colors[j]])).map(|t|(piece,t)))).collect()
    }
    fn corners(state:&State) -> Vec<Option<(usize,usize)>> {
        Self::pieces(state,&CORNER_STICKERS)
    }
    fn edges(state:&State) -> Vec<Option<(usize,usize)>> {
        Self::pieces(state,&EDGE_STICKERS)
    }
    fn check(&self,w:&str) -> Option<String> {
        if w.len()!=54 {
            return Some(format!("length {}",w.len()));
        }
        let b=w.as_bytes();
        if let Some(i)=b.iter().position(|c|!COLORS.contains(c)) {
            return Some(format!("char {}",i+1));
        }
        for &c in COLORS {
            let count=b.iter().filter(|&&x|x==c).count();
            if count!=9 {
                return Some(format!("count {} {count}",c as char));
            }
        }
        let state:State=b.try_into().unwrap();
        let Some((_,normalized))=self.normalized(&state) else {
            return Some("centers".into());
        };
        let corners=Self::corners(&state);
        let edges=Self::edges(&state);
        if let Some(i)=corners.iter().position(Option::is_none) {
            return Some(format!("corner {}",CORNERS[i]));
        }
        if let Some(i)=edges.iter().position(Option::is_none) {
            return Some(format!("edge {}",EDGES[i]));
        }
        for (names,positions) in [(CORNERS.as_slice(),&corners),(EDGES.as_slice(),&edges)] {
            for (i,name) in names.iter().enumerate() {
                if !positions.iter().any(|p|p.unwrap().0==i) {
                    return Some(format!("missing {name}"));
                }
            }
        }
        let corners=Self::corners(&normalized);
        let edges=Self::edges(&normalized);
        if corners.iter().map(|p|p.unwrap().1).sum::<usize>()%3!=0 {
            return Some("twist".into());
        }
        if edges.iter().map(|p|p.unwrap().1).sum::<usize>()%2!=0 {
            return Some("flip".into());
        }
        let parity=|ps:&[Option<(usize,usize)>]| {
            let mut count=0;
            for i in 0..ps.len() {
                for j in i+1..ps.len() {
                    count+=usize::from(ps[i].unwrap().0>ps[j].unwrap().0);
                }
            }
            count%2
        };
        if parity(&corners)!=parity(&edges) {
            return Some("parity".into());
        }
        None
    }
    fn cycles(positions:Vec<Option<(usize,usize)>>,names:&[&str],modulus:usize) -> String {
        let mut destination=vec![0; names.len()];
        let mut orientation=vec![0; names.len()];
        for (q,p) in positions.into_iter().enumerate() {
            let (piece,t)=p.unwrap();
            destination[piece]=q;
            orientation[piece]=t;
        }
        let mut seen=vec![false; names.len()];
        let mut out=Vec::new();
        for start in 0..names.len() {
            if seen[start] {
                continue;
            }
            let mut cycle=Vec::new();
            let mut sum=0;
            let mut p=start;
            while !seen[p] {
                seen[p]=true;
                cycle.push(names[p]);
                sum+=orientation[p];
                p=destination[p];
            }
            let mark=if modulus==1 || sum%modulus==0 {
                ""
            } else if modulus==3 && sum%3==2 {
                "-"
            } else {
                "+"
            };
            if cycle.len()>=2 || !mark.is_empty() {
                out.push(format!("({}){mark}",cycle.join(" ")));
            }
        }
        if out.is_empty() {
            "none".into()
        } else {
            out.join(" ")
        }
    }
    fn order(&self,sequence:&[Move]) -> u64 {
        fn gcd(mut a:u64,mut b:u64) -> u64 {
            while b!=0 {
                (a,b)=(b,a%b);
            }
            a
        }
        let p=self.effect(sequence);
        let mut seen=[false; 54];
        let mut result=1;
        for start in 0..54 {
            let mut i=start;
            let mut length=0;
            while !seen[i] {
                seen[i]=true;
                length+=1;
                i=p[i];
            }
            if length!=0 {
                result=result/gcd(result,length)*length;
            }
        }
        result
    }
    fn search(&self,state:&State,left:usize,previous:Option<u8>,path:&mut Vec<Move>) -> bool {
        if left==0 {
            return solved(state);
        }
        for face in FACES.bytes() {
            if previous==Some(face) || matches!((previous,face),(Some(b'D'),b'U')|(Some(b'L'),b'R')|(Some(b'B'),b'F')) {
                continue;
            }
            for amount in 1..=3 {
                let m=Move {
                    letter:face,amount
                };
                path.push(m);
                if self.search(&apply(state,self.permutation(m)),left-1,Some(face),path) {
                    return true;
                }
                path.pop();
            }
        }
        false
    }
    fn command(&mut self,line:&str) -> Result<Vec<String>,String> {
        let (command,arg)=line.split_once(' ').map_or((line,None),|(c,a)|(c,Some(a)));
        let none=["RESET","SHOW","STATE","ISSOLVED","HISTORY","SOLUTION","ANALYZE","STAGE","MACROS"];
        let word=["CHECK","LOAD","UNDO","REDO","SEARCH","WHERE","SAVE","RESTORE","SCRAMBLE"];
        let sequence_commands=["APPLY","INVERT","SIMPLIFY","METRICS","ORDER","CYCLES","UNROTATE","UNTIL"];
        let head_commands=["DEFINE","MIRROR","ROTATE"];
        if !none.contains(&command) && !word.contains(&command) && !sequence_commands.contains(&command) && !head_commands.contains(&command) {
            return Err(format!("error: unknown command {command}"));
        }
        let words:Vec<_>=arg.map_or(Vec::new(),|a|a.split(' ').collect());
        let head=words.first().copied().unwrap_or("");
        let bad=||"error: bad arguments".to_string();
        if none.contains(&command) && arg.is_some() {
            return Err(bad());
        }
        if word.contains(&command) {
            if words.len()!=if command=="SCRAMBLE" {
                2
            } else {
                1
            }
            {
                return Err(bad());
            }
            if ["UNDO","REDO","SEARCH","SCRAMBLE"].contains(&command) && words.iter().any(|w|number(w).is_none()) {
                return Err(bad());
            }
            if ["SAVE","RESTORE"].contains(&command) && !name(head) {
                return Err(bad());
            }
        }
        if head_commands.contains(&command) && (arg.is_none() || match command {
            "DEFINE"=>!name(head),"MIRROR"=>!["LR","UD","FB"].contains(&head),_=>!["x","x'","x2","y","y'","y2","z","z'","z2"].contains(&head)
        }) {
            return Err(bad());
        }
        let sequence=if sequence_commands.contains(&command) || head_commands.contains(&command) {
            let start=if head_commands.contains(&command) {
                (command.len()+head.len()+2).min(line.len())
            } else {
                (command.len()+1).min(line.len())
            };
            SequenceParser {
                line:line.as_bytes(),at:start,macros:&self.macros
            }.whole()?
        } else {
            Vec::new()
        };
        let n=if ["UNDO","REDO","SEARCH","SCRAMBLE"].contains(&command) {
            number(head).unwrap()
        } else {
            0
        };
        if (["UNDO","REDO"].contains(&command) && n==0) || (command=="SEARCH" && n>4) || (command=="SCRAMBLE" && (!(1..=50).contains(&n) || !(1..=2147483646).contains(&number(words[1]).unwrap()))) {
            return Err("error: bad value".into());
        }
        if command=="WHERE" && !CORNERS.contains(&head) && !EDGES.contains(&head) {
            return Err(format!("error: unknown piece {head}"));
        }
        let text=match command {
            "RESET"=>{
                self.state=solved_state();
                self.history.clear();
                self.redo.clear();
                "reset".into()
            }
            "SHOW"=>{
                let mut out=Vec::new();
                for face_group in [vec![0],vec![4,2,1,5],vec![3]] {
                    for row in 0..3 {
                        let mut colors=Vec::new();
                        for &face in &face_group {
                            for col in 0..3 {
                                colors.push((self.state[face*9+row*3+col] as char).to_string());
                            }
                        }
                        out.push(if face_group.len()==1 {
                            "      ".to_string()+&colors.join(" ")
                        } else {
                            colors.join(" ")
                        });
                    }
                }
                return Ok(out);
            }
            "STATE"=>format!("state {}",std::str::from_utf8(&self.state).unwrap()),
            "ISSOLVED"=>if solved(&self.state) {
                "solved".into()
            } else {
                format!("unsolved {}",(0..54).filter(|&i|self.state[i]!=self.state[(i/9)*9+4]).count())
            },
            "HISTORY"=>format!("history {}",notation(&self.history)),"SOLUTION"=>format!("solution {}",notation(&simplify(inverse(&self.history)))),
            "MACROS"=>{
                let mut out=vec![format!("macros {}",self.macros.len())];
                for (name,sequence) in &self.macros {
                    out.push(format!("macro {name} {}",notation(sequence)));
                }
                return Ok(out);
            }
            "CHECK"|"LOAD"=>{
                if let Some(reason)=self.check(head) {
                    if command=="LOAD" {
                        return Err(format!("error: invalid {reason}"));
                    }
                    format!("invalid {reason}")
                } else if command=="CHECK" {
                    "valid".into()
                } else {
                    self.state=head.as_bytes().try_into().unwrap();
                    self.history.clear();
                    self.redo.clear();
                    "loaded".into()
                }
            }
            "UNDO"|"REDO"=>{
                let undo=command=="UNDO";
                let count=n.min(if undo {
                    self.history.len() as u64
                } else {
                    self.redo.len() as u64
                }) as usize;
                if count==0 {
                    return Err(format!("error: nothing to {}",command.to_ascii_lowercase()));
                }
                for _ in 0..count {
                    let m=if undo {
                        self.history.pop().unwrap()
                    } else {
                        self.redo.pop().unwrap()
                    };
                    self.state=apply(&self.state,self.permutation(if undo {
                        m.inverse()
                    } else {
                        m
                    }));
                    if undo {
                        self.redo.push(m);
                    } else {
                        self.history.push(m);
                    }
                }
                format!("{} {count}",if undo {
                    "undone"
                } else {
                    "redone"
                })
            }
            "SAVE"=>{
                self.saves.insert(head.into(),(self.state,self.history.clone()));
                format!("saved {head}")
            }
            "RESTORE"=>{
                let (state,history)=self.saves.get(head).ok_or_else(||format!("error: no save {head}"))?.clone();
                self.state=state;
                self.history=history;
                self.redo.clear();
                format!("restored {head}")
            }
            "APPLY"=>{
                self.state=self.apply_sequence(&self.state,&sequence);
                self.history.extend(&sequence);
                self.redo.clear();
                format!("applied {}",sequence.len())
            }
            "DEFINE"=>{
                self.macros.insert(head.into(),sequence.clone());
                format!("defined {head} {}",sequence.len())
            }
            "INVERT"=>format!("inverse {}",notation(&inverse(&sequence))),"SIMPLIFY"=>format!("simplified {}",notation(&simplify(sequence))),
            "ORDER"=>format!("order {}",self.order(&sequence)),
            "METRICS"=>{
                let mut htm=0;
                let mut qtm=0;
                let mut stm=0;
                for m in &sequence {
                    if b"xyz".contains(&m.letter){
                        continue;
                    }
                    let h=if b"MES".contains(&m.letter){
                        2
                    } else {
                        1
                    };
                    htm+=h;
                    qtm+=h*if m.amount==2{
                        2
                    } else {
                        1
                    };
                    stm+=1;
                }
                format!("metrics htm {htm} qtm {qtm} stm {stm} etm {}",sequence.len())
            }
            "ROTATE"=>{
                let rot=Move {
                    letter:head.as_bytes()[0],amount:if head.ends_with('2'){
                        2
                    } else if head.ends_with('\''){
                        3
                    } else {
                        1
                    }
                };
                let p=*self.permutation(rot);
                format!("rotated {}",notation(&sequence.iter().map(|&m|self.conjugate(&p,m,false)).collect::<Vec<_>>()))
            }
            "MIRROR"=>{
                let mirror=match head {
                    "LR"=>b'x',"UD"=>b'y',_=>b'z'
                };
                let out:Vec<_>=sequence.iter().map(|&m|{
                    if axis(m.letter)==mirror {
                        if let Some(i)=b"RLrlUDudFBfb".iter().position(|&c|c==m.letter){
                            Move {
                                letter:b"LRlrDUduBFbf"[i],amount:4-m.amount
                            }
                        } else {
                            m
                        }
                    } else {
                        m.inverse()
                    }
                }).collect();
                format!("mirror {}",notation(&out))
            }
            "UNROTATE"=>{
                let mut out=Vec::new();
                let mut rotation=identity();
                for m in &sequence {
                    let replacement=match m.letter {
                        b'M'=>"RL'x'",b'E'=>"UD'y'",b'S'=>"F'Bz",b'r'=>"Lx",b'l'=>"Rx'",b'u'=>"Dy",b'd'=>"Uy'",b'f'=>"Bz",b'b'=>"Fz'",_=>""
                    };
                    let expanded=if replacement.is_empty(){
                        vec![*m]
                    } else {
                        let mut parser=SequenceParser {
                            line:replacement.as_bytes(),at:0,macros:&self.macros
                        };
                        parser.whole().unwrap().into_iter().map(|n|Move {
                            amount:n.amount*m.amount%4,..n
                        }).filter(|n|n.amount!=0).collect()
                    };
                    for n in expanded {
                        if b"xyz".contains(&n.letter){
                            rotation=compose(&rotation,self.permutation(n));
                        } else {
                            out.push(self.conjugate(&rotation,n,true));
                        }
                    }
                }
                out.extend(&self.rotations.iter().find(|(_,p)|*p==rotation).unwrap().0);
                format!("unrotated {}",notation(&out))
            }
            "UNTIL"=>{
                let p=self.effect(&sequence);
                let mut state=self.state;
                let mut found=None;
                for i in 1..=self.order(&sequence){
                    state=apply(&state,&p);
                    if solved(&state){
                        found=Some(i);
                        break;
                    }
                }
                format!("until {}",found.map_or("never".into(),|n|n.to_string()))
            }
            "SEARCH"=>{
                let mut answer=None;
                for depth in 0..=n as usize {
                    let mut path=Vec::new();
                    if self.search(&self.state,depth,None,&mut path){
                        answer=Some(path);
                        break;
                    }
                }
                answer.map_or("not found".into(),|s|format!("found {}",notation(&s)))
            }
            "SCRAMBLE"=>{
                let mut x=number(words[1]).unwrap();
                let mut out:Vec<Move>=Vec::new();
                for _ in 0..n {
                    let faces:Vec<_>=FACES.bytes().filter(|&f|out.last().is_none_or(|m|m.letter!=f) && (out.len()<2 || axis(out[out.len()-1].letter)!=axis(out[out.len()-2].letter) || axis(f)!=axis(out[out.len()-1].letter))).collect();
                    x=48271*x%2147483647;
                    let letter=faces[x as usize%faces.len()];
                    x=48271*x%2147483647;
                    out.push(Move {
                        letter,amount:[1,3,2][x as usize%3]
                    });
                }
                self.state=self.apply_sequence(&self.state,&out);
                self.history.extend(&out);
                self.redo.clear();
                format!("scramble {}",out.iter().map(|m|m.text()).collect::<Vec<_>>().join(" "))
            }
            "ANALYZE"|"STAGE"|"WHERE"=>{
                let (rotation,state)=self.normalized(&self.state).unwrap();
                let corners=Self::corners(&state);
                let edges=Self::edges(&state);
                if command=="ANALYZE" {
                    return Ok(vec![format!("rotation {}",if rotation.is_empty(){
                        "none".into()
                    } else {
                        rotation.iter().map(|m|m.text()).collect::<Vec<_>>().join(" ")
                    }),format!("corners {}",Self::cycles(corners,&CORNERS,3)),format!("edges {}",Self::cycles(edges,&EDGES,2))]);
                }
                if command=="WHERE" {
                    let (names,positions,orientation)=if CORNERS.contains(&head){
                        (CORNERS.as_slice(),corners,"twist")
                    } else {
                        (EDGES.as_slice(),edges,"flip")
                    };
                    let piece=names.iter().position(|&n|n==head).unwrap();
                    let (q,p)=positions.iter().enumerate().find(|(_,p)|p.unwrap().0==piece).unwrap();
                    format!("{head} at {} {orientation} {}",names[q],p.unwrap().1)
                } else {
                    let cross=(4..8).filter(|&i|edges[i]==Some((i,0))).count();
                    let slots=(4..8).filter(|&i|corners[i]==Some((i,0)) && edges[i+4]==Some((i+4,0))).count();
                    let top=state[..9].iter().filter(|&&c|c==b'W').count();
                    let stage=if solved(&state){
                        "solved"
                    } else if cross==4 && slots==4 && top==9{
                        "oll"
                    } else if cross==4 && slots==4{
                        "f2l"
                    } else if cross==4{
                        "cross"
                    } else {
                        "none"
                    };
                    format!("stage {stage} cross {cross} slots {slots} top {top}")
                }
            }
            "CYCLES"=>{
                let state=self.apply_sequence(&solved_state(),&sequence);
                let centers=(0..6).map(|i|Some((COLORS.iter().position(|&c|c==state[i*9+4]).unwrap(),0))).collect();
                return Ok(vec![format!("corners {}",Self::cycles(Self::corners(&state),&CORNERS,3)),format!("edges {}",Self::cycles(Self::edges(&state),&EDGES,2)),format!("centers {}",Self::cycles(centers,&["U","R","F","D","L","B"],1))]);
            }
            _=>unreachable!(),
        };
        Ok(vec![text])
    }
}
fn main() {
    let mut input=String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines=input.lines();
    let n:usize=lines.next().unwrap().parse().unwrap();
    let mut cube=Cube::new();
    for line in lines.take(n) {
        match cube.command(line){
            Ok(out)=>for line in out{
                println!("{line}");
            },Err(error)=>println!("{error}")
        }
    }
}
