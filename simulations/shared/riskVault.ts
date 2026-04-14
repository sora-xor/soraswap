export type BucketId = 1 | 2 | 3;

export type BucketConfig = {
  utilisationCapBps: number;
  payoutCapBps: number;
  collateralMultiplierBps: number;
};

export type AutomationState = {
  backlog: number;
  backlogCap: number;
  cadenceSlots: number;
  safeMode: boolean;
};

export type BucketSnapshot = {
  bucketId: BucketId;
  deposits: number;
  outstandingNotional: number;
  reservedCollateral: number;
  requiredCollateral: number;
  utilisationBps: number;
  payoutCapBps: number;
  utilisationCapBps: number;
  collateralMultiplierBps: number;
  settledPayouts: number;
  surplus: number;
  automation: AutomationState;
};

type BucketState = {
  deposits: number;
  outstandingNotional: number;
  reservedCollateral: number;
  settledPayouts: number;
  automation: AutomationState;
};

type ExposureState = {
  exposureId: number;
  notional: number;
  collateral: number;
  settledPayout: number;
  active: boolean;
};

const DEFAULT_BUCKET_CONFIG: Record<BucketId, BucketConfig> = {
  1: { utilisationCapBps: 0, payoutCapBps: 8_000, collateralMultiplierBps: 1_500 },
  2: { utilisationCapBps: 10_000, payoutCapBps: 10_000, collateralMultiplierBps: 10_000 },
  3: { utilisationCapBps: 10_000, payoutCapBps: 7_000, collateralMultiplierBps: 10_000 }
};

function exposureKey(bucketId: BucketId, exposureId: number): string {
  return `${bucketId}:${exposureId}`;
}

export class RiskVaultModel {
  private readonly configs = new Map<BucketId, BucketConfig>();
  private readonly buckets = new Map<BucketId, BucketState>();
  private readonly exposures = new Map<string, ExposureState>();

  constructor(configs: Partial<Record<BucketId, Partial<BucketConfig>>> = {}) {
    ([1, 2, 3] as const).forEach((bucketId) => {
      const config = { ...DEFAULT_BUCKET_CONFIG[bucketId], ...(configs[bucketId] ?? {}) };
      this.configs.set(bucketId, config);
      this.buckets.set(bucketId, {
        deposits: 0,
        outstandingNotional: 0,
        reservedCollateral: 0,
        settledPayouts: 0,
        automation: { backlog: 0, backlogCap: 0, cadenceSlots: 0, safeMode: false }
      });
    });
  }

  configureAutomation(bucketId: BucketId, update: Partial<AutomationState>): void {
    const state = this.mustBucket(bucketId).automation;
    this.mustBucket(bucketId).automation = {
      backlog: update.backlog ?? state.backlog,
      backlogCap: update.backlogCap ?? state.backlogCap,
      cadenceSlots: update.cadenceSlots ?? state.cadenceSlots,
      safeMode: update.safeMode ?? state.safeMode
    };
  }

  reportAutomation(bucketId: BucketId, backlog: number, safeMode: boolean): void {
    this.configureAutomation(bucketId, { backlog, safeMode });
  }

  deposit(bucketId: BucketId, amount: number): BucketSnapshot {
    this.assertNonNegative(amount, "deposit");
    this.mustBucket(bucketId).deposits += amount;
    return this.bucketState(bucketId);
  }

  withdraw(bucketId: BucketId, amount: number): BucketSnapshot {
    this.assertNonNegative(amount, "withdraw");
    const snapshot = this.bucketState(bucketId);
    if (amount > snapshot.surplus) {
      throw new Error(`bucket ${bucketId} surplus exhausted`);
    }
    this.mustBucket(bucketId).deposits -= amount;
    return this.bucketState(bucketId);
  }

  lockLiability(bucketId: BucketId, exposureId: number, target: { notional: number; collateral: number; backlog?: number }): BucketSnapshot {
    this.assertNonNegative(target.notional, "liability notional");
    this.assertNonNegative(target.collateral, "liability collateral");

    const key = exposureKey(bucketId, exposureId);
    const prior = this.exposures.get(key) ?? {
      exposureId,
      notional: 0,
      collateral: 0,
      settledPayout: 0,
      active: false
    };

    const bucket = this.mustBucket(bucketId);
    const nextOutstanding = bucket.outstandingNotional - prior.notional + target.notional;
    const nextReserved = bucket.reservedCollateral - prior.collateral + target.collateral;
    const nextRequired = this.requiredCollateral(bucketId, nextOutstanding, nextReserved);
    const nextUtilisation = this.utilisationBps(bucketId, bucket.deposits, nextOutstanding, nextReserved);
    const config = this.mustConfig(bucketId);

    if (bucket.deposits < nextRequired) {
      throw new Error(`bucket ${bucketId} undercollateralized`);
    }
    if (config.utilisationCapBps > 0 && nextUtilisation > config.utilisationCapBps) {
      throw new Error(`bucket ${bucketId} utilisation guard`);
    }

    bucket.outstandingNotional = nextOutstanding;
    bucket.reservedCollateral = nextReserved;
    if (typeof target.backlog === "number") {
      bucket.automation.backlog = target.backlog;
    }
    this.exposures.set(key, {
      exposureId,
      notional: target.notional,
      collateral: target.collateral,
      settledPayout: prior.settledPayout,
      active: true
    });

    return this.bucketState(bucketId);
  }

