fn det(a: &[Vec<i32>]) -> i32 {
    if a.len() == 1 {
        return a[0][0];
    }
    let mut result = 0;
    for j in 0..a.len() {
        let minor: Vec<Vec<i32>> = a[1..]
            .iter()
            .map(|row| {
                row.iter()
                    .enumerate()
                    .filter_map(|(c, &v)| (c != j).then_some(v))
                    .collect()
            })
            .collect();
        let term = a[0][j] * det(&minor);
        result += if j % 2 == 0 { term } else { -term };
    }
    result
}

fn main() {
    let matrices = [
        vec![vec![2, -3, 1], vec![5, 4, -2], vec![-1, 6, 3]],
        vec![
            vec![3, 0, -2, 5],
            vec![1, 4, 7, -3],
            vec![-6, 2, 1, 8],
            vec![9, -5, 3, 2],
        ],
        vec![
            vec![4, -1, 7, 0, -3],
            vec![2, 8, -5, 6, 1],
            vec![-9, 3, 2, -4, 5],
            vec![6, 0, -7, 3, -2],
            vec![1, -6, 4, 9, 8],
        ],
    ];
    for a in matrices {
        println!("det({}x{}) = {}", a.len(), a.len(), det(&a));
    }
}
