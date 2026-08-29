import { CoverManagerModel } from "../cover/manager";
import { OptionsFactoryModel } from "../options/factory";
import { MarketOraclePublication, PerpsEngineModel } from "../perps/engine";

type AuctionSide = "bid" | "ask";
type AuctionOrderStatus = "active" | "cancelled" | "settled";

type AuctionOrder = {
  id: string;
  owner: string;
  side: AuctionSide;
  amount: number;
  limitTick: number;
  status: AuctionOrderStatus;
  baseOut: number;
  quoteOut: number;
  baseRefund: number;
  quoteRefund: number;
};

type Clearing = {
  tick: number;
  matchedBase: number;
  bidBase: number;
  askBase: number;
  scannedTicks: number;
};

class EpochAuctionModel {
  private epoch = {
    id: 0,
    status: "idle" as "idle" | "active" | "closed",
    startSlot: 0,
    endSlot: 0,
    lowerTick: 0,
    upperTick: 0,
    tickStep: 0,
    maxOrders: 0,
    clearing: { tick: 0, matchedBase: 0, bidBase: 0, askBase: 0, scannedTicks: 0 } as Clearing
  };
  private readonly orders = new Map<string, AuctionOrder>();
  private orderCount = 0;

  configureEpoch(
    id: number,
    startSlot: number,
    endSlot: number,
    lowerTick: number,
    upperTick: number,
    tickStep: number,
    maxOrders: number
  ): void {
    if (id <= this.epoch.id) throw new Error("stale epoch");
    if (startSlot < 0) throw new Error("invalid start slot");
    if (endSlot <= startSlot) throw new Error("invalid end slot");
    if (lowerTick <= 0) throw new Error("invalid lower tick");
    if (upperTick < lowerTick) throw new Error("invalid upper tick");
    if (tickStep <= 0) throw new Error("invalid tick step");
    if (maxOrders <= 0) throw new Error("invalid max orders");
    if (maxOrders > 256) throw new Error("max orders too high");
    this.epoch = {
      id,
      status: "active",
      startSlot,
      endSlot,
      lowerTick,
      upperTick,
      tickStep,
      maxOrders,
      clearing: { tick: 0, matchedBase: 0, bidBase: 0, askBase: 0, scannedTicks: 0 }
    };
    this.orderCount = 0;
  }

  submit(input: { id: string; owner: string; side: AuctionSide; amount: number; limitTick: number; slot: number }): void {
    if (this.epoch.status !== "active") throw new Error("epoch not active");
    if (input.side !== "bid" && input.side !== "ask") throw new Error("invalid side");
    if (input.amount <= 0) throw new Error("invalid amount");
    if (input.limitTick <= 0) throw new Error("invalid limit tick");
    if (this.orders.has(input.id)) throw new Error("order exists");
    if (this.orderCount >= this.epoch.maxOrders) throw new Error("epoch order cap");
    if (input.slot < this.epoch.startSlot) throw new Error("epoch not started");
    if (input.slot >= this.epoch.endSlot) throw new Error("epoch closed");

    this.orders.set(input.id, {
      id: input.id,
      owner: input.owner,
      side: input.side,
      amount: input.amount,
      limitTick: input.limitTick,
      status: "active",
      baseOut: 0,
      quoteOut: 0,
      baseRefund: 0,
      quoteRefund: 0
    });
    this.orderCount += 1;
  }

  cancel(orderId: string, owner: string): void {
    const order = this.mustOrder(orderId);
    if (order.owner !== owner) throw new Error("order owner mismatch");
    if (order.status !== "active") throw new Error("order not active");
    if (this.epoch.status !== "active") throw new Error("epoch not active");
    order.status = "cancelled";
    if (order.side === "bid") {
      order.quoteRefund = order.amount;
    } else {
      order.baseRefund = order.amount;
    }
  }

  close(slot: number): boolean {
    if (this.epoch.status !== "active") throw new Error("epoch not active");
    if (slot < this.epoch.endSlot) {
      return false;
    }
    this.epoch.clearing = this.computeClearing();
    this.epoch.status = "closed";
    return true;
  }

