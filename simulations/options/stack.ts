import { RiskVaultModel } from "../shared/riskVault";
import { writeTelemetrySnapshot } from "../shared/telemetry";

type OptionKind = "shout" | "outperformance";

type TemplateState = {
  templateId: number;
  kind: OptionKind;
  strikeBps: number;
  collateralMultiplierBps: number;
  basePremiumBps: number;
};

type SeriesState = {
  seriesId: number;
  templateId: number;
  kind: OptionKind;
  maxNotional: number;
  premiumBps: number;
  strikeBps: number;
  collateralMultiplierBps: number;
  expirySlot: number;
  openNotional: number;
  utilisationBps: number;
  settlementSlot: number;
};

type PositionState = {
  positionId: number;
  owner: string;
  seriesId: number;
  kind: OptionKind;
  notional: number;
  premiumPaid: number;
  collateralLocked: number;
  shoutFloorBps: number;
  payout: number;
  status: "active" | "settled" | "exercised" | "expired";
};

type UtilisationGuard = {
  bumpActivateBps: number;
  bumpDeactivateBps: number;
  pauseThresholdBps: number;
  bumpPercentBps: number;
};

function max(a: number, b: number): number {
  return Math.max(a, b);
}

export class OptionsStackModel {
  private nextTemplateId = 1;
  private nextSeriesId = 1;
  private nextPositionId = 1;
  private readonly templates = new Map<number, TemplateState>();
  private readonly series = new Map<number, SeriesState>();
  private readonly positions = new Map<number, PositionState>();
  private readonly guards = new Map<number, UtilisationGuard>();
  private readonly vaultLedger = new Map<number, { collateralLocked: number; premiumAccrued: number; payouts: number }>();
  private automation = { backlogCap: 0, backlog: 0, safeMode: false };

  constructor(private readonly vault: RiskVaultModel) {}

  configureAutomation(backlogCap: number, backlog: number, safeMode: boolean): void {
    this.automation = { backlogCap, backlog, safeMode };
    this.vault.configureAutomation(2, { backlogCap, backlog, safeMode, cadenceSlots: 5 });
  }

  registerTemplate(kind: OptionKind, strikeBps: number, collateralMultiplierBps: number, basePremiumBps: number): number {
    const templateId = this.nextTemplateId++;
    this.templates.set(templateId, {
      templateId,
      kind,
      strikeBps,
      collateralMultiplierBps,
      basePremiumBps
    });
    return templateId;
  }

  createSeries(templateId: number, expirySlot: number, maxNotional: number, premiumBps: number): number {
    const template = this.mustTemplate(templateId);
    const seriesId = this.nextSeriesId++;
    this.series.set(seriesId, {
      seriesId,
      templateId,
      kind: template.kind,
      maxNotional,
      premiumBps,
      strikeBps: template.strikeBps,
      collateralMultiplierBps: template.collateralMultiplierBps,
      expirySlot,
      openNotional: 0,
      utilisationBps: 0,
      settlementSlot: 0
    });
    this.vaultLedger.set(seriesId, { collateralLocked: 0, premiumAccrued: 0, payouts: 0 });
    this.guards.set(seriesId, {
      bumpActivateBps: 8_000,
      bumpDeactivateBps: 6_000,
      pauseThresholdBps: 9_500,
      bumpPercentBps: 1_500
    });
    return seriesId;
  }

  buyShout(owner: string, seriesId: number, notional: number, premiumPaid: number, collateralLocked: number): number {
    return this.buyPosition(owner, seriesId, "shout", notional, premiumPaid, collateralLocked);
  }

  buyOutperformance(owner: string, seriesId: number, notional: number, premiumPaid: number, collateralLocked: number): number {
    return this.buyPosition(owner, seriesId, "outperformance", notional, premiumPaid, collateralLocked);
  }

  recordShout(positionId: number, floorBps: number): void {
    const position = this.mustPosition(positionId, "shout");
    position.shoutFloorBps = max(position.shoutFloorBps, floorBps);
  }

