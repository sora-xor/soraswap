import { CoverManagerModel } from "../cover/manager";
import { OptionsStackModel } from "../options/stack";
import { OraclePayload, PerpsEngineModel } from "../perps/engine";
import { RiskVaultModel } from "../shared/riskVault";
import { writeTelemetrySnapshot } from "../shared/telemetry";

export function runCrossProductStressScenario() {
  const vault = new RiskVaultModel();
  const perps = new PerpsEngineModel(vault);
  const options = new OptionsStackModel(vault);
  const cover = new CoverManagerModel(vault, 3);

  vault.deposit(1, 30_000);
  vault.deposit(2, 18_000);
  vault.deposit(3, 14_000);
  perps.heartbeat(2, false);
  options.configureAutomation(6, 1, false);
  cover.configureAutomation(6, 1, false);

  const oracle = (overrides: Partial<OraclePayload> = {}): OraclePayload => ({
    markPriceBps: 10_000,
    indexPriceBps: 9_950,
    confidenceBps: 80,
    oracleSlot: 10,
    currentSlot: 12,
    statusFlags: 0,
    attestationHash: 900,
    ...overrides
  });

  const marketId = perps.registerMarket({
    maxLeverageBps: 40_000,
    maintenanceMarginBps: 700,
    liquidationFeeBps: 900,
    openInterestCap: 60_000,
    fundingBps: 90,
    oracleStaleSlots: 4,
    backlogLimit: 6,
    utilisationClampBps: 8_800,
    liquidationStressLimit: 4
  });
  const perpsPosition = perps.openPosition("alice", marketId, 12_000, 3_200, oracle());

  const shoutTemplate = options.registerTemplate("shout", 10_100, 10_000, 450);
  const shoutSeries = options.createSeries(shoutTemplate, 40, 25_000, 500);
  const shoutPosition = options.buyShout("bob", shoutSeries, 5_500, 320, 2_600);

  const policyId = cover.registerPolicy({
    owner: "carol",
    lowerBound: 9_400,
    upperBound: 10_600,
    payoutAmount: 2_400,
    monitoringWindowSlots: 3,
    coveredNotional: 3_400,
    premiumPaid: 110
  });

  const beforeShock = vault.riskState();

  perps.applyFunding(perpsPosition, oracle({ markPriceBps: 11_200, indexPriceBps: 10_000, attestationHash: 901 }));
  options.recordShout(shoutPosition, 11_000);
  const shoutPayout = options.exerciseShout(shoutPosition, 11_300);
  cover.recordObservation(policyId, 11_200, { oracleSlot: 1, currentSlot: 1, statusFlags: 0 });
  cover.recordObservation(policyId, 11_350, { oracleSlot: 2, currentSlot: 2, statusFlags: 0 });
  cover.recordObservation(policyId, 11_600, { oracleSlot: 3, currentSlot: 5, statusFlags: 0 });
  const coverPayout = cover.routeClaim(policyId);
  const perpsClose = perps.closePosition(perpsPosition, oracle({ markPriceBps: 10_700, indexPriceBps: 10_050, attestationHash: 902 }));

  vault.assertInvariant();

  const afterShock = vault.riskState();
  const payload = {
    beforeShock,
    afterShock,
    payouts: {
      perps: perpsClose.payout,
      options: shoutPayout,
      cover: coverPayout
    },
    buckets: {
      perps: vault.bucketState(1),
      options: vault.bucketState(2),
      cover: vault.bucketState(3)
    },
    solvency: {
      totalDeposits: afterShock.totalDeposits,
      totalReservedCollateral: afterShock.totalReservedCollateral,
      totalSettledPayouts: afterShock.totalSettledPayouts,
      maxUtilisationBps: afterShock.maxUtilisationBps,
      unsafeBuckets: afterShock.unsafeBuckets
    }
  };

  writeTelemetrySnapshot("cross_product_shared_risk", payload);
  return payload;
}
