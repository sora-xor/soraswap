type AssetBuckets = {
  usdt: number;
  usdc: number;
  kusd: number;
};

function isSafeInteger(value: number): boolean {
  return Number.isSafeInteger(value);
}

function requirePositiveSafeInteger(value: number, message: string): void {
  if (!isSafeInteger(value) || value <= 0) {
    throw new Error(message);
  }
}

function requireNonNegativeSafeInteger(value: number, message: string): void {
  if (!isSafeInteger(value) || value < 0) {
    throw new Error(message);
  }
}

class ProofBoundBridge {
  private readonly consumedInbound = new Set<string>();
  private readonly routes = new Map<string, { owner: string; governed: boolean; enabled: boolean; messageId: string }>();

  constructor(private proofAuthority: string) {}

  setProofAuthority(owner: string, caller: string, nextProofAuthority: string): void {
    if (caller !== owner) {
      throw new Error("bridge owner mismatch");
    }
    if (!nextProofAuthority) {
      throw new Error("invalid proof authority");
    }
    this.proofAuthority = nextProofAuthority;
  }

  activateRoute(route: string, caller: string): void {
    if (!route) {
      throw new Error("invalid route");
    }
    if (this.routes.has(route)) {
      throw new Error("route exists");
    }
    this.routes.set(route, { owner: caller, governed: false, enabled: true, messageId: route });
  }

  activateRouteGoverned(caller: string, route = "route", messageId = "message"): void {
    this.requireProofAuthority(caller);
    if (!route) {
      throw new Error("invalid route");
    }
    if (!messageId) {
      throw new Error("invalid governance message");
    }
    const existing = this.routes.get(route);
    if (existing && existing.messageId !== messageId) {
      throw new Error("route governance mismatch");
    }
    this.routes.set(route, { owner: caller, governed: true, enabled: true, messageId });
  }

  pauseRoute(caller: string, route: string): void {
    const state = this.mustRoute(route);
    if (state.owner !== caller) {
      throw new Error("route owner mismatch");
    }
    if (state.governed) {
      throw new Error("governed route is proof-managed");
    }
    state.enabled = false;
  }

  finalizeInbound(caller: string, route = "route", messageId = "message-1", amount = 1): void {
    this.requireProofAuthority(caller);
    this.mustRoute(route);
    if (!messageId) {
      throw new Error("invalid message");
    }
    requirePositiveSafeInteger(amount, "invalid amount");
    if (this.consumedInbound.has(messageId)) {
      throw new Error("message consumed");
    }
    this.consumedInbound.add(messageId);
  }

  private requireProofAuthority(caller: string): void {
    if (caller !== this.proofAuthority) {
      throw new Error("bridge proof authority mismatch");
    }
  }

  private mustRoute(route: string): { owner: string; governed: boolean; enabled: boolean; messageId: string } {
    const state = this.routes.get(route);
    if (!state) {
      throw new Error("route missing");
    }
    return state;
  }
}

function launchpadContribute(): number {
  throw new Error("use contribute_recorded");
}

type LaunchpadSale = {
  owner: string;
  unitPrice: number;
  softCap: number;
  hardCap: number;
  raised: number;
  closed: boolean;
  successful: boolean;
  claimInventory: number;
  claimStartSlot: number;
  claimEndSlot: number;
};

type LaunchpadAllocation = {
  sale: string;
  buyer: string;
  paymentAmount: number;
  saleAmount: number;
  claimed: number;
  refunded: boolean;
};

class LaunchpadFactoryModel {
  private owner: string | undefined;
  private readonly sales = new Map<string, LaunchpadSale>();
  private readonly allocations = new Map<string, LaunchpadAllocation>();

  initFactory(caller: string): void {
    if (this.owner) {
      throw new Error("factory initialized");
    }
    this.owner = caller;
  }

  initSale(
    caller: string,
    sale: string,
    config: { unitPrice: number; softCap: number; hardCap: number; claimStartSlot: number; claimEndSlot: number }
  ): void {
    this.requireOwner(caller);
    if (this.sales.has(sale)) {
      throw new Error("sale exists");
    }
    requirePositiveSafeInteger(config.unitPrice, "invalid unit price");
    requirePositiveSafeInteger(config.softCap, "invalid cap");
    requireNonNegativeSafeInteger(config.hardCap, "invalid cap");
    requireNonNegativeSafeInteger(config.claimStartSlot, "invalid claim window");
    requireNonNegativeSafeInteger(config.claimEndSlot, "invalid claim window");
    if (config.hardCap < config.softCap) {
      throw new Error("invalid cap");
    }
    if (config.claimEndSlot < config.claimStartSlot) {
      throw new Error("invalid claim window");
    }
    this.sales.set(sale, {
      owner: caller,
      unitPrice: config.unitPrice,
      softCap: config.softCap,
      hardCap: config.hardCap,
      raised: 0,
      closed: false,
      successful: false,
      claimInventory: 0,
      claimStartSlot: config.claimStartSlot,
      claimEndSlot: config.claimEndSlot
    });
  }

  contributeRecorded(caller: string, saleId: string, allocationId: string, paymentAmount: number): number {
    const sale = this.mustSale(saleId);
    if (this.allocations.has(allocationId)) {
      throw new Error("allocation exists");
    }
    requirePositiveSafeInteger(paymentAmount, "invalid payment");
    if (sale.closed) {
      throw new Error("sale closed");
    }
    const nextRaised = sale.raised + paymentAmount;
    if (nextRaised > sale.hardCap) {
      throw new Error("hard cap");
    }
    const saleAmount = Math.floor(paymentAmount / sale.unitPrice);
    if (saleAmount <= 0) {
      throw new Error("zero sale output");
    }
    sale.raised = nextRaised;
    this.allocations.set(allocationId, {
      sale: saleId,
      buyer: caller,
      paymentAmount,
      saleAmount,
      claimed: 0,
      refunded: false
    });
    return saleAmount;
  }

