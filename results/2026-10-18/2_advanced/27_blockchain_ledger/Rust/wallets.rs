use crate::hashing::digest;
#[derive(Clone)]
pub struct Wallet {
    pub name: String,
    pub secret: String,
    pub address: String
}
pub fn sign(secret: &str, index: usize, body: &str) -> String {
    digest(&format!("{secret}:{index}:{body}"))[..16].to_owned()
}
pub fn read_wallets() -> std::io::Result<Vec<Wallet>> {
    Ok(std::fs::read_to_string("input/wallets.txt")?.lines().map(|line| {
        let (name, secret) = line.split_once(' ').unwrap();
        Wallet {
            name: name.to_owned(),
            secret: secret.to_owned(),
            address: digest(&format!("addr:{secret}"))[..16].to_owned()
        }
    }).collect())
}