  releaseLiability(bucketId: BucketId, exposureId: number, backlog?: number): BucketSnapshot {
    const key = exposureKey(bucketId, exposureId);
    const exposure = this.exposures.get(key);
    if (!exposure || !exposure.active) {
      if (typeof backlog === "number") {
        this.mustBucket(bucketId).automation.backlog = backlog;
      }
      return this.bucketState(bucketId);
    }

    const bucket = this.mustBucket(bucketId);
    bucket.outstandingNotional -= exposure.notional;
    bucket.reservedCollateral -= exposure.collateral;
    if (typeof backlog === "number") {
      bucket.automation.backlog = backlog;
    }
    this.exposures.set(key, { ...exposure, active: false, notional: 0, collateral: 0 });
    return this.bucketState(bucketId);
  }

  settlePayout(bucketId: BucketId, exposureId: number, requestedAmount: number): number {
    this.assertNonNegative(requestedAmount, "requested payout");
    const key = exposureKey(bucketId, exposureId);
    const exposure = this.exposures.get(key);
    if (!exposure) {
      throw new Error(`bucket ${bucketId} exposure ${exposureId} missing`);
    }

    const bucket = this.mustBucket(bucketId);
    const config = this.mustConfig(bucketId);
    const payoutCap = Math.floor((exposure.notional * config.payoutCapBps) / 10_000);
    const finalAmount = Math.min(requestedAmount, payoutCap, bucket.deposits);

    bucket.deposits -= finalAmount;
    bucket.settledPayouts += finalAmount;
    bucket.reservedCollateral -= Math.min(bucket.reservedCollateral, finalAmount);

    this.exposures.set(key, {
      ...exposure,
      collateral: Math.max(0, exposure.collateral - finalAmount),
      settledPayout: exposure.settledPayout + finalAmount
    });

    return finalAmount;
  }

  exposureState(bucketId: BucketId, exposureId: number): ExposureState {
    return this.exposures.get(exposureKey(bucketId, exposureId)) ?? {
      exposureId,
      notional: 0,
      collateral: 0,
      settledPayout: 0,
      active: false
    };
  }

  bucketState(bucketId: BucketId): BucketSnapshot {
    const bucket = this.mustBucket(bucketId);
    const config = this.mustConfig(bucketId);
    const requiredCollateral = this.requiredCollateral(bucketId, bucket.outstandingNotional, bucket.reservedCollateral);
    return {
      bucketId,
      deposits: bucket.deposits,
      outstandingNotional: bucket.outstandingNotional,
      reservedCollateral: bucket.reservedCollateral,
      requiredCollateral,
      utilisationBps: this.utilisationBps(bucketId, bucket.deposits, bucket.outstandingNotional, bucket.reservedCollateral),
      payoutCapBps: config.payoutCapBps,
      utilisationCapBps: config.utilisationCapBps,
      collateralMultiplierBps: config.collateralMultiplierBps,
      settledPayouts: bucket.settledPayouts,
      surplus: bucket.deposits - requiredCollateral,
      automation: { ...bucket.automation }
    };
  }

  riskState(): {
    totalDeposits: number;
    totalOutstandingNotional: number;
    totalReservedCollateral: number;
    totalSettledPayouts: number;
    maxUtilisationBps: number;
    unsafeBuckets: BucketId[];
  } {
    const snapshots = ([1, 2, 3] as const).map((bucketId) => this.bucketState(bucketId));
    return {
      totalDeposits: snapshots.reduce((sum, entry) => sum + entry.deposits, 0),
      totalOutstandingNotional: snapshots.reduce((sum, entry) => sum + entry.outstandingNotional, 0),
      totalReservedCollateral: snapshots.reduce((sum, entry) => sum + entry.reservedCollateral, 0),
      totalSettledPayouts: snapshots.reduce((sum, entry) => sum + entry.settledPayouts, 0),
      maxUtilisationBps: Math.max(...snapshots.map((entry) => entry.utilisationBps)),
      unsafeBuckets: snapshots.filter((entry) => entry.automation.safeMode).map((entry) => entry.bucketId)
    };
  }

  assertInvariant(): void {
    ([1, 2, 3] as const).forEach((bucketId) => {
      const snapshot = this.bucketState(bucketId);
      if (snapshot.deposits < 0) {
        throw new Error(`bucket ${bucketId} deposits negative`);
      }
      if (snapshot.outstandingNotional < 0 || snapshot.reservedCollateral < 0) {
        throw new Error(`bucket ${bucketId} liability negative`);
      }
      if (snapshot.surplus + snapshot.requiredCollateral !== snapshot.deposits) {
        throw new Error(`bucket ${bucketId} accounting mismatch`);
      }
    });
  }

  private requiredCollateral(bucketId: BucketId, outstandingNotional: number, reservedCollateral: number): number {
    return Math.max(
      reservedCollateral,
      Math.floor((outstandingNotional * this.mustConfig(bucketId).collateralMultiplierBps) / 10_000)
    );
  }

  private utilisationBps(bucketId: BucketId, deposits: number, outstandingNotional: number, reservedCollateral: number): number {
    const required = this.requiredCollateral(bucketId, outstandingNotional, reservedCollateral);
    if (required === 0) {
      return 0;
    }
    if (deposits === 0) {
      return 10_000;
    }
    return Math.ceil((required * 10_000) / deposits);
  }

  private mustConfig(bucketId: BucketId): BucketConfig {
    const config = this.configs.get(bucketId);
    if (!config) {
      throw new Error(`bucket ${bucketId} config missing`);
    }
    return config;
  }

  private mustBucket(bucketId: BucketId): BucketState {
    const bucket = this.buckets.get(bucketId);
    if (!bucket) {
      throw new Error(`bucket ${bucketId} missing`);
    }
    return bucket;
  }

  private assertNonNegative(value: number, label: string): void {
    if (value < 0) {
      throw new Error(`${label} cannot be negative`);
    }
  }
}