  closeSale(caller: string, saleId: string): void {
    const sale = this.mustSale(saleId);
    if (sale.owner !== caller) {
      throw new Error("sale owner mismatch");
    }
    if (sale.closed) {
      throw new Error("sale closed");
    }
    sale.closed = true;
    sale.successful = sale.raised >= sale.softCap;
  }

  depositClaimInventory(caller: string, saleId: string, amount: number): void {
    const sale = this.mustSale(saleId);
    if (sale.owner !== caller) {
      throw new Error("sale owner mismatch");
    }
    requirePositiveSafeInteger(amount, "invalid amount");
    sale.claimInventory += amount;
  }

  claimAllocation(caller: string, allocationId: string, blockHeight: number): number {
    const allocation = this.mustAllocation(allocationId);
    const sale = this.mustSale(allocation.sale);
    requireNonNegativeSafeInteger(blockHeight, "invalid block height");
    if (allocation.buyer !== caller) {
      throw new Error("buyer mismatch");
    }
    if (!sale.closed) {
      throw new Error("sale open");
    }
    if (!sale.successful) {
      throw new Error("sale failed");
    }
    if (allocation.refunded) {
      throw new Error("allocation refunded");
    }
    const claimable = this.vestedClaimable(allocation.saleAmount, sale.claimStartSlot, sale.claimEndSlot, blockHeight);
    if (claimable <= allocation.claimed) {
      throw new Error("nothing claimable");
    }
    const amount = claimable - allocation.claimed;
    if (sale.claimInventory < amount) {
      throw new Error("insufficient claim inventory");
    }
    allocation.claimed += amount;
    sale.claimInventory -= amount;
    return amount;
  }

  refundAllocation(caller: string, allocationId: string): number {
    const allocation = this.mustAllocation(allocationId);
    const sale = this.mustSale(allocation.sale);
    if (allocation.buyer !== caller) {
      throw new Error("buyer mismatch");
    }
    if (!sale.closed) {
      throw new Error("sale open");
    }
    if (sale.successful) {
      throw new Error("sale successful");
    }
    if (allocation.claimed > 0) {
      throw new Error("allocation claimed");
    }
    if (allocation.refunded) {
      throw new Error("allocation refunded");
    }
    allocation.refunded = true;
    return allocation.paymentAmount;
  }

  private requireOwner(caller: string): void {
    if (!this.owner) {
      throw new Error("factory not initialized");
    }
    if (this.owner !== caller) {
      throw new Error("factory owner mismatch");
    }
  }

  private vestedClaimable(totalAmount: number, claimStartSlot: number, claimEndSlot: number, blockHeight: number): number {
    if (blockHeight < claimStartSlot) {
      return 0;
    }
    if (claimEndSlot <= claimStartSlot || blockHeight >= claimEndSlot) {
      return totalAmount;
    }
    return Math.floor((totalAmount * (blockHeight - claimStartSlot)) / (claimEndSlot - claimStartSlot));
  }

  private mustSale(sale: string): LaunchpadSale {
    const state = this.sales.get(sale);
    if (!state) {
      throw new Error("sale missing");
    }
    return state;
  }

  private mustAllocation(allocation: string): LaunchpadAllocation {
    const state = this.allocations.get(allocation);
    if (!state) {
      throw new Error("allocation missing");
    }
    return state;
  }
}

function dlmmSwapExactIn(inputAmount: number, availableFill: number, routerPath: boolean): { used: number; output: number } {
  if (!isSafeInteger(inputAmount) || inputAmount <= 0) {
    throw new Error("invalid amount");
  }
  if (!isSafeInteger(availableFill)) {
    throw new Error("invalid fill");
  }
  const used = Math.min(inputAmount, availableFill);
  if (used <= 0) {
    throw new Error("insufficient input used");
  }
  if (routerPath && used !== inputAmount) {
    throw new Error("router partial fill");
  }
  return { used, output: used };
}

class N3xFeeReserveModel {
  basket: AssetBuckets = { usdt: 0, usdc: 0, kusd: 0 };
  feeReserves: AssetBuckets = { usdt: 0, usdc: 0, kusd: 0 };
  totalN3x = 0;

  constructor(private readonly mintFeeBps: number, private readonly redeemFeeBps: number) {
    this.validateFee(mintFeeBps);
    this.validateFee(redeemFeeBps);
  }

  mint(input: AssetBuckets): number {
    for (const [asset, amount] of Object.entries(input)) {
      if (!isSafeInteger(amount)) {
        throw new Error(`invalid ${asset}`);
      }
      if (amount < 0) {
        throw new Error(`negative ${asset}`);
      }
    }
    const fees = this.fees(input, this.mintFeeBps);
    const net = this.subtract(input, fees);
    const minted = this.sum(net);
    if (minted <= 0) {
      throw new Error("zero mint");
    }
    this.addTo(this.basket, net);
    this.addTo(this.feeReserves, fees);
    this.totalN3x += minted;
    return minted;
  }

