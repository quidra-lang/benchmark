fn main() {
    let a = [[3, -2, 5, 1], [-4, 7, 0, 6], [2, 9, -8, -3]];
    let b = [[1, 4], [-5, 2], [6, -1], [0, 7]];
    for i in 0..3 {
        for j in 0..2 {
            let mut sum = 0;
            for k in 0..4 {
                sum += a[i][k] * b[k][j];
            }
            print!("{:5}", sum);
        }
        println!();
    }
}
