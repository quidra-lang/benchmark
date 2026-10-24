fn main() {
    let mut systems = [vec![vec![2.0, -1.0, 3.0, 7.0], vec![4.0, 1.0, -2.0, 3.0], vec![-3.0, 5.0,
        1.0, -4.0]], vec![vec![1.0, 3.0, -2.0, 4.0, 6.0], vec![5.0, -2.0, 1.0, 3.0, -7.0], vec![-2.0, 4.0,
        6.0, -1.0, 9.0], vec![3.0, 1.0, -4.0, 2.0, 5.0]]];
    for (s, a) in systems.iter_mut().enumerate() {
        let n = a.len();
        let mut x = vec![0.0_f64; n];
        for k in 0..n {
            let mut pivot = k;
            for i in k + 1..n {
                if f64::abs(a[i][k]) > f64::abs(a[pivot][k]) {
                    pivot = i;
                }
            }
            a.swap(k, pivot);
            for i in k + 1..n {
                let f = a[i][k] / a[k][k];
                for j in k..=n {
                    a[i][j] = a[i][j] - f * a[k][j];
                }
            }
        }
        for i in (0..n).rev() {
            let mut sum = a[i][n];
            for j in i + 1..n {
                sum = sum - a[i][j] * x[j];
            }
            x[i] = sum / a[i][i];
        }
        println!("system {}:", s + 1);
        for (i, value) in x.iter().enumerate() {
            println!("x{} = {:.4}", i + 1, value);
        }
    }
}
