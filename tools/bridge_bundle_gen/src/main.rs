use std::{
    env, fs,
    io::{self, Read as _},
    process,
};

use iroha_sccp::{
    decode_taira_bridge_finality_proof, decode_taira_sccp_message_proof,
    sccp_taira_finality_network_id_v1,
    verified_sccp_message_taira_finality_proof_cryptographically_self_consistent, SccpNetworkV1,
    SccpPayloadV1, TairaSccpMessageProofV1, SCCP_CODEC_CANONICAL_TEXT, SCCP_CODEC_EVM_ADDRESS20,
    SCCP_CODEC_SOLANA_PUBKEY32, SCCP_CODEC_TRON_ADDRESS21, SCCP_DOMAIN_SORA,
    SCCP_TAIRA_BSC_XOR_ROUTE_ID_V1, SCCP_TAIRA_ETH_XOR_ROUTE_ID_V1, SCCP_TAIRA_SOL_XOR_ROUTE_ID_V1,
    SCCP_TAIRA_TRON_XOR_ROUTE_ID_V1, SCCP_TAIRA_XOR_ASSET_KEY_V1,
};

const USAGE: &str = "Usage:
  bridge_bundle_gen transfer --bundle PATH

Validates a state-derived Taira SCCP transfer bundle and emits canonical Norito
JSON. PATH may be a Torii `/v1/sccp/proofs/message/{message_id}` JSON response,
canonical Norito bytes, or - for stdin. This verifies cryptographic internal
consistency; destination trust still comes from the governed finality anchor.";

fn parse_bundle_path<I>(arguments: I) -> Result<String, String>
where
    I: IntoIterator<Item = String>,
{
    let mut arguments = arguments.into_iter();
    match arguments.next().as_deref() {
        Some("transfer") => {}
        Some(command) => return Err(format!("unsupported command `{command}`")),
        None => return Err("missing command".to_owned()),
    }

    match (arguments.next().as_deref(), arguments.next()) {
        (Some("--bundle"), Some(path)) => {
            if arguments.next().is_some() {
                return Err("unexpected trailing arguments".to_owned());
            }
            Ok(path)
        }
        (Some(flag), _) => Err(format!("expected --bundle, found `{flag}`")),
        (None, _) => Err("missing required flag --bundle".to_owned()),
    }
}

fn read_bundle(path: &str) -> Result<Vec<u8>, String> {
    if path == "-" {
        let mut bytes = Vec::new();
        io::stdin()
            .read_to_end(&mut bytes)
            .map_err(|error| format!("failed to read bundle from stdin: {error}"))?;
        Ok(bytes)
    } else {
        fs::read(path).map_err(|error| format!("failed to read bundle `{path}`: {error}"))
    }
}

fn decode_bundle(bytes: &[u8]) -> Result<TairaSccpMessageProofV1, String> {
    if bytes.starts_with(b"NRT0") {
        decode_taira_sccp_message_proof(bytes)
            .ok_or_else(|| "bundle is not canonical Norito SCCP proof bytes".to_owned())
    } else {
        norito::json::from_slice(bytes)
            .map_err(|error| format!("bundle is not typed SCCP proof JSON: {error}"))
    }
}

fn canonical_route(target: SccpNetworkV1) -> Result<(&'static str, u8), String> {
    match target {
        SccpNetworkV1::EthereumMainnet | SccpNetworkV1::EthereumSepolia => {
            Ok((SCCP_TAIRA_ETH_XOR_ROUTE_ID_V1, SCCP_CODEC_EVM_ADDRESS20))
        }
        SccpNetworkV1::BscMainnet | SccpNetworkV1::BscTestnet => {
            Ok((SCCP_TAIRA_BSC_XOR_ROUTE_ID_V1, SCCP_CODEC_EVM_ADDRESS20))
        }
        SccpNetworkV1::TronMainnet | SccpNetworkV1::TronNile | SccpNetworkV1::TronShasta => {
            Ok((SCCP_TAIRA_TRON_XOR_ROUTE_ID_V1, SCCP_CODEC_TRON_ADDRESS21))
        }
        SccpNetworkV1::SolanaTestnet => {
            Ok((SCCP_TAIRA_SOL_XOR_ROUTE_ID_V1, SCCP_CODEC_SOLANA_PUBKEY32))
        }
        SccpNetworkV1::SoraTaira => {
            Err("SCCP outbound transfer target must be an external profile".to_owned())
        }
    }
}

