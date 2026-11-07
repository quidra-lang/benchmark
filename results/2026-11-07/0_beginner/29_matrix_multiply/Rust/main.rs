fn main() {
    let a = [[3, -2, 5, 1], [-4, 7, 0, 6], [2, 9, -8, -3]];
    let b = [[1, 4], [-5, 2], [6, -1], [0, 7]];
    for i in 0..3 {
        let mut row = [0; 2];
        for j in 0..2 {
            let sum: i32 = (0..4).map(|k| a[i][k] * b[k][j]).sum();
            row[j] = sum;
        }
        for value in row {
            print!("{:5}", value);
        }
        println!();
    }
}