  settleOutperformance(positionId: number, baseReturnBps: number, quoteReturnBps: number): number {
    const position = this.mustPosition(positionId, "outperformance");
    const series = this.mustSeries(position.seriesId);
    const positiveDiff = max(baseReturnBps - quoteReturnBps, 0);
    position.payout = Math.floor((position.notional * positiveDiff * series.collateralMultiplierBps) / 10_000 / 10_000);
    position.status = "settled";
    series.settlementSlot += 1;
    return position.payout;
  }

  exerciseShout(positionId: number, spotBps: number): number {
    const position = this.mustPosition(positionId, "shout");
    const series = this.mustSeries(position.seriesId);
    const effectiveBps = max(position.shoutFloorBps, spotBps);
    const intrinsic = max(effectiveBps - series.strikeBps, 0);
    const requestedPayout = Math.floor((position.notional * intrinsic) / 10_000);
    return this.settlePosition(position, requestedPayout);
  }

  exerciseOutperformance(positionId: number): number {
    const position = this.mustPosition(positionId, "outperformance");
    if (position.status !== "settled") {
      throw new Error("outperformance settlement missing");
    }
    return this.settlePosition(position, position.payout);
  }

  expireSeries(seriesId: number): void {
    const series = this.mustSeries(seriesId);
    series.settlementSlot = max(series.settlementSlot, series.expirySlot);
  }

  seriesState(seriesId: number): SeriesState {
    return { ...this.mustSeries(seriesId) };
  }

  positionState(positionId: number): PositionState {
    return { ...this.mustPosition(positionId) };
  }

  vaultState(seriesId: number): { collateralLocked: number; premiumAccrued: number; payouts: number } {
    const state = this.vaultLedger.get(seriesId);
    if (!state) {
      throw new Error(`series ${seriesId} vault missing`);
    }
    return { ...state };
  }

  static runScenario(): ReturnType<typeof writeTelemetrySnapshot>["payload"] {
    const vault = new RiskVaultModel();
    const options = new OptionsStackModel(vault);
    vault.deposit(2, 25_000);
    options.configureAutomation(8, 2, false);

    const shoutTemplate = options.registerTemplate("shout", 10_200, 10_000, 400);
    const outperfTemplate = options.registerTemplate("outperformance", 10_000, 10_000, 500);
    const shoutSeries = options.createSeries(shoutTemplate, 40, 30_000, 450);
    const outperfSeries = options.createSeries(outperfTemplate, 40, 20_000, 600);

    const shoutPosition = options.buyShout("alice", shoutSeries, 6_000, 320, 2_800);
    const outperfPosition = options.buyOutperformance("bob", outperfSeries, 5_000, 360, 3_500);
    options.recordShout(shoutPosition, 11_400);
    const shoutPayout = options.exerciseShout(shoutPosition, 10_900);
    const outperfSettled = options.settleOutperformance(outperfPosition, 18_000, 10_500);
    const outperfPayout = options.exerciseOutperformance(outperfPosition);

    let staleOracleRejected = false;
    try {
      options.configureAutomation(8, 9, false);
      options.buyShout("carol", shoutSeries, 4_000, 200, 2_200);
    } catch {
      staleOracleRejected = true;
    }
    options.configureAutomation(8, 2, false);

    const payload = {
      shoutSeries: options.seriesState(shoutSeries),
      outperformanceSeries: options.seriesState(outperfSeries),
      shoutPosition: options.positionState(shoutPosition),
      outperformancePosition: options.positionState(outperfPosition),
      shoutPayoffLocking: {
        shoutFloorBps: options.positionState(shoutPosition).shoutFloorBps,
        payout: shoutPayout
      },
      outperformanceSettlement: {
        settledPayout: outperfSettled,
        exercisedPayout: outperfPayout
      },
      utilisationGuard: {
        shoutUtilisationBps: options.seriesState(shoutSeries).utilisationBps,
        outperformanceUtilisationBps: options.seriesState(outperfSeries).utilisationBps
      },
      staleOracleRejected,
      collateralConservation: {
        shoutVault: options.vaultState(shoutSeries),
        outperformanceVault: options.vaultState(outperfSeries),
        bucket: vault.bucketState(2)
      },
      riskState: vault.riskState()
    };

    writeTelemetrySnapshot("options_shared_risk", payload);
    return payload;
  }