  redeem(n3xAmount: number): { paid: AssetBuckets; fees: AssetBuckets } {
    if (!isSafeInteger(n3xAmount) || n3xAmount <= 0) {
      throw new Error("invalid n3x_amount");
    }
    if (n3xAmount > this.totalN3x) {
      throw new Error("insufficient supply");
    }
    const gross = {
      usdt: Math.floor((this.basket.usdt * n3xAmount) / this.totalN3x),
      usdc: Math.floor((this.basket.usdc * n3xAmount) / this.totalN3x),
      kusd: Math.floor((this.basket.kusd * n3xAmount) / this.totalN3x)
    };
    const fees = this.fees(gross, this.redeemFeeBps);
    const paid = this.subtract(gross, fees);
    if (this.sum(paid) <= 0) {
      throw new Error("zero redemption");
    }
    this.subtractFrom(this.basket, gross);
    this.addTo(this.feeReserves, fees);
    this.totalN3x -= n3xAmount;
    return { paid, fees };
  }

  claimFees(): AssetBuckets {
    return this.claimFeesAs("owner");
  }

  claimFeesAs(caller: string, owner = "owner"): AssetBuckets {
    if (caller !== owner) {
      throw new Error("hub owner mismatch");
    }
    const claimed = { ...this.feeReserves };
    if (this.sum(claimed) <= 0) {
      throw new Error("no fees");
    }
    this.feeReserves = { usdt: 0, usdc: 0, kusd: 0 };
    return claimed;
  }

  redeemableBacking(): number {
    return this.sum(this.basket);
  }

  vaultBacking(): number {
    return this.sum(this.basket) + this.sum(this.feeReserves);
  }

  private validateFee(feeBps: number): void {
    if (!Number.isSafeInteger(feeBps) || feeBps < 0 || feeBps >= 10_000) {
      throw new Error("invalid fee");
    }
  }

  private fees(input: AssetBuckets, feeBps: number): AssetBuckets {
    return {
      usdt: Math.floor((input.usdt * feeBps) / 10_000),
      usdc: Math.floor((input.usdc * feeBps) / 10_000),
      kusd: Math.floor((input.kusd * feeBps) / 10_000)
    };
  }

  private subtract(input: AssetBuckets, fees: AssetBuckets): AssetBuckets {
    return {
      usdt: input.usdt - fees.usdt,
      usdc: input.usdc - fees.usdc,
      kusd: input.kusd - fees.kusd
    };
  }

  private addTo(target: AssetBuckets, delta: AssetBuckets): void {
    target.usdt += delta.usdt;
    target.usdc += delta.usdc;
    target.kusd += delta.kusd;
  }

  private subtractFrom(target: AssetBuckets, delta: AssetBuckets): void {
    target.usdt -= delta.usdt;
    target.usdc -= delta.usdc;
    target.kusd -= delta.kusd;
  }

  private sum(input: AssetBuckets): number {
    return input.usdt + input.usdc + input.kusd;
  }
}

class IntentSettlementModel {
  private readonly intents = new Map<string, { owner: string; minOut: number; deadlineSlot: number; status: number; fillSlot: number }>();

  openIntent(caller: string, intentId: string, minOut: number, deadlineSlot: number): void {
    if (this.intents.has(intentId)) {
      throw new Error("intent exists");
    }
    requirePositiveSafeInteger(minOut, "invalid min out");
    requireNonNegativeSafeInteger(deadlineSlot, "invalid deadline");
    this.intents.set(intentId, { owner: caller, minOut, deadlineSlot, status: 1, fillSlot: 0 });
  }

  fillIntent(caller: string, intentId: string, amountOut: number, blockHeight: number): void {
    const intent = this.mustIntent(intentId);
    requireNonNegativeSafeInteger(blockHeight, "invalid block height");
    if (intent.status !== 1) {
      throw new Error("intent not open");
    }
    if (amountOut < intent.minOut) {
      throw new Error("insufficient output");
    }
    if (blockHeight > intent.deadlineSlot) {
      throw new Error("intent expired");
    }
    intent.status = 2;
    intent.fillSlot = blockHeight;
    void caller;
  }

  state(intentId: string): { status: number; fillSlot: number } {
    const intent = this.mustIntent(intentId);
    return { status: intent.status, fillSlot: intent.fillSlot };
  }

  private mustIntent(intentId: string): { owner: string; minOut: number; deadlineSlot: number; status: number; fillSlot: number } {
    const intent = this.intents.get(intentId);
    if (!intent) {
      throw new Error("intent missing");
    }
    return intent;
  }
}

class VaultManagerModel {
  private readonly vaults = new Set<string>();
  private readonly positionOwner = new Map<string, string>();
  private readonly positionVault = new Map<string, string>();
  private readonly positionShares = new Map<string, number>();
  private readonly requests = new Map<string, { owner: string; vault: string; shares: number; claimSlot: number; status: number }>();

  registerVault(vaultId: string): void {
    if (this.vaults.has(vaultId)) {
      throw new Error("vault exists");
    }
    this.vaults.add(vaultId);
  }

  deposit(caller: string, vaultId: string, positionId: string, amount: number): void {
    this.requireVault(vaultId);
    requirePositiveSafeInteger(amount, "invalid deposit");
    if (this.positionOwner.has(positionId)) {
      this.requirePosition(caller, vaultId, positionId);
    } else {
      this.positionOwner.set(positionId, caller);
      this.positionVault.set(positionId, vaultId);
      this.positionShares.set(positionId, 0);
    }
    this.positionShares.set(positionId, (this.positionShares.get(positionId) ?? 0) + amount);
  }

