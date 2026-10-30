use std::io::{self, BufRead};

fn hash_hex(hex: &str) {
    let hex = hex.strip_prefix("0x").unwrap_or(hex);
    assert!(hex.len() % 2 == 0, "odd-length hex");
    let input: Vec<u8> = (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).expect("invalid hex"))
        .collect();
    println!("0x{}", blake3_servil::convenience::hash(&input).to_hex());
}

fn main() {
    blake3_servil::initialize();
    if let Some(hex) = std::env::args().nth(1) {
        hash_hex(&hex);
    } else {
        for line in io::stdin().lock().lines() {
            hash_hex(&line.expect("stdin"));
        }
    }
}
