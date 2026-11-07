fn main() {
    let matrix = [
        [125, 340, 78, 912, 456],
        [603, 27, 819, 150, 384],
        [0, 765, 231, 498, 62],
        [947, 113, 586, 39, 720],
    ];
    let mut columns = [0; 5];
    let mut total = 0;
    for row in matrix {
        let mut sum = 0;
        for (j, n) in row.iter().enumerate() {
            print!("{:6}", n);
            sum += n;
            columns[j] += n;
        }
        total += sum;
        println!("{:6}", sum);
    }
    for n in columns {
        print!("{:6}", n);
    }
    println!("{:6}", total);
}