  requestRedeem(caller: string, vaultId: string, requestId: string, positionId: string, shares: number, claimSlot: number): void {
    this.requireVault(vaultId);
    if (this.requests.has(requestId)) {
      throw new Error("request exists");
    }
    requirePositiveSafeInteger(shares, "invalid shares");
    requireNonNegativeSafeInteger(claimSlot, "invalid claim slot");
    this.requirePosition(caller, vaultId, positionId);
    const currentShares = this.positionShares.get(positionId) ?? 0;
    if (currentShares < shares) {
      throw new Error("insufficient shares");
    }
    this.positionShares.set(positionId, currentShares - shares);
    this.requests.set(requestId, { owner: caller, vault: vaultId, shares, claimSlot, status: 1 });
  }

  claimRedeem(caller: string, requestId: string, blockHeight: number): void {
    const request = this.requests.get(requestId);
    if (!request) {
      throw new Error("request missing");
    }
    requireNonNegativeSafeInteger(blockHeight, "invalid block height");
    if (request.owner !== caller) {
      throw new Error("request owner mismatch");
    }
    if (request.status !== 1) {
      throw new Error("request not open");
    }
    if (blockHeight < request.claimSlot) {
      throw new Error("claim not ready");
    }
    request.status = 2;
  }

  shares(positionId: string): number {
    return this.positionShares.get(positionId) ?? 0;
  }

  private requireVault(vaultId: string): void {
    if (!this.vaults.has(vaultId)) {
      throw new Error("vault missing");
    }
  }

  private requirePosition(caller: string, vaultId: string, positionId: string): void {
    if (!this.positionOwner.has(positionId)) {
      throw new Error("position missing");
    }
    if (this.positionOwner.get(positionId) !== caller) {
      throw new Error("position owner mismatch");
    }
    if (this.positionVault.get(positionId) !== vaultId) {
      throw new Error("position vault mismatch");
    }
  }
}

class PortfolioMarginModel {
  private readonly marketOwner = new Map<string, string>();
  private readonly accountOwner = new Map<string, string>();
  private readonly collateral = new Map<string, number>();
  private readonly exposure = new Map<string, number>();

  registerMarket(caller: string, marketId: string): void {
    if (this.marketOwner.has(marketId)) {
      throw new Error("market exists");
    }
    this.marketOwner.set(marketId, caller);
  }

  depositCollateral(caller: string, accountKey: string, amount: number): void {
    requirePositiveSafeInteger(amount, "invalid collateral");
    if (this.accountOwner.has(accountKey)) {
      this.requireAccountOwner(caller, accountKey);
    } else {
      this.accountOwner.set(accountKey, caller);
    }
    this.collateral.set(accountKey, (this.collateral.get(accountKey) ?? 0) + amount);
  }

  lockExposure(caller: string, marketId: string, accountKey: string, exposureDelta: number): void {
    const owner = this.marketOwner.get(marketId);
    if (!owner) {
      throw new Error("market missing");
    }
    requireNonNegativeSafeInteger(exposureDelta, "invalid exposure");
    if (owner !== caller) {
      this.requireAccountOwner(caller, accountKey);
    }
    this.exposure.set(accountKey, (this.exposure.get(accountKey) ?? 0) + exposureDelta);
  }

  healthBps(accountKey: string): number {
    const exposure = this.exposure.get(accountKey) ?? 0;
    if (exposure === 0) {
      return 10_000;
    }
    return Math.floor(((this.collateral.get(accountKey) ?? 0) * 10_000) / exposure);
  }

  private requireAccountOwner(caller: string, accountKey: string): void {
    if (!this.accountOwner.has(accountKey)) {
      throw new Error("account missing");
    }
    if (this.accountOwner.get(accountKey) !== caller) {
      throw new Error("account owner mismatch");
    }
  }
}

