use crate::rational::Fraction as F;
use crate::tableau::Tableau;
pub fn phase(tableau: &mut Tableau, costs: &[F], candidates: &[usize], columns: &[String], rows: &[String], constant: F, sign: F, level: usize, log: &mut Vec<String>) -> (usize, Option<usize>) {
    let mut iterations = 0;
    loop {
        let reduced = tableau.reduced(costs);
        let q = match candidates.iter().copied().find(|&k| reduced[k] < F::zero()) { Some(q) => q, None => return (iterations, None) };
        let p = (0..tableau.t.len()).filter(|&i| tableau.t[i][q] > F::zero()).min_by_key(|&i| (tableau.beta[i] / tableau.t[i][q], tableau.basis[i]));
        if let Some(p) = p {
            let leaving = tableau.basis[p];
            let ratio = tableau.beta[p] / tableau.t[p][q];
            let r = reduced[q];
            tableau.pivot(p, q);
            iterations += 1;
            if level >= 1 { log.push(format!("PIVOT {} enter {} reduced {} leave {} row {} ratio {} objective {}", iterations, columns[q], r, columns[leaving], rows[p], ratio, constant + sign * tableau.value(costs))); }
        } else { return (iterations, Some(q)); }
    }
}
