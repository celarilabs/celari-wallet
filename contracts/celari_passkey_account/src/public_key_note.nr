use aztec::{macros::notes::note, protocol_types::traits::Packable};

// Stores a P256 public key as raw byte arrays (x, y coordinates)
// Using [u8; 32] instead of Field because P256 coordinates are 256-bit
// and can exceed the BN254 field modulus (~254-bit)
//
// Custom Packable packs into 4 Fields (under the 10-field note limit):
// - Field[0] = x[0..31] (31 bytes packed via base-256)
// - Field[1] = x[31] (last byte)
// - Field[2] = y[0..31]
// - Field[3] = y[31]
#[note]
#[derive(Eq)]
pub struct PublicKeyNote {
    pub x: [u8; 32],
    pub y: [u8; 32],
}

impl Packable for PublicKeyNote {
    let N: u32 = 4;

    fn pack(self) -> [Field; Self::N] {
        let mut x: Field = 0;
        let mut y: Field = 0;
        let mut mul: Field = 1;

        // Pack bytes 0-30 into a single Field each (31 bytes < 254 bits)
        for i in 1..32 {
            let byte_x: Field = self.x[31 - i] as Field;
            x = x + (byte_x * mul);
            let byte_y: Field = self.y[31 - i] as Field;
            y = y + (byte_y * mul);
            mul *= 256;
        }

        // Last byte stored separately (256^31 would exceed Field capacity)
        let last_x = self.x[31] as Field;
        let last_y = self.y[31] as Field;

        [x, last_x, y, last_y]
    }

    fn unpack(packed_note: [Field; Self::N]) -> Self {
        let mut x: [u8; 32] = [0; 32];
        let mut y: [u8; 32] = [0; 32];

        let part_x: [u8; 32] = packed_note[0].to_be_bytes();
        for i in 0..31 {
            x[i] = part_x[i + 1];
        }
        x[31] = packed_note[1].to_be_bytes::<32>()[31];

        let part_y: [u8; 32] = packed_note[2].to_be_bytes();
        for i in 0..31 {
            y[i] = part_y[i + 1];
        }
        y[31] = packed_note[3].to_be_bytes::<32>()[31];

        PublicKeyNote { x, y }
    }
}
