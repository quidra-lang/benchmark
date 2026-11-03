use std::collections::BTreeSet;
pub fn sequence(n:usize,edges:&[(usize,usize)])->Vec<usize>{
    let mut remaining:BTreeSet<_>=(0..n).collect();
    let(mut head,mut tail)=(Vec::new(),Vec::new());
    while !remaining.is_empty(){
        let degrees:Vec<_>=remaining.iter().map(|&v|{
            let out=edges.iter().filter(|&&(a,b)|a==v&&remaining.contains(&b)).count();
            let incoming=edges.iter().filter(|&&(a,b)|b==v&&remaining.contains(&a)).count();
            (v,out,incoming)
        }).collect();
        let chosen=if let Some(&(v,_,_))=degrees.iter().find(|(_,out,_)|*out==0){
            tail.insert(0,v);
            v
        }else if let Some(&(v,_,_))=degrees.iter().find(|(_,_,incoming)|*incoming==0){
            head.push(v);
            v
        }else{
            let &(v,_,_)=degrees.iter().min_by_key(|&&(v,out,incoming)|(std::cmp::Reverse(out as i64-incoming as i64),v)).unwrap();
            head.push(v);
            v
        };
        remaining.remove(&chosen);
    }
    head.extend(tail);
    head
}
pub struct Layering{
    pub heights:Vec<i64>,
    pub labels:Vec<usize>,
    pub before:i64,
    pub rounds:usize,
    pub promotions:Vec<(usize,usize,i64)>
}
pub fn assign(n:usize,edges:&[(usize,usize)],coffman:bool,width:usize,promotion:bool)->Layering{
    let mut upper=vec![Vec::new();n];
    let mut lower=vec![Vec::new();n];
    for &(a,b)in edges{
        upper[b].push(a);
        lower[a].push(b);
    }
    for a in &mut upper{
        a.sort();
    }
    for a in &mut lower{
        a.sort();
    }
    let mut labels=vec![0;n];
    let mut heights=vec![-1;n];
    if coffman{
        for k in 1..=n{
            let v=(0..n).filter(|&v|labels[v]==0&&upper[v].iter().all(|&u|labels[u]>0)).min_by_key(|&v|{
                let mut key:Vec<_>=upper[v].iter().map(|&u|labels[u]).collect();
                key.sort_by(|a,b|b.cmp(a));
                (key,v)
            }).unwrap();
            labels[v]=k;
        }
        let(mut current,mut count)=(0,0);
        for _ in 0..n{
            let v=(0..n).filter(|&v|heights[v]<0&&lower[v].iter().all(|&u|heights[u]>=0)).max_by_key(|&v|labels[v]).unwrap();
            if count==width||lower[v].iter().any(|&u|heights[u]==current){
                current+=1;
                count=0;
            }
            heights[v]=current;
            count+=1;
        }
    }else{
        fn height(v:usize,lower:&[Vec<usize>],heights:&mut[i64])->i64{
            if heights[v]>=0{
                return heights[v];
            }
            let mut h=0;
            for &u in &lower[v]{
                h=h.max(height(u,lower,heights)+1);
            }
            heights[v]=h;
            h
        }
        for v in 0..n{
            height(v,&lower,&mut heights);
        }
    }
    let before=edges.iter().map(|&(a,b)|heights[a]-heights[b]-1).sum();
    let mut rounds=0;
    let mut promotions=Vec::new();
    if promotion{
        fn promote(v:usize,upper:&[Vec<usize>],lower:&[Vec<usize>],h:&mut[i64])->i64{
            let mut diff=0;
            for &u in &upper[v]{
                if h[u]==h[v]+1{
                    diff+=promote(u,upper,lower,h);
                }
            }
            h[v]+=1;
            diff+lower[v].len()as i64-upper[v].len()as i64
        }
        loop{
            rounds+=1;
            let mut changed=false;
            for v in 0..n{
                if upper[v].is_empty(){
                    continue;
                }
                let saved=heights.clone();
                let diff=promote(v,&upper,&lower,&mut heights);
                if diff<0{
                    promotions.push((rounds,v,diff));
                    changed=true;
                }else{
                    heights=saved;
                }
            }
            if !changed{
                break;
            }
        }
    }
    Layering{
        heights,
        labels,
        before,
        rounds,
        promotions
    }
}