  settle(orderId: string, owner: string): AuctionOrder {
    const order = this.mustOrder(orderId);
    if (this.epoch.status !== "closed") throw new Error("epoch not closed");
    if (order.owner !== owner) throw new Error("order owner mismatch");
    if (order.status !== "active") throw new Error("order settled");

    const clearing = this.epoch.clearing;
    if (clearing.tick <= 0 || clearing.matchedBase <= 0 || !this.crosses(order, clearing.tick)) {
      if (order.side === "bid") {
        order.quoteRefund = order.amount;
      } else {
        order.baseRefund = order.amount;
      }
    } else if (order.side === "bid") {
      const capacity = this.baseCapacityForBid(order.amount, clearing.tick);
      order.baseOut = clearing.bidBase <= clearing.matchedBase
        ? capacity
        : Math.floor((capacity * clearing.matchedBase) / clearing.bidBase);
      order.quoteRefund = order.amount - this.quoteForBase(order.baseOut, clearing.tick);
    } else {
      const filledBase = clearing.askBase <= clearing.matchedBase
        ? order.amount
        : Math.floor((order.amount * clearing.matchedBase) / clearing.askBase);
      order.baseOut = filledBase;
      order.quoteOut = this.quoteForBase(filledBase, clearing.tick);
      order.baseRefund = order.amount - filledBase;
    }

    order.status = "settled";
    return { ...order };
  }

  clearing(): Clearing {
    return { ...this.epoch.clearing };
  }

  order(orderId: string): AuctionOrder {
    return { ...this.mustOrder(orderId) };
  }

  private computeClearing(): Clearing {
    let tick = this.epoch.lowerTick;
    let scannedTicks = 0;
    let best = { tick: 0, matchedBase: 0, bidBase: 0, askBase: 0, scannedTicks: 0 };
    while (tick <= this.epoch.upperTick && scannedTicks < 128) {
      const totals = this.totalsAtTick(tick);
      if (totals.matchedBase > best.matchedBase) {
        best = { tick, ...totals, scannedTicks: scannedTicks + 1 };
      }
      tick += this.epoch.tickStep;
      scannedTicks += 1;
    }
    return { ...best, scannedTicks };
  }

  private totalsAtTick(tick: number): { bidBase: number; askBase: number; matchedBase: number } {
    let bidBase = 0;
    let askBase = 0;
    for (const order of this.orders.values()) {
      if (order.status !== "active") continue;
      if (!this.crosses(order, tick)) continue;
      if (order.side === "bid") {
        bidBase += this.baseCapacityForBid(order.amount, tick);
      } else {
        askBase += order.amount;
      }
    }
    return { bidBase, askBase, matchedBase: Math.min(bidBase, askBase) };
  }

  private crosses(order: AuctionOrder, tick: number): boolean {
    return order.side === "bid" ? order.limitTick >= tick : order.limitTick <= tick;
  }

  private baseCapacityForBid(quoteAmount: number, tick: number): number {
    return Math.floor((quoteAmount * 1_000_000) / tick);
  }

  private quoteForBase(baseAmount: number, tick: number): number {
    return Math.floor((baseAmount * tick) / 1_000_000);
  }

  private mustOrder(orderId: string): AuctionOrder {
    const order = this.orders.get(orderId);
    if (!order) throw new Error("order missing");
    return order;
  }
}

type TwammOrder = {
  id: string;
  owner: string;
  remaining: number;
  slice: number;
  executedIn: number;
  executedOut: number;
  claimedOut: number;
  minTotalOut: number;
  intervalSlots: number;
  nextSlot: number;
  inputIsBase: number;
  status: "active" | "complete" | "cancelled";
};

class TwammModel {
  private readonly orders = new Map<string, TwammOrder>();
  private readonly orderIds: string[] = [];
  private scanCursor = 0;

  constructor(private cadenceSlots: number, private maxOrdersPerTick: number, private enabled: boolean) {}

  configure(cadenceSlots: number, maxOrdersPerTick: number, enabled: boolean): void {
    if (cadenceSlots < 0) throw new Error("invalid cadence");
    if (maxOrdersPerTick <= 0) throw new Error("invalid max orders");
    if (maxOrdersPerTick > 16) throw new Error("max orders too high");
    this.cadenceSlots = cadenceSlots;
    this.maxOrdersPerTick = maxOrdersPerTick;
    this.enabled = enabled;
  }

