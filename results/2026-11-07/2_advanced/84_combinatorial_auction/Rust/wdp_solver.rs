use crate::bids_io::Bid;
use crate::report::Fraction;
pub struct Search{
    pub welfare:i64,
    pub chosen:Vec<usize>,
    pub nodes:usize,
    pub pruned:usize,
    pub leaves:usize,
    pub improvements:Vec<(usize,i64,Vec<usize>)>,
    pub shares:Vec<(usize,Fraction,Option<usize>)>,
    pub bound:Fraction
}
struct Solver<'a>{
    bids:&'a[Bid],
    reserves:&'a[i64],
    offered:u16,
    result:Search,
    incumbent:bool
}
impl<'a> Solver<'a>{
    fn usable(&self,decided:u16,winners:u16)->Vec<usize>{
        self.bids.iter().enumerate().filter(|(_,b)|b.bundle&decided==0&&(!b.xor||winners&(1<<b.bidder)==0)).map(|(i,_)|i).collect()
    }
    fn bound(&self,decided:u16,w:i64,usable:&[usize])->(Fraction,Vec<(usize,Fraction,Option<usize>)>){
        let mut bound=Fraction::integer(w);
        let mut shares=Vec::new();
        for i in 0..self.reserves.len(){
            if self.offered&(1<<i)==0||decided&(1<<i)!=0{
                continue;
            }
            let mut share=Fraction::integer(self.reserves[i]);
            let mut source=None;
            for &j in usable{
                let b=&self.bids[j];
                if b.bundle&(1<<i)!=0{
                    let f=Fraction::new(b.amount,b.bundle.count_ones()as i64);
                    if f>share{
                        share=f;
                        source=Some(b.id);
                    }
                }
            }
            bound=bound+share;
            shares.push((i,share,source));
        }
        (bound,shares)
    }
    fn visit(&mut self,decided:u16,winners:u16,w:i64,chosen:Vec<usize>){
        self.result.nodes+=1;
        if decided==self.offered{
            self.result.leaves+=1;
            let mut chosen=chosen;
            chosen.sort();
            if !self.incumbent||w>self.result.welfare||w==self.result.welfare&&chosen<self.result.chosen{
                self.incumbent=true;
                self.result.welfare=w;
                self.result.chosen=chosen.clone();
                self.result.improvements.push((self.result.nodes,w,chosen));
            }
            return;
        }
        let usable=self.usable(decided,winners);
        if self.incumbent&&self.bound(decided,w,&usable).0<Fraction::integer(self.result.welfare){
            self.result.pruned+=1;
            return;
        }
        let j=(0..self.reserves.len()).find(|&i|self.offered&(1<<i)!=0&&decided&(1<<i)==0).unwrap();
        for k in usable{
            let b=&self.bids[k];
            if b.bundle&(1<<j)==0{
                continue;
            }
            let(mask,owner,value,id,xor)=(b.bundle,b.bidder,b.amount,b.id,b.xor);
            let mut next=chosen.clone();
            next.push(id);
            self.visit(decided|mask,if xor{
                winners|(1<<owner)
            }else{
                winners
            },w+value,next);
        }
        self.visit(decided|(1<<j),winners,w+self.reserves[j],chosen);
    }
}
pub fn solve(bids:&[Bid],reserves:&[i64],offered:u16)->Search{
    let mut solver=Solver{
        bids,
        reserves,
        offered,
        result:Search{
            welfare:0,
            chosen:Vec::new(),
            nodes:0,
            pruned:0,
            leaves:0,
            improvements:Vec::new(),
            shares:Vec::new(),
            bound:Fraction::integer(0)
        },
        incumbent:false
    };
    let usable=solver.usable(0,0);
    let(bound,shares)=solver.bound(0,0,&usable);
    solver.result.bound=bound;
    solver.result.shares=shares;
    solver.visit(0,0,0,Vec::new());
    solver.result
}
pub fn greedy_order(bids:&[Bid])->Vec<Bid>{
    let mut sorted=bids.to_vec();
    sorted.sort_by(|a,b|{
        let left=(a.amount as i128)*(a.amount as i128)*(b.bundle.count_ones()as i128);
        let right=(b.amount as i128)*(b.amount as i128)*(a.bundle.count_ones()as i128);
        right.cmp(&left).then(a.id.cmp(&b.id))
    });
    sorted
}
pub fn greedy(bids:&[Bid])->Vec<Bid>{
    let(mut used,mut owners)=(0u16,0u16);
    let mut selected=Vec::new();
    for b in bids{
        if used&b.bundle==0&&(!b.xor||owners&(1<<b.bidder)==0){
            used|=b.bundle;
            if b.xor{
                owners|=1<<b.bidder;
            }
            selected.push(b.clone());
        }
    }
    selected
}