fn validate_transfer_bundle(bundle: &TairaSccpMessageProofV1) -> Result<(), String> {
    let finality = decode_taira_bridge_finality_proof(&bundle.finality_proof)
        .ok_or_else(|| "bundle finality proof is not canonical Norito".to_owned())?;
    if finality.finality_artifact.height_context.network_id != sccp_taira_finality_network_id_v1() {
        return Err("bundle finality proof is not bound to the Taira NetworkId".to_owned());
    }
    if verified_sccp_message_taira_finality_proof_cryptographically_self_consistent(&bundle)
        .is_none()
    {
        return Err(
            "SCCP bundle failed commitment, inclusion, or finality verification".to_owned(),
        );
    }

    let SccpPayloadV1::Transfer(transfer) = &bundle.payload;
    let target = bundle.commitment.context.lane.target;
    let (expected_route_id, expected_recipient_codec) = canonical_route(target)?;
    if bundle.commitment.context.lane.source != SccpNetworkV1::SoraTaira
        || transfer.source_domain != bundle.commitment.context.lane.source.domain_id()
        || transfer.dest_domain != target.domain_id()
        || transfer.route_revision == 0
        || transfer.asset_home_domain != SCCP_DOMAIN_SORA
        || transfer.asset_id_codec != SCCP_CODEC_CANONICAL_TEXT
        || transfer.asset_id != SCCP_TAIRA_XOR_ASSET_KEY_V1.as_bytes()
        || transfer.sender_codec != SCCP_CODEC_CANONICAL_TEXT
        || transfer.recipient_codec != expected_recipient_codec
        || transfer.route_id_codec != SCCP_CODEC_CANONICAL_TEXT
        || transfer.route_id != expected_route_id.as_bytes()
    {
        return Err("SCCP bundle does not use the canonical Taira XOR route and codecs".to_owned());
    }

    Ok(())
}

fn main() {
    let path = parse_bundle_path(env::args().skip(1)).unwrap_or_else(|error| {
        eprintln!("{error}\n\n{USAGE}");
        process::exit(2);
    });
    let bytes = read_bundle(&path).unwrap_or_else(|error| {
        eprintln!("{error}");
        process::exit(1);
    });
    let bundle = decode_bundle(&bytes).unwrap_or_else(|error| {
        eprintln!("failed to decode bundle: {error}");
        process::exit(1);
    });
    validate_transfer_bundle(&bundle).unwrap_or_else(|error| {
        eprintln!("invalid transfer bundle: {error}");
        process::exit(1);
    });
    let json = norito::json::to_json_pretty(&bundle).unwrap_or_else(|error| {
        eprintln!("failed to serialize bundle: {error}");
        process::exit(1);
    });
    println!("{json}");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parser_accepts_only_the_transfer_bundle_surface() {
        assert_eq!(
            parse_bundle_path([
                "transfer".to_owned(),
                "--bundle".to_owned(),
                "bundle.nrt".to_owned()
            ]),
            Ok("bundle.nrt".to_owned())
        );
        assert!(parse_bundle_path([
            "route-activate".to_owned(),
            "--bundle".to_owned(),
            "bundle.nrt".to_owned()
        ])
        .is_err());
        assert!(parse_bundle_path([
            "transfer".to_owned(),
            "--bundle".to_owned(),
            "bundle.nrt".to_owned(),
            "--height".to_owned(),
            "1".to_owned()
        ])
        .is_err());
    }

    #[test]
    fn state_derived_json_and_binary_bundles_validate() {
        let fixture = iroha_sccp::sccp_exact_outbound_test_fixture_for_nonce_v1(42);
        validate_transfer_bundle(&fixture.bundle).expect("exact state-derived fixture");

        let json = norito::json::to_json_pretty(&fixture.bundle).expect("fixture JSON");
        let from_json = decode_bundle(json.as_bytes()).expect("typed fixture JSON");
        assert_eq!(from_json, fixture.bundle);

        let binary = norito::to_bytes(&fixture.bundle).expect("fixture Norito bytes");
        let from_binary = decode_bundle(&binary).expect("canonical fixture bytes");
        assert_eq!(from_binary, fixture.bundle);
    }
}
