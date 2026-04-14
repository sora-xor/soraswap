use std::{collections::BTreeMap, env, process};

use iroha_sccp::{
    NexusBridgeFinalityProofV1, NexusCommitQcV1, NexusConsensusPhaseV1, NexusSccpMessageProofV1,
    RouteActivatePayloadV1, SccpHubCommitmentV1, SccpMerkleProofV1, SccpPayloadV1,
    TransferPayloadV1, canonical_sccp_payload_bytes, commitment_leaf_hash, payload_hash,
    sccp_message_id, sccp_message_kind, sccp_message_target_domain, SCCP_CODEC_TEXT_UTF8,
};
use norito::to_bytes;

fn usage() -> ! {
    eprintln!(
        "Usage:
  bridge_bundle_gen route-activate --chain-id ID --height N --nonce N --source-domain N --target-domain N --asset-key KEY --route ROUTE [--block-hash-hex HEX]
  bridge_bundle_gen transfer --chain-id ID --height N --nonce N --source-domain N --target-domain N --asset-home-domain N --asset-key KEY --route ROUTE --recipient ACCOUNT [--sender TEXT] [--block-hash-hex HEX]"
    );
    process::exit(2);
}

fn parse_args() -> (String, BTreeMap<String, String>) {
    let mut args = env::args().skip(1);
    let Some(kind) = args.next() else {
        usage();
    };

    let mut values = BTreeMap::new();
    while let Some(flag) = args.next() {
        if !flag.starts_with("--") {
            usage();
        }
        let Some(value) = args.next() else {
            usage();
        };
        values.insert(flag.trim_start_matches("--").to_owned(), value);
    }
    (kind, values)
}

fn required(values: &BTreeMap<String, String>, key: &str) -> String {
    values.get(key).cloned().unwrap_or_else(|| {
        eprintln!("missing required flag --{key}");
        usage();
    })
}

fn parse_u32(values: &BTreeMap<String, String>, key: &str) -> u32 {
    required(values, key).parse().unwrap_or_else(|_| {
        eprintln!("--{key} must be a valid u32");
        process::exit(2);
    })
}

fn parse_u64(values: &BTreeMap<String, String>, key: &str) -> u64 {
    required(values, key).parse().unwrap_or_else(|_| {
        eprintln!("--{key} must be a valid u64");
        process::exit(2);
    })
}

fn parse_u128(values: &BTreeMap<String, String>, key: &str) -> u128 {
    required(values, key).parse().unwrap_or_else(|_| {
        eprintln!("--{key} must be a valid u128");
        process::exit(2);
    })
}

fn hex32_from_string(hex: &str) -> [u8; 32] {
    let normalized = hex.trim_start_matches("0x");
    if normalized.len() != 64 || !normalized.as_bytes().iter().all(|b| b.is_ascii_hexdigit()) {
        eprintln!("--block-hash-hex must contain exactly 32 bytes of hex");
        process::exit(2);
    }
    let mut out = [0u8; 32];
    for (idx, chunk) in normalized.as_bytes().chunks(2).enumerate() {
        let text = std::str::from_utf8(chunk).expect("hex");
        out[idx] = u8::from_str_radix(text, 16).expect("hex byte");
    }
    out
}

fn derived_block_hash(height: u64, nonce: u64) -> [u8; 32] {
    let mut out = [0u8; 32];
    out[..8].copy_from_slice(&height.to_be_bytes());
    out[8..16].copy_from_slice(&nonce.to_be_bytes());
    out[16..24].copy_from_slice(&height.rotate_left(7).to_be_bytes());
    out[24..32].copy_from_slice(&nonce.rotate_left(13).to_be_bytes());
    out
}

fn bundle_from_payload(
    chain_id: String,
    height: u64,
    block_hash: [u8; 32],
    payload: SccpPayloadV1,
) -> NexusSccpMessageProofV1 {
    let commitment = SccpHubCommitmentV1 {
        version: 1,
        kind: sccp_message_kind(&payload),
        target_domain: sccp_message_target_domain(&payload),
        message_id: sccp_message_id(&payload),
        payload_hash: payload_hash(&canonical_sccp_payload_bytes(&payload)),
        parliament_certificate_hash: None,
    };
    let merkle_proof = SccpMerkleProofV1 { steps: Vec::new() };
    let commitment_root = commitment_leaf_hash(&commitment);
    let finality = NexusBridgeFinalityProofV1 {
        version: 1,
        chain_id,
        height,
        block_hash,
        commitment_root,
        block_header_bytes: vec![0x01, 0x02, 0x03],
        commit_qc: NexusCommitQcV1 {
            version: 1,
            phase: NexusConsensusPhaseV1::Commit,
            height,
            view: 0,
            epoch: 0,
            mode_tag: "iroha2-consensus::npos-sumeragi@v1".to_owned(),
            subject_block_hash: block_hash,
            validator_set_hash_version: 1,
            validator_public_keys: vec!["validator-1".to_owned()],
            validator_set_pops: vec![vec![0xAA]],
            signers_bitmap: vec![0x01],
            bls_aggregate_signature: vec![0xBB],
        },
    };
    NexusSccpMessageProofV1 {
        version: 1,
        commitment_root,
        commitment,
        merkle_proof,
        payload,
        finality_proof: to_bytes(&finality).expect("encode finality proof"),
    }
}

fn main() {
    let (kind, values) = parse_args();
    let chain_id = required(&values, "chain-id");
    let height = parse_u64(&values, "height");
    let nonce = parse_u64(&values, "nonce");
    let block_hash = values
        .get("block-hash-hex")
        .map(|value| hex32_from_string(value))
        .unwrap_or_else(|| derived_block_hash(height, nonce));

    let payload = match kind.as_str() {
        "route-activate" => SccpPayloadV1::RouteActivate(RouteActivatePayloadV1 {
            version: 1,
            source_domain: parse_u32(&values, "source-domain"),
            target_domain: parse_u32(&values, "target-domain"),
            nonce,
            asset_id_codec: SCCP_CODEC_TEXT_UTF8,
            asset_id: required(&values, "asset-key").into_bytes(),
            route_id_codec: SCCP_CODEC_TEXT_UTF8,
            route_id: required(&values, "route").into_bytes(),
        }),
        "transfer" => SccpPayloadV1::Transfer(TransferPayloadV1 {
            version: 1,
            source_domain: parse_u32(&values, "source-domain"),
            dest_domain: parse_u32(&values, "target-domain"),
            nonce,
            asset_home_domain: parse_u32(&values, "asset-home-domain"),
            asset_id_codec: SCCP_CODEC_TEXT_UTF8,
            asset_id: required(&values, "asset-key").into_bytes(),
            amount: parse_u128(&values, "amount"),
            sender_codec: SCCP_CODEC_TEXT_UTF8,
            sender: values
                .get("sender")
                .cloned()
                .unwrap_or_else(|| "synthetic:bridge".to_owned())
                .into_bytes(),
            recipient_codec: SCCP_CODEC_TEXT_UTF8,
            recipient: required(&values, "recipient").into_bytes(),
            route_id_codec: SCCP_CODEC_TEXT_UTF8,
            route_id: required(&values, "route").into_bytes(),
        }),
        _ => usage(),
    };

    let bundle = bundle_from_payload(chain_id, height, block_hash, payload);
    serde_json::to_writer_pretty(std::io::stdout(), &bundle).expect("serialize bundle");
    println!();
}
