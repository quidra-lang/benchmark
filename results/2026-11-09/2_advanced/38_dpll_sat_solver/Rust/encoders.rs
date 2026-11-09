use crate::Formula;

pub fn queens(n: usize) -> Formula {
    let mut clauses: Vec<Vec<i64>> = (0..n).map(|r| (1..=n).map(|c| (r * n + c) as i64).collect()).collect();
    for a in 1..=n * n {
        for b in a + 1..=n * n {
            let (ar, ac) = ((a - 1) / n, (a - 1) % n);
            let (br, bc) = ((b - 1) / n, (b - 1) % n);
            if ar == br || ac == bc || ar.abs_diff(br) == ac.abs_diff(bc) { clauses.push(vec![-(a as i64), -(b as i64)]); }
        }
    }
    Formula { variables: n * n, clauses }
}

pub fn pigeon(pigeons: usize, holes: usize) -> Formula {
    let mut clauses: Vec<Vec<i64>> = (0..pigeons).map(|i| (1..=holes).map(|j| (i * holes + j) as i64).collect()).collect();
    for i in 0..pigeons {
        for a in 1..=holes {
            for b in a + 1..=holes {
                clauses.push(vec![-((i * holes + a) as i64), -((i * holes + b) as i64)]);
            }
        }
    }
    for j in 1..=holes {
        for a in 0..pigeons {
            for b in a + 1..pigeons {
                clauses.push(vec![-((a * holes + j) as i64), -((b * holes + j) as i64)]);
            }
        }
    }
    Formula { variables: pigeons * holes, clauses }
}

pub fn coloring(vertices: usize, edges: &[(usize, usize)], colors: usize) -> Formula {
    let mut clauses: Vec<Vec<i64>> = (0..vertices).map(|x| (1..=colors).map(|c| (x * colors + c) as i64).collect()).collect();
    for x in 0..vertices {
        for a in 1..=colors {
            for b in a + 1..=colors {
                clauses.push(vec![-((x * colors + a) as i64), -((x * colors + b) as i64)]);
            }
        }
    }
    for &(u, w) in edges {
        for c in 1..=colors { clauses.push(vec![-(((u - 1) * colors + c) as i64), -(((w - 1) * colors + c) as i64)]); }
    }
    Formula { variables: vertices * colors, clauses }
}

pub fn positions(model: &[bool], rows: usize, width: usize) -> Vec<usize> {
    (0..rows).map(|r| (1..=width).find(|&c| model[r * width + c]).unwrap()).collect()
}
