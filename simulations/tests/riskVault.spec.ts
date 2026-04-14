import { RiskVaultModel } from "../shared/riskVault";

describe("RiskVaultModel", () => {
  test("tracks bucket accounting and lock/release idempotence", () => {
    const vault = new RiskVaultModel();

    vault.deposit(1, 10_000);
    vault.lockLiability(1, 11, { notional: 5_000, collateral: 400, backlog: 1 });
    vault.lockLiability(1, 11, { notional: 6_000, collateral: 500, backlog: 2 });

    const locked = vault.bucketState(1);
    expect(locked.outstandingNotional).toBe(6_000);
    expect(locked.reservedCollateral).toBe(500);
    expect(locked.requiredCollateral).toBe(900);
    expect(locked.surplus).toBe(9_100);
    expect(locked.automation.backlog).toBe(2);

    vault.releaseLiability(1, 11, 0);
    const released = vault.bucketState(1);
    expect(released.outstandingNotional).toBe(0);
    expect(released.reservedCollateral).toBe(0);

    vault.releaseLiability(1, 11, 0);
    expect(vault.bucketState(1)).toEqual(released);
  });

  test("enforces payout caps and utilisation guards", () => {
    const payoutVault = new RiskVaultModel();
    payoutVault.deposit(3, 10_000);
    payoutVault.lockLiability(3, 7, { notional: 4_000, collateral: 2_800 });

    const settled = payoutVault.settlePayout(3, 7, 4_000);
    expect(settled).toBe(2_800);
    expect(payoutVault.exposureState(3, 7).settledPayout).toBe(2_800);

    const guardedVault = new RiskVaultModel({
      2: { utilisationCapBps: 5_000 }
    });
    guardedVault.deposit(2, 10_000);

    expect(() => {
      guardedVault.lockLiability(2, 3, { notional: 6_000, collateral: 6_000 });
    }).toThrow("bucket 2 utilisation guard");
  });
});
