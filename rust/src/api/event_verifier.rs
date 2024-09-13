use hex::decode;
use secp256k1::{schnorr::Signature, Message, Secp256k1, XOnlyPublicKey};

#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

#[test]
fn schnorr_signature_test_valid() {
    let pub_key_hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
    let event_id = "a47c525970d21575c67e6f1e47674f1b82fc7edabb098fac4be21bb05425b389";
    let signature_hex = "b03ddc4930776698d39caa3df0cd887558ceea281eb9e2524daaba324906b2e3efc06f2f65a7fbba95c0b3ce9817df81f53d2d8da0124028446b0cc3a59ae6d9";

    let result = verify_schnorr_signature(pub_key_hex, event_id, signature_hex);
    print!("result: ${result}");

    assert!(result);
}

#[test]
fn schnorr_signature_test_invalid() {
    let pub_key_hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
    let event_id = "a47c525970d21575c67e6f1e47674f1b82fc7edabb098fac4be21bb05425b389";
    // invalid sig
    let signature_hex = "a03ddc4930776698d39caa3df0cd887558ceea281eb9e2524daaba324906b2e3efc06f2f65a7fbba95c0b3ce9817df81f53d2d8da0124028446b0cc3a59ae6d9";

    let result = verify_schnorr_signature(pub_key_hex, event_id, signature_hex);
    print!("result: ${result}");

    assert!(!result);
}

pub fn verify_schnorr_signature(
    pub_key_hex: &str,
    event_id_hex: &str,
    signature_hex: &str,
) -> bool {
    let secp = Secp256k1::verification_only();

    let pub_key_bytes = match decode(pub_key_hex) {
        Ok(bytes) => bytes,
        Err(_) => {
            eprintln!("Invalid public key hex");
            return false;
        }
    };

    let event_id_bytes = match decode(event_id_hex) {
        Ok(bytes) => bytes,
        Err(_) => {
            eprintln!("Invalid event ID hex");
            return false;
        }
    };

    let signature_bytes = match decode(signature_hex) {
        Ok(bytes) => bytes,
        Err(_) => {
            eprintln!("Invalid signature hex");
            return false;
        }
    };

    if event_id_bytes.len() != 32 {
        eprintln!("Event ID is not 32 bytes");
        return false;
    }

    if pub_key_bytes.len() != 32 {
        eprintln!("Public key is not 32 bytes");
        return false;
    }

    if signature_bytes.len() != 64 {
        eprintln!("Signature is not 64 bytes");
        return false;
    }

    let pub_key = match XOnlyPublicKey::from_slice(&pub_key_bytes) {
        Ok(key) => key,
        Err(_) => {
            eprintln!("Invalid public key format");
            return false;
        }
    };

    let signature = match Signature::from_slice(&signature_bytes) {
        Ok(sig) => sig,
        Err(_) => {
            eprintln!("Invalid signature format");
            return false;
        }
    };

    let message = match Message::from_digest_slice(&event_id_bytes) {
        Ok(msg) => msg,
        Err(_) => {
            eprintln!("Invalid message format");
            return false;
        }
    };

    let verification_result = secp.verify_schnorr(&signature, &message, &pub_key);
    //println!("Verification result: {:?}", verification_result);

    return verification_result.is_ok();
}
