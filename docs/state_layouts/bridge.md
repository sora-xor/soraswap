# SCCP Bridge State Layout

Scalar state:
- `BridgeInitialized`
- `BridgeOwner`
- `BridgeProofAuthority`
- `RegistryEnabled`
- `ListingFeeAsset`
- `TreasuryAccount`
- `ListingFeeAmount`

Map state:
- `RegisteredAsset[asset_key] -> AssetDefinitionId`
- `AssetHomeDomain[asset_key] -> int`
- `AssetDecimals[asset_key] -> int`
- `AssetListingPaid[asset_key] -> int`
- `AssetVaultAccount[asset_key] -> AccountId`
- `RouteOwner[route] -> AccountId`
- `RouteAssetKey[route] -> Name`
- `RouteRemoteDomain[route] -> int`
- `RouteLocalAsset[route] -> AssetDefinitionId`
- `RouteVaultAccount[route] -> AccountId`
- `RouteEnabled[route] -> int`
- `RouteGoverned[route] -> int`
- `RouteGovernanceMessage[route] -> Name`
- `NextOutboundNonce[route] -> int`
- `OutboundRoute[transfer] -> Name`
- `OutboundSender[transfer] -> AccountId`
- `OutboundRecipient[transfer] -> Name`
- `OutboundAmount[transfer] -> int`
- `OutboundNonce[transfer] -> int`
- `OutboundStatus[transfer] -> int`
- `ConsumedInbound[message_id] -> int`

View tuple fields returned by `listing_config()`:
- `soraswap_bridge_listing_fee_asset`
- `soraswap_bridge_treasury_account`
- `soraswap_bridge_listing_fee_amount`
- `soraswap_bridge_registry_enabled`

View tuple fields returned by `bridge_authorities()`:
- `soraswap_bridge_owner`
- `soraswap_bridge_proof_authority`

View tuple fields returned by `mirror_asset(asset_key)`:
- `soraswap_bridge_asset_registered`
- `soraswap_bridge_asset_home_domain`
- `soraswap_bridge_asset_decimals`
- `soraswap_bridge_asset_listing_paid`

View tuple fields returned by `mirror_route(route)`:
- `soraswap_bridge_route_registered`
- `soraswap_bridge_route_remote_domain`
- `soraswap_bridge_route_enabled`
- `soraswap_bridge_route_next_outbound_nonce`

View tuple fields returned by `mirror_outbound(transfer)`:
- `soraswap_bridge_outbound_registered`
- `soraswap_bridge_outbound_amount`
- `soraswap_bridge_outbound_nonce`
- `soraswap_bridge_outbound_status`

Notes:
- Asset keys and route ids are logical names in the Kotodama surface. The byte-level SCCP asset id, route id, sender, and recipient codecs are defined in `../iroha`.
- `ListingFeeAmount` records the one-time Nexus registry listing fee paid in `xor#universal`.
- `ConsumedInbound` is the replay/nullifier map for inbound messages.
- `BridgeProofAuthority` gates proof-managed route activation and inbound settlement. Bootstrap defaults it to the deployment authority unless `SORASWAP_BRIDGE_PROOF_AUTHORITY` is set.