describe("Audit fix simulations", () => {
  test("bridge settlement and governed activation require the proof authority", () => {
    const bridge = new ProofBoundBridge("proof-authority");
    expect(() => bridge.finalizeInbound("deployer")).toThrow("bridge proof authority mismatch");
    expect(() => bridge.activateRouteGoverned("route-owner")).toThrow("bridge proof authority mismatch");

    bridge.activateRouteGoverned("proof-authority", "route", "governance-message");
    bridge.finalizeInbound("proof-authority", "route", "message-1", 1);
    expect(() => bridge.setProofAuthority("owner", "attacker", "attacker")).toThrow("bridge owner mismatch");
    bridge.setProofAuthority("owner", "owner", "next-proof-authority");
    expect(() => bridge.finalizeInbound("proof-authority", "route", "message-2", 1)).toThrow("bridge proof authority mismatch");
    bridge.activateRouteGoverned("next-proof-authority", "route", "governance-message");
  });

  test("bridge rejects inbound replay, invalid settlement amounts, and owner control of proof-managed routes", () => {
    const bridge = new ProofBoundBridge("proof-authority");

    expect(() => bridge.finalizeInbound("proof-authority", "missing-route", "inbound-0", 1)).toThrow("route missing");
    bridge.activateRoute("direct-route", "route-owner");
    expect(() => bridge.finalizeInbound("proof-authority", "direct-route", "inbound-0", 0)).toThrow("invalid amount");
    bridge.finalizeInbound("proof-authority", "direct-route", "inbound-1", 100);
    expect(() => bridge.finalizeInbound("proof-authority", "direct-route", "inbound-1", 100)).toThrow("message consumed");

    bridge.pauseRoute("route-owner", "direct-route");
    bridge.activateRouteGoverned("proof-authority", "governed-route", "governance-message-1");
    expect(() => bridge.pauseRoute("route-owner", "governed-route")).toThrow("route owner mismatch");
    expect(() => bridge.pauseRoute("proof-authority", "governed-route")).toThrow("governed route is proof-managed");
    expect(() => bridge.activateRouteGoverned("proof-authority", "governed-route", "governance-message-2")).toThrow(
      "route governance mismatch"
    );
  });

  test("bridge inbound message ids are globally consumed across routes", () => {
    const bridge = new ProofBoundBridge("proof-authority");
    bridge.activateRoute("route-a", "owner-a");
    bridge.activateRoute("route-b", "owner-b");

    bridge.finalizeInbound("proof-authority", "route-a", "shared-message", 10);
    expect(() => bridge.finalizeInbound("proof-authority", "route-b", "shared-message", 10)).toThrow(
      "message consumed"
    );
    bridge.finalizeInbound("proof-authority", "route-b", "route-b-message", 10);
  });

  test("bridge proof authority rotation cannot be bypassed by stale signers", () => {
    const bridge = new ProofBoundBridge("proof-authority");
    bridge.activateRoute("direct-route", "route-owner");
    expect(() => bridge.setProofAuthority("owner", "owner", "")).toThrow("invalid proof authority");
    bridge.setProofAuthority("owner", "owner", "next-proof-authority");

    expect(() => bridge.finalizeInbound("proof-authority", "direct-route", "stale-finalize", 1)).toThrow(
      "bridge proof authority mismatch"
    );
    expect(() => bridge.activateRouteGoverned("proof-authority", "governed-route", "message")).toThrow(
      "bridge proof authority mismatch"
    );
    bridge.activateRouteGoverned("next-proof-authority", "governed-route", "message");
    bridge.finalizeInbound("next-proof-authority", "direct-route", "fresh-finalize", 1);
  });

  test("bridge rejects malformed route governance and settlement values without consuming messages", () => {
    const bridge = new ProofBoundBridge("proof-authority");
    expect(() => bridge.activateRoute("", "route-owner")).toThrow("invalid route");
    expect(() => bridge.activateRouteGoverned("proof-authority", "", "message")).toThrow("invalid route");
    expect(() => bridge.activateRouteGoverned("proof-authority", "route", "")).toThrow(
      "invalid governance message"
    );

    bridge.activateRoute("route", "route-owner");
    expect(() => bridge.finalizeInbound("proof-authority", "route", "", 1)).toThrow("invalid message");
    expect(() => bridge.finalizeInbound("proof-authority", "route", "fractional", 1.5)).toThrow("invalid amount");
    expect(() =>
      bridge.finalizeInbound("proof-authority", "route", "unsafe", Number.MAX_SAFE_INTEGER + 1)
    ).toThrow("invalid amount");
    bridge.finalizeInbound("proof-authority", "route", "fractional", 1);
    bridge.finalizeInbound("proof-authority", "route", "unsafe", 1);
  });

  test("margin exposure locks require the account owner or market owner", () => {
    const margin = new PortfolioMarginModel();
    margin.registerMarket("market-controller", "perps");
    margin.depositCollateral("alice", "alice-margin", 500);

    expect(() => margin.lockExposure("attacker", "perps", "alice-margin", 10_000)).toThrow("account owner mismatch");
    expect(() => margin.lockExposure("attacker", "perps", "missing-margin", 10)).toThrow("account missing");

    margin.lockExposure("market-controller", "perps", "alice-margin", 2_500);
    expect(margin.healthBps("alice-margin")).toBe(2_000);
    margin.lockExposure("alice", "perps", "alice-margin", 500);
    expect(margin.healthBps("alice-margin")).toBe(1_666);
  });

  test("vault redemptions are scoped to position owner, position vault, and block-height claim readiness", () => {
    const vault = new VaultManagerModel();
    vault.registerVault("vault-a");
    vault.registerVault("vault-b");
    vault.deposit("alice", "vault-a", "position-a", 100);

    expect(() => vault.deposit("bob", "vault-a", "position-a", 1)).toThrow("position owner mismatch");
    expect(() => vault.requestRedeem("bob", "vault-a", "redeem-bob", "position-a", 10, 5)).toThrow(
      "position owner mismatch"
    );
    expect(() => vault.requestRedeem("alice", "vault-b", "redeem-wrong-vault", "position-a", 10, 5)).toThrow(
      "position vault mismatch"
    );

    vault.requestRedeem("alice", "vault-a", "redeem-a", "position-a", 40, 10);
    expect(vault.shares("position-a")).toBe(60);
    expect(() => vault.claimRedeem("alice", "redeem-a", 9)).toThrow("claim not ready");
    expect(() => vault.claimRedeem("bob", "redeem-a", 10)).toThrow("request owner mismatch");
    vault.claimRedeem("alice", "redeem-a", 10);
    expect(() => vault.claimRedeem("alice", "redeem-a", 11)).toThrow("request not open");
  });

  test("intent fills use block height for expiry and recorded fill slot", () => {
    const intents = new IntentSettlementModel();
    intents.openIntent("alice", "intent-expired", 90, 10);
    expect(() => intents.fillIntent("solver", "intent-expired", 95, 11)).toThrow("intent expired");

    intents.openIntent("alice", "intent-live", 90, 20);
    expect(() => intents.fillIntent("solver", "intent-live", 89, 12)).toThrow("insufficient output");
    intents.fillIntent("solver", "intent-live", 95, 20);
    expect(intents.state("intent-live")).toEqual({ status: 2, fillSlot: 20 });
  });

  test("launchpad requires explicit factory init, allocation-only buys, and block-height vesting", () => {
    expect(() => launchpadContribute()).toThrow("use contribute_recorded");

    const factory = new LaunchpadFactoryModel();
    expect(() =>
      factory.initSale("owner", "sale-a", {
        unitPrice: 10,
        softCap: 100,
        hardCap: 1_000,
        claimStartSlot: 10,
        claimEndSlot: 20
      })
    ).toThrow("factory not initialized");
    factory.initFactory("owner");
    expect(() => factory.initFactory("owner")).toThrow("factory initialized");
    expect(() =>
      factory.initSale("attacker", "sale-a", {
        unitPrice: 10,
        softCap: 100,
        hardCap: 1_000,
        claimStartSlot: 10,
        claimEndSlot: 20
      })
    ).toThrow("factory owner mismatch");
    expect(() =>
      factory.initSale("owner", "bad-window", {
        unitPrice: 10,
        softCap: 100,
        hardCap: 1_000,
        claimStartSlot: 20,
        claimEndSlot: 10
      })
    ).toThrow("invalid claim window");
    factory.initSale("owner", "sale-a", {
      unitPrice: 10,
      softCap: 100,
      hardCap: 1_000,
      claimStartSlot: 10,
      claimEndSlot: 20
    });
    expect(() =>
      factory.initSale("owner", "sale-a", {
        unitPrice: 10,
        softCap: 100,
        hardCap: 1_000,
        claimStartSlot: 10,
        claimEndSlot: 20
      })
    ).toThrow("sale exists");

    expect(factory.contributeRecorded("alice", "sale-a", "alloc-a", 250)).toBe(25);
    expect(() => factory.contributeRecorded("alice", "sale-a", "alloc-a", 250)).toThrow("allocation exists");
    expect(() => factory.contributeRecorded("dust", "sale-a", "alloc-dust", 9)).toThrow("zero sale output");
    expect(() => factory.contributeRecorded("bob", "sale-a", "alloc-b", 1_000)).toThrow("hard cap");
    expect(factory.contributeRecorded("bob", "sale-a", "alloc-b", 750)).toBe(75);
    expect(() => factory.claimAllocation("alice", "alloc-a", 15)).toThrow("sale open");

    factory.closeSale("owner", "sale-a");
    expect(() => factory.closeSale("owner", "sale-a")).toThrow("sale closed");
    expect(() => factory.depositClaimInventory("attacker", "sale-a", 25)).toThrow("sale owner mismatch");
    factory.depositClaimInventory("owner", "sale-a", 25);
    expect(() => factory.claimAllocation("bob", "alloc-a", 20)).toThrow("buyer mismatch");
    expect(() => factory.claimAllocation("alice", "alloc-a", 9)).toThrow("nothing claimable");
    expect(factory.claimAllocation("alice", "alloc-a", 15)).toBe(12);
    expect(factory.claimAllocation("alice", "alloc-a", 20)).toBe(13);
    expect(() => factory.claimAllocation("alice", "alloc-a", 21)).toThrow("nothing claimable");
    expect(() => factory.claimAllocation("bob", "alloc-b", 20)).toThrow("insufficient claim inventory");
  });

  test("launchpad failed-sale refunds cannot be replayed or mixed with claims", () => {
    const factory = new LaunchpadFactoryModel();
    factory.initFactory("owner");
    factory.initSale("owner", "sale-failed", {
      unitPrice: 10,
      softCap: 500,
      hardCap: 1_000,
      claimStartSlot: 1,
      claimEndSlot: 1
    });
    expect(factory.contributeRecorded("alice", "sale-failed", "alloc-failed", 100)).toBe(10);
    expect(() => factory.refundAllocation("alice", "alloc-failed")).toThrow("sale open");
    factory.closeSale("owner", "sale-failed");
    expect(() => factory.claimAllocation("alice", "alloc-failed", 1)).toThrow("sale failed");
    expect(() => factory.refundAllocation("bob", "alloc-failed")).toThrow("buyer mismatch");
    expect(factory.refundAllocation("alice", "alloc-failed")).toBe(100);
    expect(() => factory.refundAllocation("alice", "alloc-failed")).toThrow("allocation refunded");

    factory.initSale("owner", "sale-success", {
      unitPrice: 10,
      softCap: 100,
      hardCap: 1_000,
      claimStartSlot: 1,
      claimEndSlot: 1
    });
    expect(factory.contributeRecorded("carol", "sale-success", "alloc-success", 100)).toBe(10);
    factory.closeSale("owner", "sale-success");
    expect(() => factory.refundAllocation("carol", "alloc-success")).toThrow("sale successful");
  });

  test("launchpad rejects invalid config, missing ids, and cross-sale allocation collisions", () => {
    const factory = new LaunchpadFactoryModel();
    factory.initFactory("owner");

    expect(() =>
      factory.initSale("owner", "bad-price", {
        unitPrice: 0,
        softCap: 100,
        hardCap: 1_000,
        claimStartSlot: 0,
        claimEndSlot: 10
      })
    ).toThrow("invalid unit price");
    expect(() =>
      factory.initSale("owner", "bad-cap", {
        unitPrice: 10,
        softCap: 0,
        hardCap: 1_000,
        claimStartSlot: 0,
        claimEndSlot: 10
      })
    ).toThrow("invalid cap");
    expect(() =>
      factory.initSale("owner", "negative-window", {
        unitPrice: 10,
        softCap: 100,
        hardCap: 1_000,
        claimStartSlot: -1,
        claimEndSlot: 10
      })
    ).toThrow("invalid claim window");
    expect(() => factory.contributeRecorded("alice", "missing-sale", "missing-alloc", 100)).toThrow("sale missing");
    expect(() => factory.claimAllocation("alice", "missing-alloc", 10)).toThrow("allocation missing");
    expect(() => factory.refundAllocation("alice", "missing-alloc")).toThrow("allocation missing");

    factory.initSale("owner", "sale-a", {
      unitPrice: 10,
      softCap: 100,
      hardCap: 200,
      claimStartSlot: 0,
      claimEndSlot: 10
    });
    factory.initSale("owner", "sale-b", {
      unitPrice: 10,
      softCap: 100,
      hardCap: 200,
      claimStartSlot: 0,
      claimEndSlot: 10
    });
    expect(() => factory.contributeRecorded("alice", "sale-a", "alloc-zero", 0)).toThrow("invalid payment");
    expect(() => factory.contributeRecorded("alice", "sale-a", "alloc-negative", -1)).toThrow("invalid payment");
    expect(() => factory.depositClaimInventory("owner", "sale-a", 0)).toThrow("invalid amount");
    expect(() => factory.closeSale("attacker", "sale-a")).toThrow("sale owner mismatch");

    expect(factory.contributeRecorded("alice", "sale-a", "shared-alloc", 100)).toBe(10);
    expect(() => factory.contributeRecorded("bob", "sale-b", "shared-alloc", 100)).toThrow("allocation exists");
  });

  test("launchpad rejects fractional slot, cap, payment, and post-close contribution abuse", () => {
    const factory = new LaunchpadFactoryModel();
    factory.initFactory("owner");
    expect(() =>
      factory.initSale("owner", "fractional-price", {
        unitPrice: 10.5,
        softCap: 100,
        hardCap: 1_000,
        claimStartSlot: 0,
        claimEndSlot: 10
      })
    ).toThrow("invalid unit price");
    expect(() =>
      factory.initSale("owner", "fractional-cap", {
        unitPrice: 10,
        softCap: 100,
        hardCap: 1_000.5,
        claimStartSlot: 0,
        claimEndSlot: 10
      })
    ).toThrow("invalid cap");
    expect(() =>
      factory.initSale("owner", "fractional-slot", {
        unitPrice: 10,
        softCap: 100,
        hardCap: 1_000,
        claimStartSlot: 0,
        claimEndSlot: 10.5
      })
    ).toThrow("invalid claim window");

    factory.initSale("owner", "sale", {
      unitPrice: 10,
      softCap: 100,
      hardCap: 1_000,
      claimStartSlot: 10,
      claimEndSlot: 20
    });
    expect(() => factory.contributeRecorded("alice", "sale", "fractional-payment", 100.5)).toThrow("invalid payment");
    expect(factory.contributeRecorded("alice", "sale", "alloc-a", 100)).toBe(10);
    factory.closeSale("owner", "sale");
    expect(() => factory.contributeRecorded("bob", "sale", "alloc-b", 100)).toThrow("sale closed");
    factory.depositClaimInventory("owner", "sale", 10);
    expect(() => factory.claimAllocation("alice", "alloc-a", 10.5)).toThrow("invalid block height");
    expect(() => factory.claimAllocation("alice", "alloc-a", -1)).toThrow("invalid block height");
  });

  test("launchpad failed contributions and claims do not reserve ids or mutate inventory", () => {
    const factory = new LaunchpadFactoryModel();
    factory.initFactory("owner");
    factory.initSale("owner", "sale", {
      unitPrice: 10,
      softCap: 100,
      hardCap: 150,
      claimStartSlot: 0,
      claimEndSlot: 10
    });

    expect(() => factory.contributeRecorded("alice", "sale", "reusable", 200)).toThrow("hard cap");
    expect(factory.contributeRecorded("alice", "sale", "reusable", 100)).toBe(10);
    factory.closeSale("owner", "sale");
    factory.depositClaimInventory("owner", "sale", 5);
    expect(() => factory.claimAllocation("bob", "reusable", 10)).toThrow("buyer mismatch");
    expect(() => factory.claimAllocation("alice", "reusable", 10)).toThrow("insufficient claim inventory");
    factory.depositClaimInventory("owner", "sale", 5);
    expect(factory.claimAllocation("alice", "reusable", 10)).toBe(10);
  });

  test("DLMM direct partial fills remain allowed while router paths revert before retaining dust", () => {
    expect(dlmmSwapExactIn(100, 70, false)).toEqual({ used: 70, output: 70 });
    expect(() => dlmmSwapExactIn(100, 70, true)).toThrow("router partial fill");
    expect(() => dlmmSwapExactIn(100, 0, true)).toThrow("insufficient input used");
    expect(() => dlmmSwapExactIn(0, 100, true)).toThrow("invalid amount");
  });

  test("DLMM router exact fills succeed while malformed liquidity cannot spend", () => {
    expect(dlmmSwapExactIn(100, 100, true)).toEqual({ used: 100, output: 100 });
    expect(dlmmSwapExactIn(100, 150, true)).toEqual({ used: 100, output: 100 });
    expect(() => dlmmSwapExactIn(100, -1, false)).toThrow("insufficient input used");
    expect(() => dlmmSwapExactIn(-1, 100, true)).toThrow("invalid amount");
    expect(() => dlmmSwapExactIn(1.5, 100, true)).toThrow("invalid amount");
    expect(() => dlmmSwapExactIn(100, 99.5, true)).toThrow("invalid fill");
  });

  test("n3x fee reserves are excluded from redeemable basket backing and can be claimed independently", () => {
    const n3x = new N3xFeeReserveModel(100, 100);
    expect(() => n3x.claimFees()).toThrow("no fees");
    expect(() => n3x.mint({ usdt: -1, usdc: 0, kusd: 0 })).toThrow("negative usdt");
    expect(() => n3x.mint({ usdt: 0, usdc: 0, kusd: 0 })).toThrow("zero mint");
    const minted = n3x.mint({ usdt: 10_000, usdc: 5_000, kusd: 5_000 });
    expect(minted).toBe(19_800);
    expect(n3x.redeemableBacking()).toBe(19_800);
    expect(n3x.vaultBacking()).toBe(20_000);
    expect(() => n3x.claimFeesAs("attacker")).toThrow("hub owner mismatch");
    expect(() => n3x.redeem(minted + 1)).toThrow("insufficient supply");
    expect(() => n3x.redeem(0)).toThrow("invalid n3x_amount");

    const redeemed = n3x.redeem(minted);
    expect(redeemed.fees).toEqual({ usdt: 99, usdc: 49, kusd: 49 });
    expect(n3x.redeemableBacking()).toBe(0);
    expect(n3x.vaultBacking()).toBe(397);

    const claimed = n3x.claimFees();
    expect(claimed).toEqual({ usdt: 199, usdc: 99, kusd: 99 });
    expect(n3x.redeemableBacking()).toBe(0);
    expect(n3x.vaultBacking()).toBe(0);
    expect(() => n3x.claimFees()).toThrow("no fees");
  });

  test("n3x partial redemptions cannot drain fee reserves as basket backing", () => {
    const n3x = new N3xFeeReserveModel(100, 100);
    const minted = n3x.mint({ usdt: 10_000, usdc: 0, kusd: 0 });
    expect(minted).toBe(9_900);
    expect(n3x.redeemableBacking()).toBe(9_900);
    expect(n3x.vaultBacking()).toBe(10_000);

    const firstRedeem = n3x.redeem(4_950);
    expect(firstRedeem.paid).toEqual({ usdt: 4_901, usdc: 0, kusd: 0 });
    expect(firstRedeem.fees).toEqual({ usdt: 49, usdc: 0, kusd: 0 });
    expect(n3x.redeemableBacking()).toBe(4_950);
    expect(n3x.vaultBacking()).toBe(5_099);

    const secondRedeem = n3x.redeem(4_950);
    expect(secondRedeem.paid).toEqual({ usdt: 4_901, usdc: 0, kusd: 0 });
    expect(secondRedeem.fees).toEqual({ usdt: 49, usdc: 0, kusd: 0 });
    expect(n3x.redeemableBacking()).toBe(0);
    expect(n3x.claimFees()).toEqual({ usdt: 198, usdc: 0, kusd: 0 });
    expect(n3x.vaultBacking()).toBe(0);
  });

  test("n3x rejects invalid fee settings and zero-output dust redemptions without mutating backing", () => {
    expect(() => new N3xFeeReserveModel(-1, 0)).toThrow("invalid fee");
    expect(() => new N3xFeeReserveModel(0, 10_000)).toThrow("invalid fee");
    expect(() => new N3xFeeReserveModel(0.5, 0)).toThrow("invalid fee");

    const n3x = new N3xFeeReserveModel(0, 0);
    expect(n3x.mint({ usdt: 1, usdc: 1, kusd: 0 })).toBe(2);
    expect(() => n3x.redeem(1)).toThrow("zero redemption");
    expect(n3x.redeemableBacking()).toBe(2);
    expect(n3x.vaultBacking()).toBe(2);
    expect(n3x.redeem(2).paid).toEqual({ usdt: 1, usdc: 1, kusd: 0 });
  });

  test("n3x rejects fractional and unsafe amounts without moving basket or reserves", () => {
    const n3x = new N3xFeeReserveModel(100, 100);
    expect(() => n3x.mint({ usdt: 1.5, usdc: 0, kusd: 0 })).toThrow("invalid usdt");
    expect(() => n3x.mint({ usdt: Number.MAX_SAFE_INTEGER + 1, usdc: 0, kusd: 0 })).toThrow("invalid usdt");
    expect(n3x.redeemableBacking()).toBe(0);
    expect(n3x.vaultBacking()).toBe(0);

    const minted = n3x.mint({ usdt: 10_000, usdc: 0, kusd: 0 });
    expect(() => n3x.redeem(1.5)).toThrow("invalid n3x_amount");
    expect(() => n3x.redeem(Number.MAX_SAFE_INTEGER + 1)).toThrow("invalid n3x_amount");
    expect(n3x.redeemableBacking()).toBe(9_900);
    expect(n3x.vaultBacking()).toBe(10_000);
    expect(n3x.redeem(minted).paid).toEqual({ usdt: 9_801, usdc: 0, kusd: 0 });
  });

  test("n3x failed fee claims and invalid per-asset deposits leave reserves intact", () => {
    const n3x = new N3xFeeReserveModel(100, 100);
    expect(() => n3x.mint({ usdt: 0, usdc: -1, kusd: 0 })).toThrow("negative usdc");
    expect(() => n3x.mint({ usdt: 0, usdc: 0, kusd: 1.5 })).toThrow("invalid kusd");
    expect(n3x.mint({ usdt: 0, usdc: 10_000, kusd: 0 })).toBe(9_900);
    expect(() => n3x.claimFeesAs("attacker")).toThrow("hub owner mismatch");
    expect(n3x.vaultBacking()).toBe(10_000);
    expect(n3x.claimFees()).toEqual({ usdt: 0, usdc: 100, kusd: 0 });
    expect(n3x.vaultBacking()).toBe(9_900);
  });
});
