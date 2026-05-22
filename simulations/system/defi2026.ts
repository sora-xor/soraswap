import { writeTelemetrySnapshot } from "../shared/telemetry";

type Intent = {
  owner: string;
  amountIn: number;
  minOut: number;
  solverFeeBps: number;
  deadlineSlot: number;
  status: "open" | "filled" | "cancelled";
  solver?: string;
  amountOut?: number;
};

type Vault = {
  underlying: string;
  shares: number;
  assets: number;
  pendingRedeems: number;
};

type Operator = {
  service: string;
  bonded: number;
  minBond: number;
  healthBps: number;
  jailed: boolean;
  feesAccrued: number;
};

type MarginAccount = {
  collateral: number;
  exposure: number;
  healthBps: number;
  liquidations: number;
};

type RwaMarket = {
  navPerShare: number;
  totalShares: number;
  redemptionQueue: number;
  frozen: boolean;
};

function healthBps(account: Pick<MarginAccount, "collateral" | "exposure">): number {
  if (account.exposure === 0) {
    return 10_000;
  }
  return Math.floor((account.collateral * 10_000) / account.exposure);
}

export function runDefi2026Scenario() {
  const intent: Intent = {
    owner: "alice",
    amountIn: 1_000,
    minOut: 970,
    solverFeeBps: 25,
    deadlineSlot: 50,
    status: "open"
  };
  if (intent.solverFeeBps > 10_000) {
    throw new Error("solver fee overflow");
  }
  intent.solver = "solver-1";
  intent.amountOut = 990;
  intent.status = intent.amountOut >= intent.minOut ? "filled" : "cancelled";

  const vault: Vault = {
    underlying: "n3x",
    shares: 0,
    assets: 0,
    pendingRedeems: 0
  };
  vault.assets += 2_500;
  vault.shares += 2_500;
  vault.pendingRedeems += 400;
  vault.shares -= 400;
  vault.assets -= 400;

  const operator: Operator = {
    service: "solver",
    bonded: 1_200,
    minBond: 1_000,
    healthBps: 9_700,
    jailed: false,
    feesAccrued: 12
  };
  operator.jailed = operator.bonded < operator.minBond || operator.healthBps < 5_000;

  const hookOrder = {
    amountIn: 700,
    minOut: 690,
    amountOut: 704,
    feePips: 18
  };
  if (hookOrder.amountOut < hookOrder.minOut) {
    throw new Error("hook order underfilled");
  }

  const margin: MarginAccount = {
    collateral: 4_000,
    exposure: 3_000,
    healthBps: 10_000,
    liquidations: 0
  };
  margin.healthBps = healthBps(margin);
  if (margin.healthBps < 1_000) {
    margin.liquidations += 1;
    margin.collateral = 0;
    margin.exposure = 0;
    margin.healthBps = 10_000;
  }

  const rwa: RwaMarket = {
    navPerShare: 101,
    totalShares: 10_000,
    redemptionQueue: 750,
    frozen: false
  };
  if (rwa.frozen) {
    throw new Error("frozen RWA should not settle");
  }
  rwa.totalShares -= rwa.redemptionQueue;

  const payload = {
    intent,
    vault,
    operator,
    hookOrder,
    margin,
    rwa,
    launchReady:
      intent.status === "filled"
      && vault.assets > 0
      && !operator.jailed
      && hookOrder.amountOut >= hookOrder.minOut
      && margin.healthBps >= 1_000
      && !rwa.frozen
  };
  writeTelemetrySnapshot("defi_2026_primitives", payload);
  return payload;
}
