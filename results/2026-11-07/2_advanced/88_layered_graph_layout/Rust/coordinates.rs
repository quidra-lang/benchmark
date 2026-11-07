use std::collections::{BTreeMap,BTreeSet};
use crate::crossing;
pub struct Coordinates{
    pub x:Vec<i64>,
    pub aligned:Vec<Vec<i64>>,
    pub blocks:Vec<usize>,
    pub widths:Vec<i64>,
    pub smallest:usize,
    pub conflicts:usize,
    pub left:Vec<i64>,
    pub right:Vec<i64>
}
fn pair(a:usize,b:usize)->(usize,usize){
    (a.min(b),a.max(b))
}
pub fn assign(n:usize,order:&[Vec<usize>],layer:&[usize],upper:&[Vec<usize>],lower:&[Vec<usize>],width:&[i64],vertical:bool,node_sep:i64,dummy_sep:i64)->Coordinates{
    let vertices=layer.len();
    let pos=crossing::positions(order,vertices);
    let left:Vec<_>=width.iter().map(|&w|if vertical{
        (w-1)/2
    }else{
        0
    }).collect();
    let right:Vec<_>=width.iter().zip(&left).map(|(&w,&l)|if vertical{
        w-1-l
    }else{
        0
    }).collect();
    let separation=|a:usize,b:usize|right[a]+left[b]+1+if a<n&&b<n{
        node_sep
    }else{
        dummy_sep
    };
    let mut marked=BTreeSet::new();
    for i in 0..order.len().saturating_sub(1){
        let(a,b)=(&order[i],&order[i+1]);
        let(mut k0,mut t)=(0,0);
        for l1 in 0..b.len(){
            let v=b[l1];
            let inner=v>=n&&upper[v][0]>=n;
            if inner||l1+1==b.len(){
                let k1=if inner{
                    pos[upper[v][0]]
                }else{
                    a.len()-1
                };
                for l in t..=l1{
                    let w=b[l];
                    for &u in &upper[w]{
                        if pos[u]<k0||pos[u]>k1{
                            marked.insert(pair(u,w));
                        }
                    }
                }
                t=l1+1;
                k0=k1;
            }
        }
    }
    let mut layouts=Vec::new();
    let mut blocks=Vec::new();
    let mut widths=Vec::new();
    let mut lows=Vec::new();
    let mut highs=Vec::new();
    for variant in 0..4{
        let down=variant>=2;
        let right_scan=variant%2==1;
        let q=|v:usize|if right_scan{
            order[layer[v]].len()-1-pos[v]
        }else{
            pos[v]
        };
        let mut root:Vec<_>=(0..vertices).collect();
        let mut align=root.clone();
        let mut layers:Vec<_>=(0..order.len()).collect();
        if down{
            layers.reverse();
        }
        for &i in layers.iter().skip(1){
            let mut scan=order[i].clone();
            if right_scan{
                scan.reverse();
            }
            let mut rho=-1i64;
            for v in scan{
                let mut reference=if down{
                    lower[v].clone()
                }else{
                    upper[v].clone()
                };
                reference.sort_by_key(|&u|q(u));
                if reference.is_empty(){
                    continue;
                }
                for m in [(reference.len()-1)/2,reference.len()/2].iter().copied(){
                    let u=reference[m];
                    if align[v]==v&&!marked.contains(&pair(u,v))&&rho<(q(u)as i64){
                        align[u]=v;
                        root[v]=root[u];
                        align[v]=root[v];
                        rho=q(u)as i64;
                    }
                }
            }
        }
        let roots:BTreeSet<_>=root.iter().copied().collect();
        blocks.push(roots.len());
        let mut edges:BTreeMap<(usize,usize),i64>=BTreeMap::new();
        for row in order{
            let mut scan=row.clone();
            if right_scan{
                scan.reverse();
            }
            for w in scan.windows(2){
                let(a,b)=(w[0],w[1]);
                let delta=if right_scan{
                    separation(b,a)
                }else{
                    separation(a,b)
                };
                edges.entry((root[a],root[b])).and_modify(|d|*d=(*d).max(delta)).or_insert(delta);
            }
        }
        let mut incoming=vec![Vec::new();vertices];
        let mut outgoing=vec![Vec::new();vertices];
        let mut degree=vec![0usize;vertices];
        for(&(a,b),&d)in &edges{
            incoming[b].push((a,d));
            outgoing[a].push((b,d));
            degree[b]+=1;
        }
        let mut ready:BTreeSet<_>=roots.iter().copied().filter(|&r|degree[r]==0).collect();
        let mut topology=Vec::new();
        while let Some(v)=ready.pop_first(){
            topology.push(v);
            for &(u,_)in &outgoing[v]{
                degree[u]-=1;
                if degree[u]==0{
                    ready.insert(u);
                }
            }
        }
        let mut y1=vec![0i64;vertices];
        for &v in &topology{
            y1[v]=incoming[v].iter().map(|&(u,d)|y1[u]+d).max().unwrap_or(0);
        }
        let mut y2=y1.clone();
        for &v in topology.iter().rev(){
            if let Some(minimum)=outgoing[v].iter().map(|&(u,d)|y2[u]-d).min(){
                y2[v]=y1[v].max(minimum);
            }
        }
        let x:Vec<_>=root.iter().map(|&r|if right_scan{
            -y2[r]
        }else{
            y2[r]
        }).collect();
        let lo=(0..vertices).map(|v|x[v]-left[v]).min().unwrap();
        let hi=(0..vertices).map(|v|x[v]+right[v]).max().unwrap();
        lows.push(lo);
        highs.push(hi);
        widths.push(hi-lo+1);
        layouts.push(x);
    }
    let smallest=(0..4).min_by_key(|&i|(widths[i],i)).unwrap();
    for i in 0..4{
        let delta=if i%2==0{
            lows[smallest]-lows[i]
        }else{
            highs[smallest]-highs[i]
        };
        for x in &mut layouts[i]{
            *x+=delta;
        }
    }
    let mut x=Vec::new();
    for v in 0..vertices{
        let mut values:Vec<_>=layouts.iter().map(|l|l[v]).collect();
        values.sort();
        x.push((values[1]+values[2]).div_euclid(2));
    }
    let minimum=(0..vertices).map(|v|x[v]-left[v]).min().unwrap();
    for x in &mut x{
        *x-=minimum;
    }
    Coordinates{
        x,
        aligned:layouts,
        blocks,
        widths,
        smallest,
        conflicts:marked.len(),
        left,
        right
    }
}