  schedule(input: {
    id: string;
    owner: string;
    inputIsBase: number;
    totalIn: number;
    sliceIn: number;
    minTotalOut: number;
    intervalSlots: number;
    startSlot: number;
  }): void {
    if (!this.enabled) throw new Error("twamm disabled");
    if (this.orders.has(input.id)) throw new Error("twamm order exists");
    if (input.inputIsBase !== 0 && input.inputIsBase !== 1) throw new Error("invalid direction");
    if (input.totalIn <= 0) throw new Error("invalid total in");
    if (input.sliceIn <= 0) throw new Error("invalid slice in");
    if (input.minTotalOut < 0) throw new Error("invalid min total out");
    if (input.intervalSlots <= 0) throw new Error("invalid interval");
    if (input.startSlot < 0) throw new Error("invalid start slot");
    this.orders.set(input.id, {
      id: input.id,
      owner: input.owner,
      inputIsBase: input.inputIsBase,
      remaining: input.totalIn,
      slice: input.sliceIn,
      executedIn: 0,
      executedOut: 0,
      claimedOut: 0,
      minTotalOut: input.minTotalOut,
      intervalSlots: input.intervalSlots,
      nextSlot: input.startSlot,
      status: "active"
    });
    this.orderIds.push(input.id);
  }

  tick(slot: number, lastTickSlot: number, fillBps = 9_700): { scanned: number; processed: number } {
    if (!this.enabled) return { scanned: 0, processed: 0 };
    if (this.cadenceSlots > 0 && lastTickSlot > 0 && slot < lastTickSlot + this.cadenceSlots) {
      return { scanned: 0, processed: 0 };
    }

    let scanned = 0;
    let processed = 0;
    if (this.scanCursor >= this.orderIds.length) {
      this.scanCursor = 0;
    }
    while (scanned < this.maxOrdersPerTick && this.orderIds.length > 0) {
      const order = this.orders.get(this.orderIds[this.scanCursor]);
      scanned += 1;
      this.scanCursor = (this.scanCursor + 1) % this.orderIds.length;
      if (order && this.executeOrder(order, slot, fillBps)) {
        processed += 1;
      }
      if (scanned >= this.orderIds.length) break;
    }
    return { scanned, processed };
  }

  cancel(orderId: string, owner: string): number {
    const order = this.mustOrder(orderId);
    if (order.owner !== owner) throw new Error("twamm owner mismatch");
    if (order.status !== "active") throw new Error("twamm not active");
    const refund = order.remaining;
    order.remaining = 0;
    order.status = "cancelled";
    return refund;
  }

  claim(orderId: string, owner: string): number {
    const order = this.mustOrder(orderId);
    if (order.owner !== owner) throw new Error("twamm owner mismatch");
    if (order.status !== "complete" && order.status !== "cancelled") throw new Error("twamm not claimable");
    if (order.executedOut < order.minTotalOut) throw new Error("min total out");
    const claimable = order.executedOut - order.claimedOut;
    if (claimable <= 0) throw new Error("nothing claimable");
    order.claimedOut += claimable;
    return claimable;
  }

  order(orderId: string): TwammOrder {
    return { ...this.mustOrder(orderId) };
  }

  private executeOrder(order: TwammOrder, slot: number, fillBps: number): boolean {
    if (order.status !== "active" || slot < order.nextSlot) return false;
    const amountIn = Math.min(order.remaining, order.slice);
    if (amountIn <= 0) return false;
    order.remaining -= amountIn;
    order.executedIn += amountIn;
    order.executedOut += Math.floor((amountIn * fillBps) / 10_000);
    order.nextSlot = slot + order.intervalSlots;
    if (order.remaining === 0) {
      order.status = "complete";
    }
    return true;
  }

  private mustOrder(orderId: string): TwammOrder {
    const order = this.orders.get(orderId);
    if (!order) throw new Error("twamm order missing");
    return order;
  }
}

type EscrowStatus = "open" | "accepted" | "cancelled" | "expired_refunded";

class ConditionalEscrowModel {
  private readonly escrows = new Map<string, {
    maker: string;
    taker: string;
    amount: number;
    expirySlot: number;
    conditionCode: number;
    status: EscrowStatus;
  }>();

  constructor(private readonly contractAccount = "escrow-contract") {}

  open(input: { id: string; maker: string; taker: string; amount: number; expirySlot: number; conditionCode: number }): void {
    if (this.escrows.has(input.id)) throw new Error("escrow exists");
    if (input.amount <= 0) throw new Error("invalid amount");
    if (input.expirySlot < 0) throw new Error("invalid expiry");
    if (input.conditionCode <= 0) throw new Error("invalid condition");
    this.escrows.set(input.id, { ...input, status: "open" });
  }

