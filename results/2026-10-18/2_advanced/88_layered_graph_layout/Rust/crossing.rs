#[derive(Clone)] pub struct Segment{
    pub p:usize,
    pub q:usize,
    pub edge:usize
}
pub fn positions(order:&[Vec<usize>],n:usize)->Vec<usize>{
    let mut pos=vec![0;n];
    for layer in order{
        for(i,&v)in layer.iter().enumerate(){
            pos[v]=i;
        }
    }
    pos
}
pub fn count(segments:&[Segment],pos:&[usize],width:usize)->usize{
    let mut pairs:Vec<_>=segments.iter().map(|s|(pos[s.p],pos[s.q])).collect();
    pairs.sort();
    let mut c=1;
    while c<width{
        c*=2;
    }
    let mut tree=vec![0usize;2*c-1];
    let mut count=0;
    for(_,q)in pairs{
        let mut k=q+c-1;
        tree[k]+=1;
        while k>0{
            if k%2==1{
                count+=tree[k+1];
            }
            k=(k-1)/2;
            tree[k]+=1;
        }
    }
    count
}
pub fn brute(segments:&[Segment],pos:&[usize])->usize{
    let mut count=0;
    for i in 0..segments.len(){
        for j in i+1..segments.len(){
            let(a,b)=(&segments[i],&segments[j]);
            if(pos[a.p]<pos[b.p]&&pos[a.q]>pos[b.q])||(pos[a.p]>pos[b.p]&&pos[a.q]<pos[b.q]){
                count+=1;
            }
        }
    }
    count
}
pub fn total(gaps:&[Vec<Segment>],order:&[Vec<usize>],n:usize)->usize{
    let pos=positions(order,n);
    gaps.iter().enumerate().map(|(i,g)|count(g,&pos,order[i+1].len())).sum()
}
pub fn adjacent(v:usize,w:usize,upper:&[Vec<usize>],lower:&[Vec<usize>],pos:&[usize])->usize{
    upper[v].iter().map(|&a|upper[w].iter().filter(|&&b|pos[a]>pos[b]).count()).sum::<usize>()+lower[v].iter().map(|&a|lower[w].iter().filter(|&&b|pos[a]>pos[b]).count()).sum::<usize>()
}
