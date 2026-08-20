/// Returns the IEEE CRC32 checksum for `bytes`.
///
/// The implementation is table-free to keep the stage 6 dependency surface
/// small and deterministic.
pub fn crc32_ieee(bytes: &[u8]) -> u32 {
    let mut crc = 0xffff_ffff_u32;
    for &byte in bytes {
        crc ^= u32::from(byte);
        for _ in 0..8 {
            let mask = 0_u32.wrapping_sub(crc & 1);
            crc = (crc >> 1) ^ (0xedb8_8320 & mask);
        }
    }
    !crc
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crc32_matches_standard_vector() {
        assert_eq!(crc32_ieee(b"123456789"), 0xcbf4_3926);
    }
}
