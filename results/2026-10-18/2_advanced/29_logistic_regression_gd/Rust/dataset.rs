use std::{
    fs, io, collections::BTreeMap
};
#[derive(Clone)]
pub struct Example {
    pub id: String,
    pub values: Vec<f64>,
    pub label: usize
}
pub struct Settings {
    pub values: BTreeMap<String, Vec<String>>
}
impl Settings {
    pub fn read() -> io::Result<Self> {
        Ok(Self {
            values: fs::read_to_string("input/params.txt")?.lines().map(|l| {
                let mut f = l.split(' '); (f.next().unwrap().into(), f.map(str::to_owned).collect())
            }).collect()
        })
    }
    pub fn real(&self, k: &str, i: usize) -> f64 {
        self.values[k][i].parse().unwrap()
    }
    pub fn int(&self, k: &str, i: usize) -> usize {
        self.values[k][i].parse().unwrap()
    }
}
pub fn read_examples(name: &str) -> io::Result<(Vec<String>, Vec<Example>)> {
    let text = fs::read_to_string(format!("input/{name}.csv"))?;
    let mut lines = text.lines();
    let headers = lines.next().unwrap().split(',').collect::<Vec<_>>();
    let names = headers[1..headers.len()-1].iter().map(|s|s.to_string()).collect();
    let rows = lines.map(|l| {
        let f = l.split(',').collect::<Vec<_>>(); Example {
            id: f[0].into(),
            values: f[1..f.len()-1].iter().map(|s|s.parse().unwrap()).collect(),
            label: f.last().unwrap().parse().unwrap()
        }
    }).collect();
    Ok((names, rows))
}
pub fn expansion_tuples(d: usize, p: usize) -> Vec<Vec<usize>> {
    fn extend(out: &mut Vec<Vec<usize>>, prefix: Vec<usize>, start: usize, d: usize, left: usize) {
        if left == 0 {
            out.push(prefix);
            return
        }
        for i in start..d {
            let mut next = prefix.clone();
            next.push(i);
            extend(out, next, i, d, left-1);
        }
    }
    let mut out = vec![];
    for k in 1..=p {
        extend(&mut out, vec![], 0, d, k)
    }
    out
}
pub fn expanded_values(tuples: &[Vec<usize>], v: &[f64]) -> Vec<f64> {
    tuples.iter().map(|t| {
        let mut value = v[t[0]]; for &i in &t[1..] {
            value *= v[i]
        }
        value
    }).collect()
}
pub struct Statistics {
    pub means: Vec<f64>,
    pub sd: Vec<f64>
}
pub fn statistics(rows: &[Vec<f64>], q: usize) -> Statistics {
    let mut means = vec![];
    let mut sd = vec![];
    for j in 0..q {
        let mean = rows.iter().fold(0.0, |s, r|s+r[j])/rows.len() as f64;
        let squares = rows.iter().fold(0.0, |s, r|s+(r[j]-mean)*(r[j]-mean));
        means.push(mean);
        sd.push((squares/(rows.len()-1)as f64).sqrt());
    }
    Statistics {
        means,
        sd
    }
}
pub fn standardize(v: &[f64], s: &Statistics, q: usize) -> Vec<f64> {
    let mut out = vec![1.0];
    out.extend((0..q).map(|j|(v[j]-s.means[j])/s.sd[j]));
    out
}
