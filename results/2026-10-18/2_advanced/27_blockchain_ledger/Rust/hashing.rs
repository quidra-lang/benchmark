pub fn digest(text: &str) -> String {
    [(1000003i64, 11), (1500007, 23), (2750159, 37), (4194301, 53)].iter().map(|&(base, initial)| {
        let mut h = initial;
        for c in text.bytes().map(i64::from).chain([text.len() as i64, 0, 0]) {
            h = (h*base+c)%2147483647;
        }
        format!("{h:08x}")
    }).collect()
}
pub fn merkle_root(mut hashes: Vec<String>) -> String {
    while hashes.len()>1 {
        if hashes.len()%2 == 1 {
            hashes.push(hashes.last().unwrap().clone());
        }
        hashes = hashes.chunks(2).map(|p| digest(&(p[0].clone()+&p[1]))).collect();
    }
    hashes.remove(0)
}
pub fn short(s: &str) -> &str {
    &s[..8]
}