  private buyPosition(owner: string, seriesId: number, kind: OptionKind, notional: number, premiumPaid: number, collateralLocked: number): number {
    const series = this.mustSeries(seriesId);
    const guard = this.mustGuard(seriesId);
    const nextOpenNotional = series.openNotional + notional;
    const projectedUtilisation = Math.ceil((nextOpenNotional * 10_000) / series.maxNotional);

    if (this.automation.safeMode) {
      throw new Error("options safe mode");
    }
    if (this.automation.backlogCap > 0 && this.automation.backlog > this.automation.backlogCap) {
      throw new Error("options backlog");
    }
    if (projectedUtilisation >= guard.pauseThresholdBps) {
      throw new Error("options utilisation pause");
    }

    const bumpedPremiumBps =
      projectedUtilisation >= guard.bumpActivateBps ? series.premiumBps + guard.bumpPercentBps : series.premiumBps;
    const requiredPremium = Math.floor((notional * bumpedPremiumBps) / 10_000);
    if (premiumPaid < requiredPremium) {
      throw new Error("premium below utilisation guard");
    }

    const positionId = this.nextPositionId++;
    this.positions.set(positionId, {
      positionId,
      owner,
      seriesId,
      kind,
      notional,
      premiumPaid,
      collateralLocked,
      shoutFloorBps: 0,
      payout: 0,
      status: "active"
    });

    series.openNotional = nextOpenNotional;
    series.utilisationBps = projectedUtilisation;

    const ledger = this.mustVault(seriesId);
    ledger.collateralLocked += collateralLocked;
    ledger.premiumAccrued += premiumPaid;

    this.vault.deposit(2, premiumPaid + collateralLocked);
    this.vault.lockLiability(2, positionId, {
      notional: collateralLocked,
      collateral: collateralLocked,
      backlog: this.automation.backlog
    });

    return positionId;
  }

  private settlePosition(position: PositionState, requestedPayout: number): number {
    if (position.kind === "shout" && position.status !== "active") {
      throw new Error("position not active");
    }
    if (position.kind === "outperformance" && position.status !== "settled") {
      throw new Error("position not settled");
    }

    const series = this.mustSeries(position.seriesId);
    const ledger = this.mustVault(position.seriesId);
    const finalPayout = this.vault.settlePayout(2, position.positionId, Math.min(requestedPayout, position.collateralLocked));
    this.vault.releaseLiability(2, position.positionId, this.automation.backlog);

    ledger.collateralLocked -= Math.min(ledger.collateralLocked, finalPayout);
    ledger.payouts += finalPayout;
    series.openNotional -= position.notional;
    series.utilisationBps = series.maxNotional > 0 ? Math.ceil((series.openNotional * 10_000) / series.maxNotional) : 0;
    position.payout = finalPayout;
    position.status = "exercised";
    return finalPayout;
  }

  private mustTemplate(templateId: number): TemplateState {
    const template = this.templates.get(templateId);
    if (!template) {
      throw new Error(`template ${templateId} missing`);
    }
    return template;
  }

  private mustSeries(seriesId: number): SeriesState {
    const series = this.series.get(seriesId);
    if (!series) {
      throw new Error(`series ${seriesId} missing`);
    }
    return series;
  }

  private mustPosition(positionId: number, kind?: OptionKind): PositionState {
    const position = this.positions.get(positionId);
    if (!position) {
      throw new Error(`position ${positionId} missing`);
    }
    if (kind && position.kind !== kind) {
      throw new Error(`position ${positionId} kind mismatch`);
    }
    return position;
  }

  private mustGuard(seriesId: number): UtilisationGuard {
    const guard = this.guards.get(seriesId);
    if (!guard) {
      throw new Error(`series ${seriesId} guard missing`);
    }
    return guard;
  }

  private mustVault(seriesId: number): { collateralLocked: number; premiumAccrued: number; payouts: number } {
    const ledger = this.vaultLedger.get(seriesId);
    if (!ledger) {
      throw new Error(`series ${seriesId} vault missing`);
    }
    return ledger;
  }
}
