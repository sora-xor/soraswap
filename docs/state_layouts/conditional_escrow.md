# Conditional Escrow State Layout

Singleton state:
- `EscrowInitialized`
- `EscrowOwner`
- `EscrowContractId`
- `EscrowContractBound`

Escrow maps:
- `EscrowMaker`
- `EscrowTaker`
- `EscrowAsset`
- `EscrowAmount`
- `EscrowExpirySlot`
- `EscrowConditionCode`
- `EscrowStatus`
- `EscrowAcceptedSlot`
- `EscrowRefundedSlot`

Status values:
- `1=open`
- `2=accepted`
- `3=cancelled`
- `4=expired_refunded`
