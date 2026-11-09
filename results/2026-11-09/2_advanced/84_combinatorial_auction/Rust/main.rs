mod bids_io;
mod wdp_solver;
mod payments;
mod auctions;
mod report;
use std::collections::{BTreeMap,BTreeSet};
use bids_io::{Input,Auction,Group,Bid};
use report::{Fraction as F,bundle,numbers};
struct Bidder{
    name:String,
    xor:bool,
    bids:Vec<Bid>
}
struct Validated{
    offered:u16,
    bidders:Vec<Bidder>,
    valid:Vec<Bid>,
    eligible:Vec<Bid>,
    rejects:Vec<(usize,String,String)>,
    total:usize
}
fn reserve(mask:u16,input:&Input)->i64{
    input.reserves.iter().enumerate().filter(|(i,_)|mask&(1<<i)!=0).map(|(_,v)|*v).sum()
}
fn validate_bid(text:&str,id:usize,owner:usize,xor:bool,offered:u16,earlier:&[Bid],input:&Input)->Result<Bid,String>{
    let parts:Vec<_>=text.split(':').collect();
    if parts.len()!=2{
        return Err("malformed bid".into());
    }
    let names:Vec<_>=parts[0].split('+').collect();
    let value=parts[1];
    if names.iter().any(|s|s.is_empty()||!s.bytes().all(|c|c.is_ascii_lowercase()))||value.is_empty()||value.len()>5||!value.bytes().all(|c|c.is_ascii_digit())||value.len()>1&&value.starts_with('0'){
        return Err("malformed bid".into());
    }
    let mut mask=0u16;
    for name in &names{
        let i=match input.names.iter().position(|s|s.as_str()==*name){
            Some(i)=>i,None=>return Err(format!("unknown item {}",name))
        };
        if offered&(1<<i)==0{
            return Err(format!("item not offered {}",name));
        }
        if mask&(1<<i)!=0{
            return Err(format!("duplicate item {}",name));
        }
        mask|=1<<i;
    }
    if names.len()>input.params.bundle{
        return Err("bundle too large".into());
    }
    let amount=value.parse().unwrap();
    if amount==0{
        return Err("zero value".into());
    }
    if let Some(b)=earlier.iter().find(|b|b.bundle==mask){
        return Err(format!("duplicate bundle {}",b.id));
    }
    if earlier.len()>=input.params.bids{
        return Err("too many bids".into());
    }
    Ok(Bid{
        id,
        bidder:owner,
        bundle:mask,
        amount,
        xor
    })
}
fn validate(auction:&Auction,input:&Input)->Validated{
    let offered=auction.offered.iter().fold(0,|a,s|a|(1<<input.names.iter().position(|n|n==s).unwrap()));
    let mut v=Validated{
        offered,
        bidders:Vec::new(),
        valid:Vec::new(),
        eligible:Vec::new(),
        rejects:Vec::new(),
        total:0
    };
    let mut seen=BTreeSet::new();
    for line in &auction.lines{
        let error=if !seen.insert(line.name.clone()){
            Some("duplicate bidder".into())
        }else if line.language!="XOR"&&line.language!="OR"{
            Some(format!("bad language {}",line.language))
        }else{
            None
        };
        let owner=v.bidders.len();
        let mut bidder=Bidder{
            name:line.name.clone(),
            xor:line.language=="XOR",
            bids:Vec::new()
        };
        for text in &line.bids{
            v.total+=1;
            let result=if let Some(error)=&error{
                Err(error.clone())
            }else{
                validate_bid(text,v.total,owner,bidder.xor,offered,&bidder.bids,input)
            };
            match result{
                Ok(b)=>{
                    if b.amount>=reserve(b.bundle,input){
                        v.eligible.push(b.clone());
                    }
                    v.valid.push(b.clone());
                    bidder.bids.push(b);
                },Err(message)=>v.rejects.push((v.total,line.name.clone(),message))
            }
        }
        if error.is_none(){
            v.bidders.push(bidder);
        }
    }
    v
}
fn allocation(ids:&[usize],v:&Validated,input:&Input)->(i64,i64,u16,Vec<i64>){
    let mut accepted=0;
    let mut used=0;
    let mut values=vec![0;v.bidders.len()];
    for id in ids{
        let b=v.valid.iter().find(|b|b.id==*id).unwrap();
        accepted+=b.amount;
        used|=b.bundle;
        values[b.bidder]+=b.amount;
    }
    (accepted,reserve(v.offered&!used,input),v.offered&!used,values)
}
fn unsold(mask:u16,input:&Input)->String{
    bundle(mask,&input.names).replace('+'," ")
}
fn coalition_name(members:&[usize],v:&Validated)->String{
    if members.is_empty(){
        "-".into()
    }else{
        members.iter().map(|&k|v.bidders[k].name.clone()).collect::<Vec<_>>().join("+")
    }
}
struct Ascending{
    lines:Vec<String>,
    payments:Vec<i64>,
    utilities:Vec<i64>,
    revenue:i64,
    welfare:i64,
    retained:i64,
    rounds:usize,
    capped:bool,
    exposed:usize,
    exposure:i64
}
fn ascending(name:&str,v:&Validated,input:&Input,optimum:i64)->Ascending{
    let p=&input.params;
    let n=v.bidders.len();
    let candidates:Vec<_>=v.bidders.iter().map(|b|auctions::candidates(&b.bids,b.xor)).collect();
    let mut eligibility:Vec<_>=candidates.iter().map(|c|c.iter().map(|c|c.bundle.count_ones()as usize).max().unwrap_or(0)).collect();
    let mut prices=input.reserves.clone();
    let mut holders=vec![None;input.names.len()];
    let(mut bids,mut rounds_bid,mut last)=(vec![0usize;prices.len()],vec![0usize;prices.len()],vec![0usize;prices.len()]);
    let mut lines=vec![format!("AUCTION {} increment {}",name,p.increment)];
    let mut random=p.seed;
    let(mut rounds,mut capped)=(0,false);
    for round in 1..=p.cap{
        rounds=round;
        let mut new=vec![0u16;n];
        let mut activity=vec![0;n];
        for k in 0..n{
            let held=holders.iter().enumerate().filter(|(_,h)|**h==Some(k)).fold(0u16,|a,(i,_)|a|(1<<i));
            let mut best=None;
            let mut surplus=0;
            for c in &candidates[k]{
                if (c.bundle|held).count_ones()as usize>eligibility[k]{
                    continue;
                }
                let asking:i64=(0..prices.len()).filter(|&i|c.bundle&(1<<i)!=0).map(|i|prices[i]+if holders[i].is_some()&&holders[i]!=Some(k){
                    p.increment
                }else{
                    0
                }).sum();
                if c.value-asking>surplus{
                    surplus=c.value-asking;
                    best=Some(c);
                }
            }
            activity[k]=if let Some(c)=best{
                new[k]=c.bundle&!held;
                (c.bundle|held).count_ones()as usize
            }else{
                held.count_ones()as usize
            };
        }
        let demand:u32=new.iter().map(|m|m.count_ones()).sum();
        if demand==0{
            lines.push(format!("ROUND {} none",round));
        }else{
            let requests=new.iter().enumerate().filter(|(_,m)|**m!=0).map(|(k,&m)|format!("{}:{}",v.bidders[k].name,bundle(m,&input.names))).collect::<Vec<_>>().join(" ");
            lines.push(format!("ROUND {} demand {} {}",round,demand,requests));
            for i in 0..prices.len(){
                if v.offered&(1<<i)==0{
                    continue;
                }
                let applicants:Vec<_>=(0..n).filter(|&k|new[k]&(1<<i)!=0).collect();
                if applicants.is_empty(){
                    continue;
                }
                bids[i]+=applicants.len();
                rounds_bid[i]+=1;
                last[i]=round;
                let q=if applicants.len()==1{
                    0
                }else{
                    random=(48271*random)%2147483647;
                    random as usize%applicants.len()
                };
                if holders[i].is_some(){
                    prices[i]+=p.increment;
                }
                holders[i]=Some(applicants[q]);
            }
            let standing=(0..prices.len()).filter(|&i|v.offered&(1<<i)!=0).map(|i|format!("{}={}@{}",input.names[i],prices[i],holders[i].map_or_else(||"-".into(),|k|v.bidders[k].name.clone()))).collect::<Vec<_>>().join(" ");
            lines.push(format!("STANDING {}",standing));
        }
        let mut edited=Vec::new();
        for k in 0..n{
            if activity[k]<eligibility[k]{
                eligibility[k]=activity[k];
                edited.push(format!("{}={}",v.bidders[k].name,eligibility[k]));
            }
        }
        if !edited.is_empty(){
            lines.push(format!("ELIGIBILITY {}",edited.join(" ")));
        }
        if demand==0{
            break;
        }
        if round==p.cap{
            capped=true;
        }
    }
    lines.push(format!("END rounds {} {}",rounds,if capped{
        "cap"
    }else{
        "quiet"
    }));
    let mut retained=0;
    for i in 0..prices.len(){
        if v.offered&(1<<i)==0{
            continue;
        }
        if let Some(k)=holders[i]{
            lines.push(format!("ITEM {} price {} holder {} bids {} rounds {} last {}",input.names[i],prices[i],v.bidders[k].name,bids[i],rounds_bid[i],last[i]));
        }else{
            retained+=input.reserves[i];
            lines.push(format!("ITEM {} unsold reserve {}",input.names[i],input.reserves[i]));
        }
    }
    let(mut payments,mut utilities)=(vec![0;n],vec![0;n]);
    let(mut welfare,mut exposed,mut exposure)=(retained,0,0);
    for k in 0..n{
        let won=(0..prices.len()).filter(|&i|holders[i]==Some(k)).fold(0u16,|a,i|a|(1<<i));
        payments[k]=(0..prices.len()).filter(|&i|won&(1<<i)!=0).map(|i|prices[i]).sum();
        let value=auctions::value(&candidates[k],won);
        welfare+=value;
        utilities[k]=value-payments[k];
        if utilities[k]<0{
            exposed+=1;
            exposure-=utilities[k];
        }
        lines.push(format!("BIDDER {} won {} paid {} value {} utility {} eligibility {}{}",v.bidders[k].name,bundle(won,&input.names),payments[k],value,utilities[k],eligibility[k],if utilities[k]<0{
            " exposed"
        }else{
            ""
        }));
    }
    let revenue=payments.iter().sum();
    lines.push(format!("TOTAL revenue {} welfare {} efficiency {} exposure {} exposed {}",revenue,welfare,F::new(welfare,optimum),exposure,exposed));
    Ascending{
        lines,
        payments,
        utilities,
        revenue,
        welfare,
        retained,
        rounds,
        capped,
        exposed,
        exposure
    }
}
struct Output{
    wdp:Vec<String>,
    vcg:Vec<String>,
    core:Vec<String>,
    ascending:Vec<String>,
    single:Vec<String>,
    summary:Vec<String>,
    totals:[i64;6],
    revenues:[i64;5],
    core_counts:[usize;6],
    saa_counts:[i64;4],
    single_counts:[usize;6]
}
impl Output{
    fn new()->Self{
        Self{
            wdp:Vec::new(),
            vcg:Vec::new(),
            core:Vec::new(),
            ascending:Vec::new(),
            single:Vec::new(),
            summary:vec!["mechanism,revenue,welfare,efficiency".into()],
            totals:[0;6],
            revenues:[0;5],
            core_counts:[0;6],
            saa_counts:[0;4],
            single_counts:[0;6]
        }
    }
}
fn run_auction(auction:&Auction,input:&Input,o:&mut Output){
    let v=validate(auction,input);
    let optimum=wdp_solver::solve(&v.eligible,&input.reserves,v.offered);
    let(a,r,unsold_mask,values)=allocation(&optimum.chosen,&v,input);
    let order=wdp_solver::greedy_order(&v.eligible);
    let greedy=wdp_solver::greedy(&order);
    let mut greedy_ids:Vec<_>=greedy.iter().map(|b|b.id).collect();
    greedy_ids.sort();
    let(ga,gr,gun,greedy_values)=allocation(&greedy_ids,&v,input);
    let gw=ga+gr;
    let critical:BTreeMap<_,_>=greedy.iter().map(|b|(b.id,payments::critical(b,&order,reserve(b.bundle,input)))).collect();
    let mut critical_pay=vec![0;v.bidders.len()];
    for b in &greedy{
        critical_pay[b.bidder]+=critical[&b.id].0;
    }
    let critical_total:i64=critical_pay.iter().sum();
    let critical_utility:Vec<_>=greedy_values.iter().zip(&critical_pay).map(|(a,b)|a-b).collect();
    let saa=ascending(&auction.name,&v,input,optimum.welfare);
    o.wdp.push(format!("AUCTION {} items {} bidders {} bids {} valid {} eligible {}",auction.name,v.offered.count_ones(),v.bidders.len(),v.total,v.valid.len(),v.eligible.len()));
    for(k,b)in v.bidders.iter().enumerate(){
        o.wdp.push(format!("BIDDER {} {} valid {} eligible {}",b.name,if b.xor{
            "XOR"
        }else{
            "OR"
        },b.bids.len(),v.eligible.iter().filter(|b|b.bidder==k).count()));
    }
    for(id,name,message)in &v.rejects{
        o.wdp.push(format!("REJECT {} {} {}",id,name,message));
    }
    for b in &v.valid{
        let reserve=reserve(b.bundle,input);
        if b.amount<reserve{
            o.wdp.push(format!("BELOW_RESERVE {} {} value {} reserve {}",b.id,v.bidders[b.bidder].name,b.amount,reserve));
        }
    }
    for &(i,share,source)in &optimum.shares{
        o.wdp.push(format!("SHARE {} {} {}",input.names[i],share,source.map_or_else(||"reserve".into(),|id|format!("bid {}",id))));
    }
    o.wdp.push(format!("ROOT_BOUND {}",optimum.bound));
    for(node,w,ids)in &optimum.improvements{
        o.wdp.push(format!("IMPROVE {} welfare {} bids {}",node,w,numbers(ids)));
    }
    o.wdp.push(format!("OPTIMAL welfare {} accepted {} retained {} winners {}",optimum.welfare,a,r,optimum.chosen.len()));
    for &id in &optimum.chosen{
        let b=v.valid.iter().find(|b|b.id==id).unwrap();
        o.wdp.push(format!("WIN {} {} {} {}",id,v.bidders[b.bidder].name,bundle(b.bundle,&input.names),b.amount));
    }
    o.wdp.push(format!("UNSOLD {}",unsold(unsold_mask,input)));
    o.wdp.push(format!("SEARCH nodes {} pruned {} leaves {} improvements {}",optimum.nodes,optimum.pruned,optimum.leaves,optimum.improvements.len()));
    o.wdp.push(format!("GREEDY_ORDER {}",if order.is_empty(){
        "-".into()
    }else{
        order.iter().map(|b|b.id.to_string()).collect::<Vec<_>>().join(" ")
    }));
    o.wdp.push(format!("GREEDY welfare {} accepted {} retained {} winners {} efficiency {}",gw,ga,gr,greedy.len(),F::new(gw,optimum.welfare)));
    for &id in &greedy_ids{
        let b=v.valid.iter().find(|b|b.id==id).unwrap();
        o.wdp.push(format!("GWIN {} {} {} {} critical {} against {}",id,v.bidders[b.bidder].name,bundle(b.bundle,&input.names),b.amount,critical[&id].0,critical[&id].1.map_or_else(||"-".into(),|v|v.to_string())));
    }
    o.wdp.push(format!("GUNSOLD {}",unsold(gun,input)));
    for i in 0..input.names.len(){
        if v.offered&(1<<i)==0{
            continue;
        }
        let owner=|ids:&[usize]|ids.iter().find_map(|id|v.valid.iter().find(|b|b.id==*id&&b.bundle&(1<<i)!=0).map(|b|v.bidders[b.bidder].name.clone())).unwrap_or_else(||"-".into());
        o.wdp.push(format!("ITEM {} reserve {} demand {} optimal {} greedy {}",input.names[i],input.reserves[i],v.eligible.iter().filter(|b|b.bundle&(1<<i)!=0).count(),owner(&optimum.chosen),owner(&greedy_ids)));
    }
    let n=v.bidders.len();
    let(mut vcg_pay,mut vcg_util)=(vec![0;n],vec![0;n]);
    o.vcg.push(format!("AUCTION {} welfare {}",auction.name,optimum.welfare));
    for k in 0..n{
        let ids:Vec<_>=optimum.chosen.iter().copied().filter(|id|v.valid.iter().any(|b|b.id==*id&&b.bidder==k)).collect();
        if ids.is_empty(){
            o.vcg.push(format!("BIDDER {} lost",v.bidders[k].name));
            continue;
        }
        let(payment,without,alternative)=payments::vcg(k,&v.eligible,&input.reserves,v.offered,optimum.welfare,values[k]);
        vcg_pay[k]=payment;
        vcg_util[k]=values[k]-payment;
        o.vcg.push(format!("BIDDER {} won {} value {} without {} alternative {} payment {} utility {}",v.bidders[k].name,numbers(&ids),values[k],without,numbers(&alternative),payment,vcg_util[k]));
    }
    let revenue:i64=vcg_pay.iter().sum();
    o.vcg.push(format!("TOTAL revenue {} pay_as_bid {} retained {} seller {} bidders {}",revenue,a,r,revenue+r,vcg_util.iter().sum::<i64>()));
    for k in 0..n{
        o.vcg.push(format!("PAYMENTS {} vcg {} pay_as_bid {} greedy {} critical {} saa {}",v.bidders[k].name,vcg_pay[k],values[k],greedy_values[k],critical_pay[k],saa.payments[k]));
    }
    for k in 0..n{
        o.vcg.push(format!("UTILITIES {} vcg {} critical {} saa {}",v.bidders[k].name,vcg_util[k],critical_utility[k],saa.utilities[k]));
    }
    o.core.push(format!("AUCTION {} bidders {}",auction.name,n));
    if n>input.params.core{
        o.core_counts[1]+=1;
        o.core.push("SKIPPED".into());
    }else{
        o.core_counts[0]+=1;
        let coalitions=payments::coalitions(n,&v.eligible,&input.reserves,v.offered);
        o.core.push(format!("COALITIONS {}",coalitions.len()));
        let outcomes=vec![("vcg",revenue+r,vcg_util),("greedy",gw,vec![0;n]),("critical",critical_total+gr,critical_utility),("saa",saa.revenue+saa.retained,saa.utilities.clone())];
        for(k,(name,seller,utilities))in outcomes.iter().enumerate(){
            o.core.push(format!("OUTCOME {} seller {} utilities {}",name,seller,utilities.iter().map(i64::to_string).collect::<Vec<_>>().join(" ")));
            let blocking=payments::blocking(&coalitions,*seller,utilities);
            for b in blocking.iter().filter(|b|b.minimal){
                let c=&coalitions[b.index];
                o.core.push(format!("BLOCK {} welfare {} payoff {} deficit {} bids {}",coalition_name(&c.members,&v),c.welfare,b.payoff,b.deficit,numbers(&c.chosen)));
            }
            if blocking.is_empty(){
                o.core_counts[2+k]+=1;
                o.core.push("RESULT core".into());
            }else{
                let max=blocking.iter().map(|b|b.deficit).max().unwrap();
                let by=blocking.iter().find(|b|b.deficit==max).unwrap();
                o.core.push(format!("RESULT blocked {} minimal {} max_deficit {} by {}",blocking.len(),blocking.iter().filter(|b|b.minimal).count(),max,coalition_name(&coalitions[by.index].members,&v)));
            }
        }
    }
    o.ascending.extend(saa.lines);
    let mechanisms=[("vcg",revenue,optimum.welfare),("pay_as_bid",a,optimum.welfare),("greedy",ga,gw),("critical",critical_total,gw),("saa",saa.revenue,saa.welfare)];
    for(i,(format,revenue,welfare))in mechanisms.iter().enumerate(){
        o.revenues[i]+=revenue;
        o.summary.push(format!("{}/{},{},{},{}",auction.name,format,revenue,welfare,F::new(*welfare,optimum.welfare)));
    }
    let totals=[1,v.total as i64,v.valid.len()as i64,v.eligible.len()as i64,optimum.nodes as i64,i64::from(gw==optimum.welfare)];
    for i in 0..6{
        o.totals[i]+=totals[i];
    }
    o.saa_counts[0]+=saa.rounds as i64;
    o.saa_counts[1]+=i64::from(saa.capped);
    o.saa_counts[2]+=saa.exposed as i64;
    o.saa_counts[3]+=saa.exposure;
}
fn duplicate(g:&Group)->Option<String>{
    let mut seen=BTreeSet::new();
    g.people.iter().find(|p|!seen.insert(p.name.clone())).map(|p|p.name.clone())
}
fn lot(g:&Group,input:&Input,o:&mut Output){
    o.single_counts[0]+=1;
    let error=if g.people.is_empty(){
        Some("no bidders".into())
    }else if let Some(name)=duplicate(g){
        Some(format!("duplicate bidder {}",name))
    }else{
        g.people.iter().find(|p|p.bid>p.value).map(|p|format!("bid above value {}",p.name))
    };
    if let Some(error)=error{
        o.single_counts[2]+=1;
        o.single.push(format!("LOT {} ERROR {}",g.name,error));
        return;
    }
    let reserve=g.args[0].parse::<i64>().unwrap();
    let values:Vec<_>=g.people.iter().map(|p|p.value).collect();
    let bids:Vec<_>=g.people.iter().map(|p|p.bid).collect();
    let best=|amounts:&[i64]|amounts.iter().enumerate().filter(|(_,v)|**v>=reserve).min_by_key(|(i,v)|(std::cmp::Reverse(**v),*i)).map(|(i,_)|i);
    let efficient=best(&values);
    let optimum=reserve.max(*values.iter().max().unwrap());
    o.single.push(format!("LOT {} reserve {} bidders {} efficient {} optimum {}",g.name,reserve,g.people.len(),efficient.map_or_else(||"-".into(),|i|g.people[i].name.clone()),optimum));
    let first=best(&bids);
    let first_price=first.map_or(0,|i|bids[i]);
    let second=efficient;
    let second_price=second.map_or(0,|i|values.iter().enumerate().filter(|(j,_)|*j!=i).map(|(_,v)|*v).max().unwrap_or(0).max(reserve));
    let(english,english_price,english_steps,drops)=auctions::english(&values,reserve,input.params.english);
    let(dutch,dutch_price,dutch_steps)=auctions::dutch(&bids,reserve,input.params.dutch_start,input.params.dutch_decrement);
    let results=[(first,first_price,None),(second,second_price,None),(english,english_price,Some(english_steps)),(dutch,dutch_price,Some(dutch_steps)),(first,first_price,None)];
    let labels=["FIRST_PRICE","SECOND_PRICE","ENGLISH","DUTCH","ALL_PAY"];
    let formats=["first_price","second_price","english","dutch","all_pay"];
    let mut utilities=vec![vec![0i64;5];g.people.len()];
    let mut revenues=Vec::new();
    for(k,&(winner,price,steps))in results.iter().enumerate(){
        if k==4{
            for i in 0..g.people.len(){
                if bids[i]>=reserve{
                    utilities[i][k]=-bids[i];
                }
            }
        }
        if let Some(i)=winner{
            utilities[i][k]=values[i]-price;
        }
        let revenue=if k==4{
            bids.iter().filter(|&&b|b>=reserve).sum()
        }else{
            price
        };
        revenues.push(revenue);
        let welfare=winner.map_or(reserve,|i|values[i]);
        let notation=winner.map_or_else(||"unsold".into(),|i|format!("winner {} price {} utility {}",g.people[i].name,price,utilities[i][k]));
        o.single.push(format!("{} {}{} revenue {} welfare {} efficiency {}",labels[k],notation,steps.map_or_else(String::new,|n|format!(" steps {}",n)),revenue,welfare,F::new(welfare,optimum)));
        if k==2{
            o.single.push(format!("ENGLISH_DROPS {}",g.people.iter().enumerate().map(|(i,p)|format!("{}={}",p.name,drops[i].map_or_else(||"-".into(),|v|v.to_string()))).collect::<Vec<_>>().join(" ")));
        }
        o.summary.push(format!("{}/{},{},{},{}",g.name,formats[k],revenue,welfare,F::new(welfare,optimum)));
    }
    for(i,p)in g.people.iter().enumerate(){
        o.single.push(format!("UTILITY {} {}",p.name,utilities[i].iter().map(i64::to_string).collect::<Vec<_>>().join(" ")));
    }
    let mut ranking:Vec<_>=(0..5).collect();
    ranking.sort_by_key(|&i|(std::cmp::Reverse(revenues[i]),i));
    o.single.push(format!("RANKING {}",ranking.iter().map(|&i|formats[i]).collect::<Vec<_>>().join(" ")));
}
fn slots(g:&Group,o:&mut Output){
    o.single_counts[1]+=1;
    let mut ctr=Vec::new();
    let mut error=None;
    for text in &g.args{
        let parts:Vec<_>=text.split('/').collect();
        let form=parts.len()==2&&parts.iter().all(|s|!s.is_empty()&&!s.starts_with('0')&&s.bytes().all(|c|c.is_ascii_digit()));
        if !form{
            error=Some(format!("bad ctr {}",text));
            break;
        }
        let f=F::new(parts[0].parse().unwrap(),parts[1].parse().unwrap());
        if f>F::integer(1)||ctr.last().map_or(false,|previous|f>=*previous){
            error=Some(format!("bad ctr {}",text));
            break;
        }
        ctr.push(f);
    }
    if error.is_none(){
        if g.people.is_empty(){
            error=Some("no advertisers".into());
        }else if let Some(name)=duplicate(g){
            error=Some(format!("duplicate advertiser {}",name));
        }
    }
    if let Some(error)=error{
        o.single_counts[2]+=1;
        o.single.push(format!("SLOTS {} ERROR {}",g.name,error));
        return;
    }
    let n=g.people.len();
    let k=ctr.len();
    let values:Vec<_>=g.people.iter().map(|p|p.value).collect();
    let bids:Vec<_>=g.people.iter().map(|p|p.bid).collect();
    let mut gsp:Vec<_>=(0..n).collect();
    gsp.sort_by_key(|&i|(std::cmp::Reverse(bids[i]),i));
    let mut vcg:Vec<_>=(0..n).collect();
    vcg.sort_by_key(|&i|(std::cmp::Reverse(values[i]),i));
    let c=|rank:usize|ctr.get(rank).copied().unwrap_or(F::integer(0));
    let b=|rank:usize|gsp.get(rank).map_or(0,|&i|bids[i]);
    let optimum=(0..n.min(k)).fold(F::integer(0),|a,s|a+c(s)*F::integer(values[vcg[s]]));
    o.single.push(format!("SLOTS {} slots {} advertisers {}",g.name,k,n));
    let(mut gsp_revenue,mut welfare,mut vcg_revenue)=(F::integer(0),F::integer(0),F::integer(0));
    for s in 0..n.min(k){
        let i=gsp[s];
        let price=payments::gsp_price(s,&gsp,&bids);
        let payment=c(s)*F::integer(price);
        let utility=c(s)*F::integer(values[i]-price);
        gsp_revenue=gsp_revenue+payment;
        welfare=welfare+c(s)*F::integer(values[i]);
        o.single.push(format!("GSP {} {} ctr {} bid {} price {} payment {} utility {}",s+1,g.people[i].name,c(s),bids[i],price,payment,utility));
    }
    o.single.push(format!("GSP_TOTAL revenue {} welfare {} efficiency {}",gsp_revenue,welfare,welfare/optimum));
    for s in 0..n.min(k){
        let i=vcg[s];
        let payment=payments::ad_vcg(s,&vcg,&values,&ctr);
        vcg_revenue=vcg_revenue+payment;
        o.single.push(format!("VCG {} {} ctr {} value {} payment {} price {} utility {}",s+1,g.people[i].name,c(s),values[i],payment,payment/c(s),c(s)*F::integer(values[i])-payment));
    }
    o.single.push(format!("VCG_TOTAL revenue {} welfare {} efficiency 1",vcg_revenue,optimum));
    let mut violations=0;
    for s in 1..n.min(k+1){
        let i=gsp[s];
        let stay=c(s)*F::integer(values[i]-b(s+1));
        let swap=c(s-1)*F::integer(values[i]-b(s));
        if stay<swap{
            violations+=1;
        }
        o.single.push(format!("ENVY {} {} stay {} swap {} {}",s+1,g.people[i].name,stay,swap,if stay>=swap{
            "ok"
        }else{
            "violated"
        }));
    }
    if violations==0{
        o.single_counts[3]+=1;
        o.single.push("ENVY_FREE yes".into());
    }else{
        o.single.push(format!("ENVY_FREE no violations {}",violations));
    }
    let mut deviations=0;
    for s in 0..n{
        let i=gsp[s];
        let stay=c(s)*F::integer(values[i]-b(s+1));
        for t in 0..k{
            if t==s{
                continue;
            }
            let payoff=c(t)*F::integer(values[i]-if t<s{
                b(t)
            }else{
                b(t+1)
            });
            if payoff>stay{
                deviations+=1;
                o.single.push(format!("DEVIATE {} from {} to {} gain {}",g.people[i].name,s+1,t+1,payoff-stay));
            }
        }
    }
    if deviations==0{
        o.single_counts[4]+=1;
        o.single.push("NASH yes".into());
    }else{
        o.single.push(format!("NASH no deviations {}",deviations));
    }
    if deviations==0&&violations==0{
        o.single_counts[5]+=1;
        o.single.push("EQUILIBRIUM yes".into());
    }else{
        o.single.push("EQUILIBRIUM no".into());
    }
    o.summary.push(format!("{}/gsp,{},{},{}",g.name,gsp_revenue,welfare,welfare/optimum));
    o.summary.push(format!("{}/vcg,{},{},1",g.name,vcg_revenue,optimum));
}
fn main(){
    let input=bids_io::read();
    let mut o=Output::new();
    for name in &input.params.run{
        let auction=input.auctions.iter().find(|a|&a.name==name).unwrap();
        run_auction(auction,&input,&mut o);
    }
    for group in &input.groups{
        if group.lot{
            lot(group,&input,&mut o);
        }else{
            slots(group,&mut o);
        }
    }
    let t=o.totals;
    o.wdp.push(format!("TOTAL auctions {} bids {} valid {} eligible {} nodes {} greedy_optimal {}",t[0],t[1],t[2],t[3],t[4],t[5]));
    let r=o.revenues;
    o.vcg.push(format!("OVERALL vcg {} pay_as_bid {} greedy {} critical {} saa {}",r[0],r[1],r[2],r[3],r[4]));
    let c=o.core_counts;
    o.core.push(format!("SUMMARY checked {} skipped {} vcg {} greedy {} critical {} saa {}",c[0],c[1],c[2],c[3],c[4],c[5]));
    let a=o.saa_counts;
    o.ascending.push(format!("SUMMARY auctions {} rounds {} capped {} exposed {} exposure {}",input.params.run.len(),a[0],a[1],a[2],a[3]));
    let s=o.single_counts;
    o.single.push(format!("SUMMARY lots {} slot_groups {} errors {} envy_free {} nash {} equilibria {}",s[0],s[1],s[2],s[3],s[4],s[5]));
    report::write("wdp.txt",&o.wdp);
    report::write("vcg.txt",&o.vcg);
    report::write("core_check.txt",&o.core);
    report::write("ascending_log.txt",&o.ascending);
    report::write("single_item.txt",&o.single);
    report::write("summary.csv",&o.summary);
}
