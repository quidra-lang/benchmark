use std::collections::BTreeMap;
use crate::doc_builder::{Document,Doc};
pub fn tree(d:&Document,depth:usize,modes:&BTreeMap<usize,&'static str>,out:&mut Vec<String>){
    let prefix=" ".repeat(2*depth);
    match d.as_ref(){
        Doc::Concat(parts)=>{
            for p in parts{
                tree(p,depth,modes,out);
            }
        },Doc::Text(s)=>out.push(format!("{}text \"{}\"",prefix,s)),Doc::Suffix(s)=>out.push(format!("{}suffix \"{}\"",prefix,s)),Doc::IfBreak(a,b)=>out.push(format!("{}if_break \"{}\" \"{}\"",prefix,a,b)),Doc::Group(id,child)=>{
            out.push(format!("{}group {}",prefix,modes[id]));
            tree(child,depth+1,modes,out);
        },Doc::Nest(n,child)=>{
            out.push(format!("{}nest {}",prefix,n));
            tree(child,depth+1,modes,out);
        },Doc::Align(child)=>{
            out.push(format!("{}align",prefix));
            tree(child,depth+1,modes,out);
        },Doc::Line=>out.push(format!("{}line",prefix)),Doc::Softline=>out.push(format!("{}softline",prefix)),Doc::Hardline=>out.push(format!("{}hardline",prefix)),Doc::BreakParent=>out.push(format!("{}break_parent",prefix))
    }
}
pub fn diff(a:&[String],b:&[String])->Vec<String>{
    let(n,m)=(a.len(),b.len());
    let mut lcs=vec![vec![0usize;m+1];n+1];
    for i in(0..n).rev(){
        for j in(0..m).rev(){
            lcs[i][j]=if a[i]==b[j]{
                lcs[i+1][j+1]+1
            }else{
                lcs[i+1][j].max(lcs[i][j+1])
            };
        }
    }
    let(mut i,mut j,mut deleted,mut inserted)=(0,0,0,0);
    let mut hunks=Vec::new();
    while i<n||j<m{
        if i<n&&j<m&&a[i]==b[j]{
            i+=1;
            j+=1;
            continue;
        }
        let(i0,j0)=(i,j);
        let(mut d,mut e)=(0,0);
        let mut lines=Vec::new();
        while i<n||j<m{
            if i<n&&j<m&&a[i]==b[j]{
                break;
            }
            if j==m||i<n&&lcs[i+1][j]>=lcs[i][j+1]{
                lines.push(format!("-{}",a[i]));
                i+=1;
                d+=1;
            }else{
                lines.push(format!("+{}",b[j]));
                j+=1;
                e+=1;
            }
        }
        deleted+=d;
        inserted+=e;
        hunks.push((i0,j0,d,e,lines));
    }
    let mut result=vec![format!("hunks={} deleted={} inserted={}",hunks.len(),deleted,inserted)];
    for(i,j,d,e,lines)in hunks{
        result.push(format!("@@ -{},{} +{},{} @@",if d>0{
            i+1
        }else{
            i
        },d,if e>0{
            j+1
        }else{
            j
        },e));
        result.extend(lines);
    }
    result
}
