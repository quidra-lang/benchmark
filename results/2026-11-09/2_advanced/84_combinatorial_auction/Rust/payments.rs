use crate::bids_io::Bid;
use crate::wdp_solver;
use crate::report::Fraction;
pub fn critical(b:&Bid,order:&[Bid],reserve:i64)->(i64,Option<usize>){
    let remaining:Vec<_>=order.iter().filter(|c|c.id!=b.id).cloned().collect();
    let selected=wdp_solver::greedy(&remaining);
    if let Some(c)=selected.iter().find(|c|b.bundle&c.bundle!=0||b.xor&&b.bidder==c.bidder){
        let before=|t:i64|{
            let a=(t as i128)*(t as i128)*(c.bundle.count_ones()as i128);
            let v=(c.amount as i128)*(c.amount as i128)*(b.bundle.count_ones()as i128);
            a>v||a==v&&b.id<c.id
        };
        let(mut lo,mut hi)=(1,1);
        while !before(hi){
            hi*=2;
        }
        while lo<hi{
            let mid=(lo+hi)/2;
            if before(mid){
                hi=mid;
            }else{
                lo=mid+1;
            }
        }
        (reserve.max(lo),Some(c.id))
    }else{
        (reserve,None)
    }
}
pub fn vcg(k:usize,bids:&[Bid],reserves:&[i64],offered:u16,welfare:i64,value:i64)->(i64,i64,Vec<usize>){
    let bids:Vec<_>=bids.iter().filter(|b|b.bidder!=k).cloned().collect();
    let result=wdp_solver::solve(&bids,reserves,offered);
    (result.welfare-(welfare-value),result.welfare,result.chosen)
}
pub struct Coalition{
    pub mask:u16,
    pub members:Vec<usize>,
    pub welfare:i64,
    pub chosen:Vec<usize>
}
pub fn coalitions(n:usize,bids:&[Bid],reserves:&[i64],offered:u16)->Vec<Coalition>{
    let mut sets:Vec<Vec<usize>>=(0u16..(1u16<<n)).map(|mask|(0..n).filter(|&i|mask&(1<<i)!=0).collect()).collect();
    sets.sort_by(|a,b|a.len().cmp(&b.len()).then(a.cmp(b)));
    sets.into_iter().map(|members|{
        let mask=members.iter().fold(0u16,|a,&i|a|(1<<i));
        let bids:Vec<_>=bids.iter().filter(|b|mask&(1<<b.bidder)!=0).cloned().collect();
        let result=wdp_solver::solve(&bids,reserves,offered);
        Coalition{
            mask,
            members,
            welfare:result.welfare,
            chosen:result.chosen
        }
    }).collect()
}
pub struct Blocking{
    pub index:usize,
    pub payoff:i64,
    pub deficit:i64,
    pub minimal:bool
}
pub fn blocking(coalitions:&[Coalition],seller:i64,utilities:&[i64])->Vec<Blocking>{
    let mut blocking=Vec::new();
    for(index,c)in coalitions.iter().enumerate(){
        let payoff=seller+c.members.iter().map(|&k|utilities[k]).sum::<i64>();
        if c.welfare>payoff{
            let minimal=!blocking.iter().any(|b:&Blocking|coalitions[b.index].mask&c.mask==coalitions[b.index].mask);
            blocking.push(Blocking{
                index,
                payoff,
                deficit:c.welfare-payoff,
                minimal
            });
        }
    }
    blocking
}
pub fn gsp_price(rank:usize,ranking:&[usize],bids:&[i64])->i64{
    ranking.get(rank+1).map_or(0,|&i|bids[i])
}
pub fn ad_vcg(rank:usize,ranking:&[usize],values:&[i64],ctr:&[Fraction])->Fraction{
    let mut payment=Fraction::integer(0);
    for t in rank+1..ranking.len().min(ctr.len()+1){
        let next=ctr.get(t).copied().unwrap_or(Fraction::integer(0));
        payment=payment+Fraction::integer(values[ranking[t]])*(ctr[t-1]-next);
    }
    payment
}