  accept(id: string, actor: string, conditionCode: number, slot: number): number {
    const escrow = this.mustEscrow(id);
    if (escrow.status !== "open") throw new Error("escrow not open");
    if (escrow.conditionCode !== conditionCode) throw new Error("condition mismatch");
    if (escrow.expirySlot > 0 && slot > escrow.expirySlot) throw new Error("escrow expired");
    if (actor !== escrow.taker && actor !== this.contractAccount) throw new Error("taker mismatch");
    escrow.status = "accepted";
    return escrow.amount;
  }

  executeTrigger(args: Record<string, unknown>, actor: string, slot: number): number {
    if (typeof args.escrow_id !== "string") throw new Error("escrow_id missing");
    if (!Number.isInteger(args.condition_code)) throw new Error("condition_code missing");
    return this.accept(args.escrow_id, actor, Number(args.condition_code), slot);
  }

  cancel(id: string, actor: string): number {
    const escrow = this.mustEscrow(id);
    if (escrow.maker !== actor) throw new Error("maker mismatch");
    if (escrow.status !== "open") throw new Error("escrow not open");
    escrow.status = "cancelled";
    return escrow.amount;
  }

  refundExpired(id: string, slot: number): number {
    const escrow = this.mustEscrow(id);
    if (escrow.status !== "open") throw new Error("escrow not open");
    if (escrow.expirySlot <= 0) throw new Error("no expiry");
    if (slot <= escrow.expirySlot) throw new Error("escrow live");
    escrow.status = "expired_refunded";
    return escrow.amount;
  }

  status(id: string): EscrowStatus {
    return this.mustEscrow(id).status;
  }

  private mustEscrow(id: string) {
    const escrow = this.escrows.get(id);
    if (!escrow) throw new Error("escrow missing");
    return escrow;
  }
}

function runLifecycleTick<T extends { status: string }>(
  items: T[],
  config: { enabled: boolean; currentSlot: number; nextSlot: number; maxItems: number; cursor: number },
  mutate: (item: T) => boolean
): { processed: number; cursor: number; nextSlot: number } {
  if (!config.enabled || config.currentSlot < config.nextSlot) {
    return { processed: 0, cursor: config.cursor, nextSlot: config.nextSlot };
  }
  let processed = 0;
  let cursor = config.cursor;
  while (processed < config.maxItems && cursor < items.length) {
    if (mutate(items[cursor])) {
      processed += 1;
    }
    cursor += 1;
  }
  return {
    processed,
    cursor: cursor >= items.length ? 0 : cursor,
    nextSlot: config.currentSlot + 4
  };
}

function applyRangeGovernor(
  pool: { feePips: number; activeBin: number; targetHasLiquidity: boolean; balances: { base: number; quote: number } },
  governor: { enabled: boolean; maxFeePips: number; targetActiveBin: number; maxActiveBinDrift: number; nextSlot: number },
  currentSlot: number
): number {
  if (governor.maxFeePips < 0) throw new Error("invalid max fee");
  if (governor.maxActiveBinDrift < 0) throw new Error("invalid drift");
  if (!governor.enabled || currentSlot < governor.nextSlot) return 0;
  let actions = 0;
  if (pool.feePips > governor.maxFeePips) {
    pool.feePips = governor.maxFeePips;
    actions += 1;
  }
  if (Math.abs(pool.activeBin - governor.targetActiveBin) > governor.maxActiveBinDrift && pool.targetHasLiquidity) {
    pool.activeBin = governor.targetActiveBin;
    actions += 2;
  }
  return actions;
}

