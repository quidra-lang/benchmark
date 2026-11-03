use crate::bids_io::Bid;
#[derive(Clone)] pub struct Candidate{
    pub bundle:u16,
    pub value:i64
}
pub fn candidates(bids:&[Bid],xor:bool)->Vec<Candidate>{
    let mut out=Vec::new();
    for mask in 1u16..(1u16<<bids.len()){
        if xor&&mask.count_ones()!=1{
            continue;
        }
        let(mut bundle,mut value,mut valid)=(0u16,0,true);
        for(i,b)in bids.iter().enumerate(){
            if mask&(1<<i)!=0{
                if bundle&b.bundle!=0{
                    valid=false;
                    break;
                }
                bundle|=b.bundle;
                value+=b.amount;
            }
        }
        if valid{
            out.push(Candidate{
                bundle,
                value
            });
        }
    }
    out
}
pub fn value(candidates:&[Candidate],bundle:u16)->i64{
    candidates.iter().filter(|c|c.bundle&bundle==c.bundle).map(|c|c.value).max().unwrap_or(0)
}
pub fn english(values:&[i64],reserve:i64,increment:i64)->(Option<usize>,i64,usize,Vec<Option<i64>>){
    let mut price=reserve;
    let mut steps=0;
    let mut drops=vec![None;values.len()];
    loop{
        let remaining:Vec<_>=values.iter().enumerate().filter(|(_,v)|**v>=price).map(|(i,_)|i).collect();
        for(i,&v)in values.iter().enumerate(){
            if drops[i].is_none()&&v<price{
                drops[i]=Some(price);
            }
        }
        if remaining.len()<=1{
            return(remaining.first().copied(),if remaining.is_empty(){
                0
            }else{
                price
            },steps,drops);
        }
        let previous=remaining;
        let old=price;
        price+=increment;
        steps+=1;
        let remaining:Vec<_>=values.iter().enumerate().filter(|(_,v)|**v>=price).map(|(i,_)|i).collect();
        for(i,&v)in values.iter().enumerate(){
            if drops[i].is_none()&&v<price{
                drops[i]=Some(price);
            }
        }
        if remaining.is_empty(){
            return(Some(previous[0]),old,steps,drops);
        }
        if remaining.len()==1{
            return(Some(remaining[0]),price,steps,drops);
        }
    }
}
pub fn dutch(bids:&[i64],reserve:i64,start:i64,decrement:i64)->(Option<usize>,i64,usize){
    let(mut price,mut steps)=(start,0);
    while price>=reserve{
        let winner=bids.iter().enumerate().filter(|(_,b)|**b>=price).min_by_key(|(i,b)|(std::cmp::Reverse(**b),*i)).map(|(i,_)|i);
        if winner.is_some(){
            return(winner,price,steps);
        }
        price-=decrement;
        steps+=1;
    }
    (None,0,steps)
}