describe("Trigger-native suite simulations", () => {
  test("epoch auction clears uniformly, prorates at the clearing tick, refunds no-cross orders, and rejects replay settlement", () => {
    const auction = new EpochAuctionModel();
    auction.configureEpoch(1, 0, 10, 900_000, 1_100_000, 100_000, 6);
    auction.submit({ id: "bid-a", owner: "alice", side: "bid", amount: 1_000, limitTick: 1_000_000, slot: 2 });
    auction.submit({ id: "bid-b", owner: "bob", side: "bid", amount: 1_000, limitTick: 1_000_000, slot: 2 });
    auction.submit({ id: "ask-a", owner: "carol", side: "ask", amount: 1_500, limitTick: 1_000_000, slot: 2 });
    auction.submit({ id: "ask-too-high", owner: "dave", side: "ask", amount: 500, limitTick: 1_200_000, slot: 2 });
    auction.submit({ id: "cancel-me", owner: "erin", side: "bid", amount: 2_000, limitTick: 1_100_000, slot: 2 });
    auction.cancel("cancel-me", "erin");

    expect(auction.close(9)).toBe(false);
    expect(() => auction.settle("bid-a", "alice")).toThrow("epoch not closed");
    expect(auction.close(10)).toBe(true);
    expect(auction.clearing()).toMatchObject({ tick: 1_000_000, matchedBase: 1_500, bidBase: 2_000, askBase: 1_500 });

    expect(auction.settle("bid-a", "alice")).toMatchObject({ baseOut: 750, quoteRefund: 250, status: "settled" });
    expect(auction.settle("bid-b", "bob")).toMatchObject({ baseOut: 750, quoteRefund: 250, status: "settled" });
    expect(auction.settle("ask-a", "carol")).toMatchObject({ quoteOut: 1_500, baseRefund: 0, status: "settled" });
    expect(auction.settle("ask-too-high", "dave")).toMatchObject({ quoteOut: 0, baseRefund: 500, status: "settled" });
    expect(() => auction.settle("bid-a", "alice")).toThrow("order settled");
    expect(() => auction.cancel("ask-a", "carol")).toThrow("order not active");
  });

  test("epoch auction rejects invalid config, duplicate orders, wrong owners, slot abuse, and order-cap abuse", () => {
    const auction = new EpochAuctionModel();
    expect(() => auction.configureEpoch(1, 5, 5, 1, 2, 1, 1)).toThrow("invalid end slot");
    expect(() => auction.configureEpoch(1, 0, 5, 0, 2, 1, 1)).toThrow("invalid lower tick");
    expect(() => auction.configureEpoch(1, 0, 5, 1, 2, 0, 1)).toThrow("invalid tick step");
    expect(() => auction.configureEpoch(1, 0, 5, 1, 2, 1, 257)).toThrow("max orders too high");

    auction.configureEpoch(1, 5, 8, 900_000, 1_100_000, 100_000, 1);
    expect(() => auction.configureEpoch(1, 5, 8, 900_000, 1_100_000, 100_000, 1)).toThrow("stale epoch");
    expect(() => auction.submit({ id: "too-early", owner: "alice", side: "bid", amount: 1, limitTick: 1_000_000, slot: 4 })).toThrow("epoch not started");
    expect(() => auction.submit({ id: "bad-side", owner: "alice", side: "bad" as AuctionSide, amount: 1, limitTick: 1_000_000, slot: 5 })).toThrow("invalid side");
    expect(() => auction.submit({ id: "zero", owner: "alice", side: "bid", amount: 0, limitTick: 1_000_000, slot: 5 })).toThrow("invalid amount");
    auction.submit({ id: "live", owner: "alice", side: "bid", amount: 1_000, limitTick: 1_000_000, slot: 5 });
    expect(() => auction.submit({ id: "live", owner: "alice", side: "bid", amount: 1_000, limitTick: 1_000_000, slot: 5 })).toThrow("order exists");
    expect(() => auction.submit({ id: "over-cap", owner: "bob", side: "ask", amount: 10, limitTick: 1_000_000, slot: 5 })).toThrow("epoch order cap");
    expect(() => auction.cancel("live", "mallory")).toThrow("order owner mismatch");
    auction.close(8);
    expect(() => auction.submit({ id: "late", owner: "alice", side: "bid", amount: 1, limitTick: 1, slot: 8 })).toThrow("epoch not active");
  });

  test("epoch auction price scan is bounded and no-cross settlement fully refunds both sides", () => {
    const auction = new EpochAuctionModel();
    auction.configureEpoch(1, 0, 10, 1, 1_000, 1, 4);
    auction.submit({ id: "late-bid", owner: "alice", side: "bid", amount: 200, limitTick: 200, slot: 1 });
    auction.submit({ id: "late-ask", owner: "bob", side: "ask", amount: 1, limitTick: 200, slot: 1 });
    auction.close(10);

    expect(auction.clearing()).toMatchObject({ tick: 0, matchedBase: 0, scannedTicks: 128 });
    expect(auction.settle("late-bid", "alice")).toMatchObject({ baseOut: 0, quoteRefund: 200 });
    expect(auction.settle("late-ask", "bob")).toMatchObject({ quoteOut: 0, baseRefund: 1 });
  });

  test("TWAMM trigger scans and executes bounded work while enforcing min-total-out on claim", () => {
    const twamm = new TwammModel(2, 2, true);
    twamm.schedule({ id: "a", owner: "alice", inputIsBase: 1, totalIn: 90, sliceIn: 30, minTotalOut: 84, intervalSlots: 2, startSlot: 10 });
    twamm.schedule({ id: "b", owner: "bob", inputIsBase: 1, totalIn: 60, sliceIn: 30, minTotalOut: 56, intervalSlots: 2, startSlot: 10 });
    twamm.schedule({ id: "c", owner: "carol", inputIsBase: 1, totalIn: 60, sliceIn: 30, minTotalOut: 56, intervalSlots: 2, startSlot: 10 });

    expect(twamm.tick(9, 8)).toEqual({ scanned: 0, processed: 0 });
    expect(twamm.tick(10, 8)).toEqual({ scanned: 2, processed: 2 });
    expect(twamm.order("a")).toMatchObject({ remaining: 60, executedIn: 30, executedOut: 29 });
    expect(twamm.order("c")).toMatchObject({ remaining: 60, executedIn: 0 });
    expect(twamm.tick(11, 10)).toEqual({ scanned: 0, processed: 0 });
    expect(twamm.tick(12, 10)).toEqual({ scanned: 2, processed: 2 });
    expect(twamm.order("c")).toMatchObject({ remaining: 30, executedOut: 29 });

    twamm.tick(14, 12);
    twamm.tick(16, 14);
    expect(twamm.claim("a", "alice")).toBe(87);
    expect(() => twamm.claim("a", "alice")).toThrow("nothing claimable");
  });

  test("TWAMM rejects adversarial schedules, wrong owners, premature claims, disabled ticks, and min-out failures", () => {
    const twamm = new TwammModel(1, 2, true);
    expect(() => twamm.schedule({ id: "bad-dir", owner: "alice", inputIsBase: 2, totalIn: 1, sliceIn: 1, minTotalOut: 0, intervalSlots: 1, startSlot: 0 })).toThrow("invalid direction");
    expect(() => twamm.schedule({ id: "dust", owner: "alice", inputIsBase: 1, totalIn: 1, sliceIn: 0, minTotalOut: 0, intervalSlots: 1, startSlot: 0 })).toThrow("invalid slice in");
    twamm.schedule({ id: "slow", owner: "alice", inputIsBase: 1, totalIn: 100, sliceIn: 50, minTotalOut: 120, intervalSlots: 1, startSlot: 1 });
    expect(() => twamm.schedule({ id: "slow", owner: "alice", inputIsBase: 1, totalIn: 1, sliceIn: 1, minTotalOut: 0, intervalSlots: 1, startSlot: 1 })).toThrow("twamm order exists");
    expect(() => twamm.claim("slow", "alice")).toThrow("twamm not claimable");
    expect(() => twamm.cancel("slow", "mallory")).toThrow("twamm owner mismatch");
    twamm.configure(1, 2, false);
    expect(twamm.tick(1, 0)).toEqual({ scanned: 0, processed: 0 });
    twamm.configure(1, 2, true);
    twamm.tick(1, 0, 8_000);
    twamm.tick(2, 1, 8_000);
    expect(twamm.order("slow")).toMatchObject({ status: "complete", executedOut: 80 });
    expect(() => twamm.claim("slow", "alice")).toThrow("min total out");
  });

  test("product lifecycle ticks are disabled/not-due safe, bounded by max_items_per_tick, and skip finalized state", () => {
    const options = [
      { status: "active", expiry: 10 },
      { status: "closed", expiry: 5 },
      { status: "active", expiry: 12 },
      { status: "active", expiry: 30 }
    ];
    const disabled = runLifecycleTick(options, { enabled: false, currentSlot: 20, nextSlot: 10, maxItems: 2, cursor: 0 }, (item) => {
      if (item.status === "active" && 20 >= item.expiry) {
        item.status = "closed";
        return true;
      }
      return false;
    });
    expect(disabled.processed).toBe(0);
    expect(options.map((entry) => entry.status)).toEqual(["active", "closed", "active", "active"]);

    const due = runLifecycleTick(options, { enabled: true, currentSlot: 20, nextSlot: 10, maxItems: 2, cursor: 0 }, (item) => {
      if (item.status === "active" && 20 >= item.expiry) {
        item.status = "closed";
        return true;
      }
      return false;
    });
    expect(due).toMatchObject({ processed: 2, cursor: 3, nextSlot: 24 });
    expect(options.map((entry) => entry.status)).toEqual(["closed", "closed", "closed", "active"]);

    const launchpadSales = [
      { status: "live", endSlot: 10, seedCustodied: true, activation: "none" },
      { status: "live", endSlot: 10, seedCustodied: false, activation: "none" }
    ];
    runLifecycleTick(launchpadSales, { enabled: true, currentSlot: 20, nextSlot: 1, maxItems: 2, cursor: 0 }, (sale) => {
      if (sale.status !== "live" || 20 < sale.endSlot) return false;
      sale.status = "closed";
      sale.activation = sale.seedCustodied ? "seeded" : "pending";
      return true;
    });
    expect(launchpadSales.map((sale) => sale.activation)).toEqual(["seeded", "pending"]);
  });

  test("conditional escrow public and by-call paths reject replay, wrong takers, bad args, bad conditions, and expired accepts", () => {
    const escrow = new ConditionalEscrowModel();
    escrow.open({ id: "escrow-1", maker: "alice", taker: "bob", amount: 100, expirySlot: 50, conditionCode: 7 });
    expect(() => escrow.accept("escrow-1", "mallory", 7, 20)).toThrow("taker mismatch");
    expect(() => escrow.accept("escrow-1", "bob", 8, 20)).toThrow("condition mismatch");
    expect(escrow.accept("escrow-1", "bob", 7, 20)).toBe(100);
    expect(escrow.status("escrow-1")).toBe("accepted");
    expect(() => escrow.accept("escrow-1", "bob", 7, 21)).toThrow("escrow not open");
    expect(() => escrow.cancel("escrow-1", "alice")).toThrow("escrow not open");
    expect(() => escrow.refundExpired("escrow-1", 60)).toThrow("escrow not open");

    escrow.open({ id: "triggered", maker: "alice", taker: "carol", amount: 75, expirySlot: 50, conditionCode: 9 });
    expect(() => escrow.executeTrigger({}, "escrow-contract", 20)).toThrow("escrow_id missing");
    expect(() => escrow.executeTrigger({ escrow_id: "triggered" }, "escrow-contract", 20)).toThrow("condition_code missing");
    expect(escrow.executeTrigger({ escrow_id: "triggered", condition_code: 9 }, "escrow-contract", 20)).toBe(75);
    expect(() => escrow.executeTrigger({ escrow_id: "triggered", condition_code: 9 }, "escrow-contract", 21)).toThrow("escrow not open");

    escrow.open({ id: "expired", maker: "alice", taker: "bob", amount: 20, expirySlot: 10, conditionCode: 1 });
    expect(() => escrow.accept("expired", "bob", 1, 11)).toThrow("escrow expired");
    expect(escrow.refundExpired("expired", 11)).toBe(20);
    expect(() => escrow.cancel("expired", "alice")).toThrow("escrow not open");
  });

  test("range governor is disabled/not-due safe, rejects invalid bounds, avoids asset movement, and repairs only liquid internal drift", () => {
    const pool = { feePips: 3_000, activeBin: 5, targetHasLiquidity: true, balances: { base: 1_000, quote: 2_000 } };
    const balancesBefore = { ...pool.balances };
    const governor = { enabled: false, maxFeePips: 2_500, targetActiveBin: 0, maxActiveBinDrift: 2, nextSlot: 10 };
    expect(applyRangeGovernor(pool, governor, 20)).toBe(0);
    governor.enabled = true;
    expect(applyRangeGovernor(pool, governor, 9)).toBe(0);
    expect(applyRangeGovernor(pool, governor, 20)).toBe(3);
    expect(pool).toMatchObject({ feePips: 2_500, activeBin: 0, balances: balancesBefore });

    pool.activeBin = 8;
    pool.targetHasLiquidity = false;
    expect(applyRangeGovernor(pool, governor, 21)).toBe(0);
    expect(pool.activeBin).toBe(8);
    expect(() => applyRangeGovernor(pool, { ...governor, maxFeePips: -1 }, 21)).toThrow("invalid max fee");
    expect(() => applyRangeGovernor(pool, { ...governor, maxActiveBinDrift: -1 }, 21)).toThrow("invalid drift");
  });

  test("options and cover trigger lifecycle models keep finalized state immutable under replay and stale observations", () => {
    const options = new OptionsFactoryModel({ oracleStaleSlots: 4 });
    options.syncAutomation(8, false);
    options.exitWithdrawalOnly();
    options.syncSeries(1, {
      kind: "shout",
      maxNotional: 10_000,
      premiumBps: 300,
      collateralMultiplierBps: 10_000,
      expirySlot: 40,
      strikeBps: 10_000
    }, 1);
    options.syncSeries(2, {
      kind: "outperformance",
      maxNotional: 10_000,
      premiumBps: 300,
      collateralMultiplierBps: 10_000,
      expirySlot: 40,
      strikeBps: 10_000
    }, 1);
    const shoutPosition = options.buyShout("alice", 1, 1_000, 10);
    const outperformancePosition = options.buyOutperformance("bob", 2, 1_000, 10);

    options.publishShoutMark(shoutPosition, 11_000, 20, 200, 20);
    expect(options.exerciseShoutPosition("alice", shoutPosition, 20)).toBe(100);
    expect(() => options.exerciseShoutPosition("alice", shoutPosition, 20)).toThrow("position inactive");
    options.settleOutperformanceSeries(2, {
      finalMark: 12_000,
      finalQuoteMark: 10_000,
      baseReturnBps: 12_000,
      quoteReturnBps: 10_000,
      oracleSlot: 40,
      attestationHash: 400
    }, 40);
    expect(options.exerciseOutperformancePosition("bob", outperformancePosition)).toBe(200);
    expect(() => options.exerciseOutperformancePosition("bob", outperformancePosition)).toThrow("position inactive");

    const cover = new CoverManagerModel({ defaultRequiredObservations: 2, oracleStaleSlots: 4 });
    cover.syncAutomation(10, false);
    cover.exitWithdrawalOnly();
    cover.fundReserve(10_000);
    const policyId = cover.registerPolicy("carol", {
      lowerBound: 9_500,
      upperBound: 10_500,
      payoutAmount: 1_000,
      monitoringWindowSlots: 2,
      requiredObservations: 2,
      coveredNotional: 1_500,
      premiumPaid: 50
    }, 0);
    cover.expirePolicy(policyId, 2);
    expect(cover.policy(policyId).status).toBe("expired");
    expect(() => cover.recordObservation(policyId, 12_000, 2, 0, 200, 3)).toThrow("policy not active");
    expect(() => cover.routeClaim("carol", policyId)).toThrow("policy not claimable");
  });

  test("perps native lifecycle uses cached valid oracle state, caps trigger scans, and pays no keeper reward", () => {
    const engine = new PerpsEngineModel();
    engine.syncAutomation(10, false);
    engine.exitWithdrawalOnly();
    engine.fundCollateralPool(100_000);
    const marketId = engine.registerMarket({
      asset: "xor#universal",
      maxLeverageBps: 100_000,
      maintenanceMarginBps: 1_000,
      liquidationFeeBps: 900,
      openInterestCap: 50_000,
      fundingBps: 100,
      fundingIntervalSlots: 4,
      oracleStaleSlots: 4,
      backlogLimit: 10,
      utilisationClampBps: 10_000,
      liquidationStressLimit: 4
    });
    const oracle = (overrides: Partial<MarketOraclePublication> = {}): MarketOraclePublication => ({
      markPriceBps: 10_000,
      indexPriceBps: 10_000,
      confidenceBps: 50,
      oracleSlot: 10,
      currentSlot: 10,
      statusFlags: 0,
      attestationHash: 100,
      ...overrides
    });

    engine.publishMarketOracle(marketId, oracle());
    const positionId = engine.openPosition("alice", marketId, 10_000, 1_500, 100_000, 10);
    engine.publishMarketOracle(marketId, oracle({
      markPriceBps: 8_000,
      indexPriceBps: 8_000,
      oracleSlot: 20,
      currentSlot: 20,
      attestationHash: 200
    }));
    expect(engine.runNativeLifecyclePass(marketId, 1, 20)).toEqual({ scanned: 1, queued: 1, recovered: 0, liquidated: 0 });
    expect(engine.runNativeLifecyclePass(marketId, 1, 21)).toEqual({ scanned: 1, queued: 0, recovered: 0, liquidated: 1 });
    expect(engine.position(positionId)).toMatchObject({ status: "liquidated", lastKeeperReward: 0 });
    expect(() => engine.runNativeLifecyclePass(marketId, 5, 21)).toThrow("native scan size exceeds cap");

    engine.publishMarketOracle(marketId, oracle({ oracleSlot: 30, currentSlot: 30, attestationHash: 300 }));
    const stalePosition = engine.openPosition("bob", marketId, 2_000, 500, 100_000, 30);
    expect(engine.runNativeLifecyclePass(marketId, 1, 40)).toEqual({ scanned: 0, queued: 0, recovered: 0, liquidated: 0 });
    expect(engine.position(stalePosition).status).toBe("open");
    expect(() => engine.publishMarketOracle(marketId, oracle({
      statusFlags: 1,
      oracleSlot: 41,
      currentSlot: 41,
      attestationHash: 301
    }))).toThrow("oracle degraded");
  });
});
