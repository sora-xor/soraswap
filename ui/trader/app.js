const DEFAULT_VISIBLE_FILL_LIMIT = 120;
const DEFAULT_GAS_LIMIT = 100000;
const DEFAULT_UNIFIED_ACTIVITY_LIMIT = 28;
const DEFAULT_CANDLE_LIMIT = 96;
const DEFAULT_MODULE_ACTIVITY_LIMIT = 12;
const LIVE_FALLBACK_REFRESH_INTERVAL_MS = 15000;
const LIVE_EVENT_REFRESH_DEBOUNCE_MS = 1500;
const LIVE_RECONNECT_DELAY_MS = 2500;
const DEFAULT_TRANSACTION_POLL_INTERVAL_MS = 1000;
const DEFAULT_TRANSACTION_POLL_TIMEOUT_MS = 45000;
const STORAGE_KEYS = {
  selectedEnvironment: "soraswap.trader.selectedEnvironment.v1",
  authorityByEnvironment: "soraswap.trader.authorityByEnvironment.v1",
  liveModeEnabled: "soraswap.trader.liveModeEnabled.v1",
};
const SUCCESS_STATUSES = new Set(["Approved", "Committed", "Applied"]);
const FAILURE_STATUSES = new Set(["Rejected", "Expired"]);
const PRODUCT_DEFINITIONS = [
  { key: "swaps", label: "Swaps", contractKey: "dlmm.dlmm_router" },
  { key: "batchAuction", label: "Batch Auction", contractKey: "batch_amm.epoch_auction" },
  { key: "n3x", label: "n3x", contractKey: "n3x.n3x_hub" },
  { key: "perps", label: "Perps", contractKey: "perps.perps_engine" },
  { key: "farms", label: "Farms", contractKey: "farms.farm" },
  { key: "launchpad", label: "Launchpad", contractKey: "launchpad.sale_factory" },
  { key: "options", label: "Options", contractKey: "options.factory" },
  { key: "cover", label: "Cover", contractKey: "cover.policy_manager" },
  { key: "intents", label: "Intents", contractKey: "intents.settlement_router" },
  { key: "vaults", label: "Vaults", contractKey: "vaults.manager" },
  { key: "escrow", label: "Escrow", contractKey: "escrow.conditional_escrow" },
  { key: "operators", label: "Operators", contractKey: "operators.registry" },
  { key: "margin", label: "Margin", contractKey: "margin.portfolio_margin" },
  { key: "rwa", label: "RWA", contractKey: "rwa.market" },
  { key: "dlmmHooks", label: "DLMM Hooks", contractKey: "dlmm_hooks.hook_manager" },
];
const ACTION_RAILS = {
  swaps: {
    title: "Route Swap",
    copy: "Submit directly against the deployed router using the rollup-backed journal and candle surfaces.",
    actions: [
      {
        key: "swap_buy",
        label: "Buy Quote",
        submitLabel: "Submit Buy",
        entrypoint: "route_swap",
        fields: [
          { key: "amount_in", label: "Spend Base Amount", type: "number", min: 1, step: 1, defaultValue: 100 },
          { key: "min_out", label: "Minimum Quote Out", type: "number", min: 0, step: 1, defaultValue: 95 },
        ],
        buildPayload: (draft) => ({
          amount_in: normalizeInteger(draft.amount_in),
          input_is_base: 1,
          min_out: normalizeInteger(draft.min_out),
        }),
      },
      {
        key: "swap_sell",
        label: "Sell Quote",
        submitLabel: "Submit Sell",
        entrypoint: "route_swap",
        fields: [
          { key: "amount_in", label: "Sell Quote Amount", type: "number", min: 1, step: 1, defaultValue: 60 },
          { key: "min_out", label: "Minimum Base Out", type: "number", min: 0, step: 1, defaultValue: 64 },
        ],
        buildPayload: (draft) => ({
          amount_in: normalizeInteger(draft.amount_in),
          input_is_base: 0,
          min_out: normalizeInteger(draft.min_out),
        }),
      },
    ],
  },
  batchAuction: {
    title: "Epoch Auction",
    copy: "Submit, cancel, and settle xor/n3x batch auction orders against the trigger-closed epoch.",
    actions: [
      {
        key: "auction_bid",
        label: "Bid",
        submitLabel: "Submit Bid",
        entrypoint: "submit_order",
        fields: [
          { key: "order_id", label: "Order ID", type: "text", defaultValue: "bid-1" },
          { key: "amount", label: "Quote Amount", type: "number", min: 1, step: 1, defaultValue: 100 },
          { key: "limit_tick", label: "Limit Tick", type: "number", min: 1, step: 1, defaultValue: 1_000_000 },
        ],
        buildPayload: (draft) => ({
          order_id: String(draft.order_id || "bid-1").trim(),
          side: 1,
          amount: normalizeInteger(draft.amount),
          limit_tick: normalizeInteger(draft.limit_tick),
        }),
      },
      {
        key: "auction_ask",
        label: "Ask",
        submitLabel: "Submit Ask",
        entrypoint: "submit_order",
        fields: [
          { key: "order_id", label: "Order ID", type: "text", defaultValue: "ask-1" },
          { key: "amount", label: "Base Amount", type: "number", min: 1, step: 1, defaultValue: 100 },
          { key: "limit_tick", label: "Limit Tick", type: "number", min: 1, step: 1, defaultValue: 1_000_000 },
        ],
        buildPayload: (draft) => ({
          order_id: String(draft.order_id || "ask-1").trim(),
          side: 2,
          amount: normalizeInteger(draft.amount),
          limit_tick: normalizeInteger(draft.limit_tick),
        }),
      },
      {
        key: "auction_cancel",
        label: "Cancel",
        submitLabel: "Cancel Order",
        entrypoint: "cancel_order",
        fields: [
          { key: "order_id", label: "Order ID", type: "text", defaultValue: "bid-1" },
        ],
        buildPayload: (draft) => ({
          order_id: String(draft.order_id || "bid-1").trim(),
        }),
      },
      {
        key: "auction_settle",
        label: "Settle",
        submitLabel: "Settle Order",
        entrypoint: "settle_order",
        fields: [
          { key: "order_id", label: "Order ID", type: "text", defaultValue: "bid-1" },
        ],
        buildPayload: (draft) => ({
          order_id: String(draft.order_id || "bid-1").trim(),
        }),
      },
    ],
  },
  n3x: {
    title: "n3x Rails",
    copy: "Mint and redeem the stable basket from the same cockpit used for wallet-level trader activity.",
    actions: [
      {
        key: "n3x_mint",
        label: "Mint",
        submitLabel: "Submit Mint",
        entrypoint: "deposit_and_mint",
        fields: [
          { key: "usdt_in", label: "USDT In", type: "number", min: 0, step: 1, defaultValue: 160 },
          { key: "usdc_in", label: "USDC In", type: "number", min: 0, step: 1, defaultValue: 40 },
          { key: "kusd_in", label: "KUSD In", type: "number", min: 0, step: 1, defaultValue: 20 },
        ],
        buildPayload: (draft) => ({
          usdt_in: normalizeInteger(draft.usdt_in),
          usdc_in: normalizeInteger(draft.usdc_in),
          kusd_in: normalizeInteger(draft.kusd_in),
        }),
      },
      {
        key: "n3x_redeem",
        label: "Redeem",
        submitLabel: "Submit Redeem",
        entrypoint: "burn_and_redeem",
        fields: [
          { key: "n3x_amount", label: "n3x Amount", type: "number", min: 1, step: 1, defaultValue: 180 },
        ],
        buildPayload: (draft) => ({
          n3x_amount: normalizeInteger(draft.n3x_amount),
        }),
      },
    ],
  },
  perps: {
    title: "Perps Rails",
    copy: "Open, modify, margin, and close perp positions without leaving the trader cockpit.",
    actions: [
      {
        key: "perps_open",
        label: "Open",
        submitLabel: "Open Position",
        entrypoint: "open_position",
        fields: [
          { key: "market_id", label: "Market ID", type: "number", min: 1, step: 1, defaultValue: 1 },
          { key: "position_id", label: "Position ID", type: "number", min: 1, step: 1, defaultValue: 8 },
          { key: "size", label: "Size", type: "number", min: 1, step: 1, defaultValue: 520 },
          { key: "margin", label: "Margin", type: "number", min: 1, step: 1, defaultValue: 120 },
        ],
        buildPayload: (draft) => ({
          market_id: normalizeInteger(draft.market_id),
          position_id: normalizeInteger(draft.position_id),
          size: normalizeInteger(draft.size),
          margin: normalizeInteger(draft.margin),
        }),
      },
      {
        key: "perps_modify",
        label: "Modify",
        submitLabel: "Submit Modify",
        entrypoint: "modify_position",
        fields: [
          { key: "position_id", label: "Position ID", type: "number", min: 1, step: 1, defaultValue: 7 },
          { key: "size_delta", label: "Size Delta", type: "number", min: 1, step: 1, defaultValue: 40 },
          { key: "margin_delta", label: "Margin Delta", type: "number", min: 1, step: 1, defaultValue: 10 },
        ],
        buildPayload: (draft) => ({
          position_id: normalizeInteger(draft.position_id),
          size_delta: normalizeInteger(draft.size_delta),
          margin_delta: normalizeInteger(draft.margin_delta),
        }),
      },
      {
        key: "perps_add_margin",
        label: "Add Margin",
        submitLabel: "Add Margin",
        entrypoint: "add_margin",
        fields: [
          { key: "position_id", label: "Position ID", type: "number", min: 1, step: 1, defaultValue: 7 },
          { key: "amount", label: "Margin Amount", type: "number", min: 1, step: 1, defaultValue: 24 },
        ],
        buildPayload: (draft) => ({
          position_id: normalizeInteger(draft.position_id),
          amount: normalizeInteger(draft.amount),
        }),
      },
      {
        key: "perps_remove_margin",
        label: "Remove Margin",
        submitLabel: "Remove Margin",
        entrypoint: "remove_margin",
        fields: [
          { key: "position_id", label: "Position ID", type: "number", min: 1, step: 1, defaultValue: 7 },
          { key: "amount", label: "Margin Amount", type: "number", min: 1, step: 1, defaultValue: 12 },
        ],
        buildPayload: (draft) => ({
          position_id: normalizeInteger(draft.position_id),
          amount: normalizeInteger(draft.amount),
        }),
      },
      {
        key: "perps_close",
        label: "Close",
        submitLabel: "Close Position",
        entrypoint: "close_position",
        fields: [
          { key: "position_id", label: "Position ID", type: "number", min: 1, step: 1, defaultValue: 7 },
        ],
        buildPayload: (draft) => ({
          position_id: normalizeInteger(draft.position_id),
        }),
      },
    ],
  },
  farms: {
    title: "Farm Rails",
    copy: "Stake, unwind, and claim from the live farm surface without leaving the trading frame.",
    actions: [
      {
        key: "farms_stake",
        label: "Stake",
        submitLabel: "Submit Stake",
        entrypoint: "stake",
        fields: [
          { key: "position", label: "Position", type: "text", defaultValue: "yield-alpha" },
          { key: "amount", label: "Amount", type: "number", min: 1, step: 1, defaultValue: 120 },
        ],
        buildPayload: (draft) => ({
          position: String(draft.position || "").trim(),
          amount: normalizeInteger(draft.amount),
        }),
      },
      {
        key: "farms_unstake",
        label: "Unstake",
        submitLabel: "Submit Unstake",
        entrypoint: "unstake",
        fields: [
          { key: "position", label: "Position", type: "text", defaultValue: "yield-alpha" },
          { key: "amount", label: "Amount", type: "number", min: 1, step: 1, defaultValue: 80 },
        ],
        buildPayload: (draft) => ({
          position: String(draft.position || "").trim(),
          amount: normalizeInteger(draft.amount),
        }),
      },
      {
        key: "farms_claim",
        label: "Claim",
        submitLabel: "Claim Rewards",
        entrypoint: "claim",
        fields: [
          { key: "position", label: "Position", type: "text", defaultValue: "yield-alpha" },
        ],
        buildPayload: (draft) => ({
          position: String(draft.position || "").trim(),
        }),
      },
    ],
  },
  launchpad: {
    title: "Launchpad Rails",
    copy: "Contribute, claim, or unwind a launchpad allocation from the same wallet-focused cockpit.",
    actions: [
      {
        key: "launchpad_contribute",
        label: "Contribute",
        submitLabel: "Submit Contribution",
        entrypoint: "contribute_recorded",
        fields: [
          { key: "sale", label: "Sale", type: "text", defaultValue: "seed-alpha" },
          { key: "allocation", label: "Allocation", type: "text", defaultValue: "alloc-alpha" },
          { key: "payment_amount", label: "Payment Amount", type: "number", min: 1, step: 1, defaultValue: 260 },
        ],
        buildPayload: (draft) => ({
          sale: String(draft.sale || "").trim(),
          allocation: String(draft.allocation || "").trim(),
          payment_amount: normalizeInteger(draft.payment_amount),
        }),
      },
      {
        key: "launchpad_claim",
        label: "Claim",
        submitLabel: "Claim Allocation",
        entrypoint: "claim_allocation",
        fields: [
          { key: "sale", label: "Sale", type: "text", defaultValue: "seed-alpha" },
          { key: "allocation", label: "Allocation", type: "text", defaultValue: "alloc-alpha" },
        ],
        buildPayload: (draft) => ({
          sale: String(draft.sale || "").trim(),
          allocation: String(draft.allocation || "").trim(),
        }),
      },
      {
        key: "launchpad_refund",
        label: "Refund",
        submitLabel: "Refund Allocation",
        entrypoint: "refund_allocation",
        fields: [
          { key: "sale", label: "Sale", type: "text", defaultValue: "seed-alpha" },
          { key: "allocation", label: "Allocation", type: "text", defaultValue: "alloc-alpha" },
        ],
        buildPayload: (draft) => ({
          sale: String(draft.sale || "").trim(),
          allocation: String(draft.allocation || "").trim(),
        }),
      },
    ],
  },
  options: {
    title: "Options Rails",
    copy: "Buy, record shouts, and exercise from one public options surface.",
    actions: [
      {
        key: "options_buy_shout",
        label: "Buy Shout",
        submitLabel: "Buy Shout",
        entrypoint: "buy_shout",
        fields: [
          { key: "series_id", label: "Series ID", type: "number", min: 1, step: 1, defaultValue: 12 },
          { key: "position_id", label: "Position ID", type: "number", min: 1, step: 1, defaultValue: 79 },
          { key: "notional", label: "Notional", type: "number", min: 1, step: 1, defaultValue: 220 },
          { key: "premium_paid", label: "Premium Paid", type: "number", min: 1, step: 1, defaultValue: 16 },
        ],
        buildPayload: (draft) => ({
          series_id: normalizeInteger(draft.series_id),
          position_id: normalizeInteger(draft.position_id),
          notional: normalizeInteger(draft.notional),
          premium_paid: normalizeInteger(draft.premium_paid),
        }),
      },
      {
        key: "options_buy_outperformance",
        label: "Buy Outperformance",
        submitLabel: "Buy Outperformance",
        entrypoint: "buy_outperformance",
        fields: [
          { key: "series_id", label: "Series ID", type: "number", min: 1, step: 1, defaultValue: 12 },
          { key: "position_id", label: "Position ID", type: "number", min: 1, step: 1, defaultValue: 80 },
          { key: "notional", label: "Notional", type: "number", min: 1, step: 1, defaultValue: 240 },
          { key: "premium_paid", label: "Premium Paid", type: "number", min: 1, step: 1, defaultValue: 19 },
        ],
        buildPayload: (draft) => ({
          series_id: normalizeInteger(draft.series_id),
          position_id: normalizeInteger(draft.position_id),
          notional: normalizeInteger(draft.notional),
          premium_paid: normalizeInteger(draft.premium_paid),
        }),
      },
      {
        key: "options_record_shout",
        label: "Record Shout",
        submitLabel: "Record Shout",
        entrypoint: "record_shout",
        fields: [
          { key: "series_id", label: "Series ID", type: "number", min: 1, step: 1, defaultValue: 12 },
          { key: "position_id", label: "Position ID", type: "number", min: 1, step: 1, defaultValue: 77 },
          { key: "shout_price", label: "Shout Price", type: "number", min: 1, step: 1, defaultValue: 11350 },
        ],
        buildPayload: (draft) => ({
          series_id: normalizeInteger(draft.series_id),
          position_id: normalizeInteger(draft.position_id),
          shout_price: normalizeInteger(draft.shout_price),
        }),
      },
      {
        key: "options_exercise_shout",
        label: "Exercise Shout",
        submitLabel: "Exercise Shout",
        entrypoint: "exercise_shout_position",
        fields: [
          { key: "series_id", label: "Series ID", type: "number", min: 1, step: 1, defaultValue: 12 },
          { key: "position_id", label: "Position ID", type: "number", min: 1, step: 1, defaultValue: 77 },
        ],
        buildPayload: (draft) => ({
          series_id: normalizeInteger(draft.series_id),
          position_id: normalizeInteger(draft.position_id),
        }),
      },
      {
        key: "options_exercise_outperformance",
        label: "Exercise Outperformance",
        submitLabel: "Exercise Outperformance",
        entrypoint: "exercise_outperformance_position",
        fields: [
          { key: "series_id", label: "Series ID", type: "number", min: 1, step: 1, defaultValue: 12 },
          { key: "position_id", label: "Position ID", type: "number", min: 1, step: 1, defaultValue: 80 },
        ],
        buildPayload: (draft) => ({
          series_id: normalizeInteger(draft.series_id),
          position_id: normalizeInteger(draft.position_id),
        }),
      },
    ],
  },
  cover: {
    title: "Cover Rails",
    copy: "Open policies and route claims from the same trader frame used for market activity.",
    actions: [
      {
        key: "cover_register",
        label: "Register",
        submitLabel: "Open Policy",
        entrypoint: "register_policy",
        fields: [
          { key: "policy_id", label: "Policy ID", type: "number", min: 1, step: 1, defaultValue: 6 },
          { key: "covered_notional", label: "Covered Notional", type: "number", min: 1, step: 1, defaultValue: 1100 },
          { key: "payout_amount", label: "Payout Amount", type: "number", min: 1, step: 1, defaultValue: 260 },
          { key: "premium_paid", label: "Premium Paid", type: "number", min: 1, step: 1, defaultValue: 32 },
        ],
        buildPayload: (draft) => ({
          policy_id: normalizeInteger(draft.policy_id),
          covered_notional: normalizeInteger(draft.covered_notional),
          payout_amount: normalizeInteger(draft.payout_amount),
          premium_paid: normalizeInteger(draft.premium_paid),
        }),
      },
      {
        key: "cover_claim",
        label: "Claim",
        submitLabel: "Route Claim",
        entrypoint: "route_claim",
        fields: [
          { key: "policy_id", label: "Policy ID", type: "number", min: 1, step: 1, defaultValue: 5 },
          { key: "payout_amount", label: "Payout Amount", type: "number", min: 1, step: 1, defaultValue: 180 },
        ],
        buildPayload: (draft) => ({
          policy_id: normalizeInteger(draft.policy_id),
          payout_amount: normalizeInteger(draft.payout_amount),
        }),
      },
    ],
  },
  intents: {
    title: "Intent Rails",
    copy: "Open, cancel, and fill solver intents from the trader cockpit.",
    actions: [
      {
        key: "intent_open",
        label: "Open",
        submitLabel: "Open Intent",
        entrypoint: "open_intent",
        fields: [
          { key: "intent_id", label: "Intent ID", type: "text", defaultValue: "intent-1" },
          { key: "amount_in", label: "Amount In", type: "number", min: 1, step: 1, defaultValue: 100 },
          { key: "min_out", label: "Minimum Out", type: "number", min: 1, step: 1, defaultValue: 97 },
          { key: "solver_fee_bps", label: "Solver Fee BPS", type: "number", min: 0, step: 1, defaultValue: 25 },
        ],
        buildPayload: (draft) => ({
          intent_id: String(draft.intent_id || "intent-1"),
          input_asset: "xor#universal",
          output_asset: "usdt#soraswap.universal",
          amount_in: normalizeInteger(draft.amount_in),
          min_out: normalizeInteger(draft.min_out),
          solver_fee_bps: normalizeInteger(draft.solver_fee_bps),
          deadline_slot: 1_000_000_000,
          nonce: 1,
        }),
      },
      {
        key: "intent_fill",
        label: "Fill",
        submitLabel: "Fill Intent",
        entrypoint: "fill_intent",
        fields: [
          { key: "intent_id", label: "Intent ID", type: "text", defaultValue: "intent-1" },
          { key: "amount_out", label: "Amount Out", type: "number", min: 1, step: 1, defaultValue: 99 },
        ],
        buildPayload: (draft) => ({
          intent_id: String(draft.intent_id || "intent-1"),
          amount_out: normalizeInteger(draft.amount_out),
        }),
      },
    ],
  },
  vaults: {
    title: "Vault Rails",
    copy: "Register vaults, deposit, and claim async redemptions.",
    actions: [
      {
        key: "vault_deposit",
        label: "Deposit",
        submitLabel: "Deposit",
        entrypoint: "deposit",
        fields: [
          { key: "vault_id", label: "Vault ID", type: "text", defaultValue: "n3x-savings" },
          { key: "position_id", label: "Position ID", type: "text", defaultValue: "pos-1" },
          { key: "amount", label: "Amount", type: "number", min: 1, step: 1, defaultValue: 250 },
        ],
        buildPayload: (draft) => ({
          vault_id: String(draft.vault_id || "n3x-savings"),
          position_id: String(draft.position_id || "pos-1"),
          amount: normalizeInteger(draft.amount),
        }),
      },
      {
        key: "vault_redeem",
        label: "Redeem",
        submitLabel: "Request Redeem",
        entrypoint: "request_redeem",
        fields: [
          { key: "vault_id", label: "Vault ID", type: "text", defaultValue: "n3x-savings" },
          { key: "request_id", label: "Request ID", type: "text", defaultValue: "redeem-1" },
          { key: "position_id", label: "Position ID", type: "text", defaultValue: "pos-1" },
          { key: "shares", label: "Shares", type: "number", min: 1, step: 1, defaultValue: 40 },
        ],
        buildPayload: (draft) => ({
          vault_id: String(draft.vault_id || "n3x-savings"),
          request_id: String(draft.request_id || "redeem-1"),
          position_id: String(draft.position_id || "pos-1"),
          shares: normalizeInteger(draft.shares),
          claim_slot: 1,
        }),
      },
    ],
  },
  escrow: {
    title: "Conditional Escrow",
    copy: "Open, accept, cancel, and refund trigger-resident escrow agreements.",
    actions: [
      {
        key: "escrow_open",
        label: "Open",
        submitLabel: "Open Escrow",
        entrypoint: "open_escrow",
        fields: [
          { key: "escrow_id", label: "Escrow ID", type: "text", defaultValue: "escrow-1" },
          { key: "taker", label: "Taker", type: "text", defaultValue: "i105fixturetaker@universal" },
          { key: "asset", label: "Asset", type: "text", defaultValue: "n3x#soraswap.universal" },
          { key: "amount", label: "Amount", type: "number", min: 1, step: 1, defaultValue: 100 },
          { key: "expiry_slot", label: "Expiry Slot", type: "number", min: 0, step: 1, defaultValue: 1_000_000 },
          { key: "condition_code", label: "Condition Code", type: "number", min: 1, step: 1, defaultValue: 7 },
        ],
        buildPayload: (draft) => ({
          escrow_id: String(draft.escrow_id || "escrow-1").trim(),
          taker: String(draft.taker || "").trim(),
          asset: String(draft.asset || "").trim(),
          amount: normalizeInteger(draft.amount),
          expiry_slot: normalizeInteger(draft.expiry_slot),
          condition_code: normalizeInteger(draft.condition_code),
        }),
      },
      {
        key: "escrow_accept",
        label: "Accept",
        submitLabel: "Accept Escrow",
        entrypoint: "accept_escrow",
        fields: [
          { key: "escrow_id", label: "Escrow ID", type: "text", defaultValue: "escrow-1" },
          { key: "condition_code", label: "Condition Code", type: "number", min: 1, step: 1, defaultValue: 7 },
        ],
        buildPayload: (draft) => ({
          escrow_id: String(draft.escrow_id || "escrow-1").trim(),
          condition_code: normalizeInteger(draft.condition_code),
        }),
      },
      {
        key: "escrow_cancel",
        label: "Cancel",
        submitLabel: "Cancel Escrow",
        entrypoint: "cancel_escrow",
        fields: [
          { key: "escrow_id", label: "Escrow ID", type: "text", defaultValue: "escrow-1" },
        ],
        buildPayload: (draft) => ({
          escrow_id: String(draft.escrow_id || "escrow-1").trim(),
        }),
      },
      {
        key: "escrow_refund",
        label: "Refund",
        submitLabel: "Refund Expired",
        entrypoint: "refund_expired",
        fields: [
          { key: "escrow_id", label: "Escrow ID", type: "text", defaultValue: "escrow-1" },
        ],
        buildPayload: (draft) => ({
          escrow_id: String(draft.escrow_id || "escrow-1").trim(),
        }),
      },
    ],
  },
  operators: {
    title: "Operator Rails",
    copy: "Register bonded operators, post bond, heartbeat, and claim fees.",
    actions: [
      {
        key: "operator_bond",
        label: "Bond",
        submitLabel: "Post Bond",
        entrypoint: "bond",
        fields: [
          { key: "service", label: "Service", type: "text", defaultValue: "solver" },
          { key: "amount", label: "Amount", type: "number", min: 1, step: 1, defaultValue: 1000 },
        ],
        buildPayload: (draft) => ({
          service: String(draft.service || "solver"),
          amount: normalizeInteger(draft.amount),
        }),
      },
      {
        key: "operator_heartbeat",
        label: "Heartbeat",
        submitLabel: "Heartbeat",
        entrypoint: "heartbeat",
        fields: [
          { key: "service", label: "Service", type: "text", defaultValue: "solver" },
          { key: "health_bps", label: "Health BPS", type: "number", min: 0, step: 1, defaultValue: 9700 },
        ],
        buildPayload: (draft) => ({
          service: String(draft.service || "solver"),
          slot: 1,
          health_bps: normalizeInteger(draft.health_bps),
          fees_accrued: 0,
        }),
      },
    ],
  },
  margin: {
    title: "Margin Rails",
    copy: "Deposit collateral, lock exposure, and route liquidation checks.",
    actions: [
      {
        key: "margin_deposit",
        label: "Deposit",
        submitLabel: "Deposit Collateral",
        entrypoint: "deposit_collateral",
        fields: [
          { key: "account_key", label: "Account Key", type: "text", defaultValue: "alice" },
          { key: "amount", label: "Amount", type: "number", min: 1, step: 1, defaultValue: 500 },
        ],
        buildPayload: (draft) => ({
          account_key: String(draft.account_key || "alice"),
          amount: normalizeInteger(draft.amount),
        }),
      },
      {
        key: "margin_liquidate",
        label: "Liquidate",
        submitLabel: "Liquidate",
        entrypoint: "liquidate_account",
        fields: [
          { key: "account_key", label: "Account Key", type: "text", defaultValue: "alice" },
        ],
        buildPayload: (draft) => ({
          account_key: String(draft.account_key || "alice"),
        }),
      },
    ],
  },
  rwa: {
    title: "RWA Rails",
    copy: "Issue markets, report NAV, request redemptions, and settle controller actions.",
    actions: [
      {
        key: "rwa_issue",
        label: "Issue",
        submitLabel: "Issue Lot",
        entrypoint: "issue_lot",
        fields: [
          { key: "market_id", label: "Market ID", type: "text", defaultValue: "tbill-1" },
          { key: "initial_nav_per_share", label: "NAV", type: "number", min: 1, step: 1, defaultValue: 101 },
          { key: "total_shares", label: "Shares", type: "number", min: 1, step: 1, defaultValue: 10000 },
        ],
        buildPayload: (draft) => ({
          market_id: String(draft.market_id || "tbill-1"),
          share_asset: "rwa_tbill#soraswap.universal",
          nav_asset: "usdt#soraswap.universal",
          initial_nav_per_share: normalizeInteger(draft.initial_nav_per_share),
          total_shares: normalizeInteger(draft.total_shares),
        }),
      },
      {
        key: "rwa_redeem",
        label: "Redeem",
        submitLabel: "Request Redemption",
        entrypoint: "request_redemption",
        fields: [
          { key: "market_id", label: "Market ID", type: "text", defaultValue: "tbill-1" },
          { key: "redemption_id", label: "Redemption ID", type: "text", defaultValue: "r-1" },
          { key: "shares", label: "Shares", type: "number", min: 1, step: 1, defaultValue: 250 },
        ],
        buildPayload: (draft) => ({
          market_id: String(draft.market_id || "tbill-1"),
          redemption_id: String(draft.redemption_id || "r-1"),
          shares: normalizeInteger(draft.shares),
        }),
      },
    ],
  },
  dlmmHooks: {
    title: "DLMM Hook Rails",
    copy: "Configure hooks and place limit/TWAMM orders for the DLMM surface.",
    actions: [
      {
        key: "hook_limit",
        label: "Limit",
        submitLabel: "Place Limit",
        entrypoint: "place_limit_order",
        fields: [
          { key: "order_id", label: "Order ID", type: "text", defaultValue: "order-1" },
          { key: "hook_id", label: "Hook ID", type: "text", defaultValue: "limit" },
          { key: "amount_in", label: "Amount In", type: "number", min: 1, step: 1, defaultValue: 100 },
          { key: "min_out", label: "Min Out", type: "number", min: 1, step: 1, defaultValue: 99 },
        ],
        buildPayload: (draft) => ({
          order_id: String(draft.order_id || "order-1"),
          hook_id: String(draft.hook_id || "limit"),
          amount_in: normalizeInteger(draft.amount_in),
          min_out: normalizeInteger(draft.min_out),
        }),
      },
      {
        key: "hook_twamm",
        label: "TWAMM",
        submitLabel: "Schedule TWAMM",
        entrypoint: "schedule_twamm_v2",
        fields: [
          { key: "order_id", label: "Order ID", type: "text", defaultValue: "twamm-1" },
          { key: "input_is_base", label: "Input Is Base", type: "number", min: 0, step: 1, defaultValue: 1 },
          { key: "total_in", label: "Total In", type: "number", min: 1, step: 1, defaultValue: 1_000 },
          { key: "slice_in", label: "Slice In", type: "number", min: 1, step: 1, defaultValue: 100 },
          { key: "min_total_out", label: "Min Total Out", type: "number", min: 0, step: 1, defaultValue: 950 },
          { key: "interval_slots", label: "Interval Slots", type: "number", min: 1, step: 1, defaultValue: 2 },
          { key: "start_slot", label: "Start Slot", type: "number", min: 0, step: 1, defaultValue: 1 },
        ],
        buildPayload: (draft) => ({
          order_id: String(draft.order_id || "twamm-1").trim(),
          input_is_base: normalizeInteger(draft.input_is_base),
          total_in: normalizeInteger(draft.total_in),
          slice_in: normalizeInteger(draft.slice_in),
          min_total_out: normalizeInteger(draft.min_total_out),
          interval_slots: normalizeInteger(draft.interval_slots),
          start_slot: normalizeInteger(draft.start_slot),
        }),
      },
      {
        key: "hook_twamm_cancel",
        label: "Cancel TWAMM",
        submitLabel: "Cancel TWAMM",
        entrypoint: "cancel_twamm",
        fields: [
          { key: "order_id", label: "Order ID", type: "text", defaultValue: "twamm-1" },
        ],
        buildPayload: (draft) => ({
          order_id: String(draft.order_id || "twamm-1").trim(),
        }),
      },
      {
        key: "hook_twamm_claim",
        label: "Claim TWAMM",
        submitLabel: "Claim TWAMM",
        entrypoint: "claim_twamm",
        fields: [
          { key: "order_id", label: "Order ID", type: "text", defaultValue: "twamm-1" },
        ],
        buildPayload: (draft) => ({
          order_id: String(draft.order_id || "twamm-1").trim(),
        }),
      },
    ],
  },
};

const state = {
  catalog: null,
  environments: [],
  currentEnvironment: null,
  currentContract: null,
  selectedActionKey: "swap_buy",
  tradeDrafts: {},
  selectedModuleKey: "swaps",
  activityFilterKey: "all",
  liveModeEnabled: loadStorage(STORAGE_KEYS.liveModeEnabled, true) !== false,
  liveConnectionState: "connecting",
  lastRefreshMs: null,
  refreshToken: 0,
  workspace: null,
  local: {
    selectedEnvironment: loadStorage(STORAGE_KEYS.selectedEnvironment, ""),
    authorityByEnvironment: loadStorage(STORAGE_KEYS.authorityByEnvironment, {}),
  },
  live: {
    eventSource: null,
    debounceTimer: null,
    fallbackTimer: null,
    reconnectTimer: null,
    streamKey: "",
  },
};

const environmentSelect = document.querySelector("#environment-select");
const authorityInput = document.querySelector("#authority-input");
const refreshWorkspaceButton = document.querySelector("#refresh-workspace");
const statusBanner = document.querySelector("#status-banner");
const liveStatus = document.querySelector("#live-status");
const liveDetail = document.querySelector("#live-detail");
const lastRefreshDisplay = document.querySelector("#last-refresh");
const liveToggle = document.querySelector("#live-toggle");

const routerContractLabel = document.querySelector("#router-contract-label");
const routerAddress = document.querySelector("#router-address");
const routerTorii = document.querySelector("#router-torii");
const routerCallAccess = document.querySelector("#router-call-access");
const historyHeadDisplay = document.querySelector("#history-head");
const historyCountDisplay = document.querySelector("#history-count");
const recentFills = document.querySelector("#recent-fills");
const moduleRadar = document.querySelector("#module-radar");

const pairSymbol = document.querySelector("#pair-symbol");
const pairCopy = document.querySelector("#pair-copy");
const metricAvgEntry = document.querySelector("#metric-avg-entry");
const metricAvgExit = document.querySelector("#metric-avg-exit");
const metricOpenPosition = document.querySelector("#metric-open-position");
const metricRealizedPnl = document.querySelector("#metric-realized-pnl");
const metricTotalPnl = document.querySelector("#metric-total-pnl");

const priceChart = document.querySelector("#price-chart");
const chartEmpty = document.querySelector("#chart-empty");
const moduleGrid = document.querySelector("#module-grid");
const focusTitle = document.querySelector("#focus-title");
const focusCopy = document.querySelector("#focus-copy");
const focusHero = document.querySelector("#focus-hero");
const focusContract = document.querySelector("#focus-contract");
const focusMetrics = document.querySelector("#focus-metrics");
const focusFeedCount = document.querySelector("#focus-feed-count");
const focusFeed = document.querySelector("#focus-feed");
const journalBody = document.querySelector("#journal-body");
const activityFilterBar = document.querySelector("#activity-filter-bar");
const activityBody = document.querySelector("#activity-body");

const tradeKicker = document.querySelector("#trade-kicker");
const tradeTitle = document.querySelector("#trade-title");
const tradeCopy = document.querySelector("#trade-copy");
const tradeModeBar = document.querySelector("#trade-mode-bar");
const tradeFields = document.querySelector("#trade-fields");
const tradeGasLimitInput = document.querySelector("#trade-gas-limit-input");
const tradePreview = document.querySelector("#trade-preview");
const tradeSubmit = document.querySelector("#trade-submit");
const tradeResult = document.querySelector("#trade-result");
const signedConfirmationDialog = document.querySelector("#signed-confirmation-dialog");
const confirmationDetailList = document.querySelector("#confirmation-detail-list");
const confirmationWarning = document.querySelector("#confirmation-warning");
const confirmationPayload = document.querySelector("#confirmation-payload");

const insightLastPrice = document.querySelector("#insight-last-price");
const insightUnrealizedPnl = document.querySelector("#insight-unrealized-pnl");
const insightWinRate = document.querySelector("#insight-win-rate");
const insightCushion = document.querySelector("#insight-cushion");
const insightBaseSpent = document.querySelector("#insight-base-spent");
const insightBaseRealized = document.querySelector("#insight-base-realized");
const insightNote = document.querySelector("#insight-note");

function loadStorage(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) {
      return fallback;
    }
    return JSON.parse(raw);
  } catch (error) {
    console.warn(`failed to load ${key}`, error);
    return fallback;
  }
}

function saveStorage(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch (error) {
    console.warn(`failed to store ${key}`, error);
  }
}

function setBanner(element, text, kind = "muted") {
  element.textContent = text;
  element.className = `banner ${kind}`;
}

function sanitizeJsonForDisplay(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => sanitizeJsonForDisplay(entry));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => !["private_key", "privateKey", "secret", "mnemonic"].includes(key))
        .map(([key, entry]) => [key, sanitizeJsonForDisplay(entry)]),
    );
  }
  return value;
}

function confirmationValue(value) {
  if (value === undefined || value === null || value === "") {
    return "-";
  }
  return String(value);
}

function renderConfirmationDetails(rows) {
  confirmationDetailList.replaceChildren();
  rows.forEach(([label, value]) => {
    const term = document.createElement("dt");
    term.textContent = label;
    const detail = document.createElement("dd");
    detail.textContent = confirmationValue(value);
    confirmationDetailList.append(term, detail);
  });
}

function confirmSignedMutation(details) {
  if (!signedConfirmationDialog || typeof signedConfirmationDialog.showModal !== "function") {
    return Promise.resolve(window.confirm("Confirm signed call?"));
  }

  renderConfirmationDetails([
    ["Environment", details.environment],
    ["Authority", details.authority],
    ["Contract", details.contract],
    ["Address", details.contractAddress],
    ["Action", details.action],
    ["Entrypoint", details.entrypoint],
    [details.requestPath ? "Request Path" : "Gas Limit", details.requestPath || details.gasLimit],
  ]);
  confirmationPayload.textContent = JSON.stringify(sanitizeJsonForDisplay(details.payload ?? {}), null, 2);
  if (details.warningText) {
    confirmationWarning.textContent = details.warningText;
    confirmationWarning.hidden = false;
  } else {
    confirmationWarning.textContent = "";
    confirmationWarning.hidden = true;
  }

  signedConfirmationDialog.returnValue = "";
  return new Promise((resolve) => {
    const handleClose = () => {
      signedConfirmationDialog.removeEventListener("close", handleClose);
      resolve(signedConfirmationDialog.returnValue === "confirm");
    };
    signedConfirmationDialog.addEventListener("close", handleClose);
    signedConfirmationDialog.showModal();
  });
}

function renderLiveStatus() {
  const stateClass =
    state.liveConnectionState === "live"
      ? "live-live"
      : state.liveConnectionState === "paused"
        ? "live-paused"
        : state.liveConnectionState === "error"
          ? "live-error"
          : "";
  liveStatus.className = stateClass;
  const labelMap = {
    live: "Live",
    paused: "Paused",
    connecting: "Connecting…",
    error: "Reconnecting…",
  };
  liveStatus.textContent = labelMap[state.liveConnectionState] || "Connecting…";
  if (!state.liveModeEnabled) {
    liveDetail.textContent = "Live follow is paused. The workspace will only change on manual refresh or signed actions.";
    liveToggle.textContent = "Resume Live";
  } else if (state.liveConnectionState === "live") {
    liveDetail.textContent = "Following Torii events and refreshing the cockpit when the chain moves.";
    liveToggle.textContent = "Pause Live";
  } else if (state.liveConnectionState === "error") {
    liveDetail.textContent = "Event stream dropped. A slower polling fallback is active until the stream reconnects.";
    liveToggle.textContent = "Pause Live";
  } else {
    liveDetail.textContent = "Opening Torii event stream.";
    liveToggle.textContent = "Pause Live";
  }

  if (Number.isFinite(state.lastRefreshMs)) {
    lastRefreshDisplay.textContent = `Last refresh ${formatTimestamp(state.lastRefreshMs, "-")}`;
  } else {
    lastRefreshDisplay.textContent = "No refresh yet.";
  }
}

function buildUrl(path, params = {}) {
  const url = new URL(path, window.location.origin);
  Object.entries(params).forEach(([key, value]) => {
    if (value === undefined || value === null || value === "") {
      return;
    }
    url.searchParams.set(key, String(value));
  });
  return url.toString();
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  let payload = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (error) {
      throw new Error(`expected JSON from ${url} but received: ${text.slice(0, 200)}`);
    }
  }
  if (!response.ok) {
    const message =
      payload?.error
      || payload?.message
      || payload?.response_text
      || `request to ${url} failed with status ${response.status}`;
    throw new Error(message);
  }
  return payload;
}

function clearLiveTimer(timerName) {
  const timer = state.live[timerName];
  if (timer) {
    window.clearTimeout(timer);
    window.clearInterval(timer);
    state.live[timerName] = null;
  }
}

function closeLiveEventSource() {
  if (state.live.eventSource) {
    state.live.eventSource.close();
    state.live.eventSource = null;
  }
}

function stopLiveInfrastructure() {
  clearLiveTimer("debounceTimer");
  clearLiveTimer("fallbackTimer");
  clearLiveTimer("reconnectTimer");
  closeLiveEventSource();
  state.live.streamKey = "";
}

function scheduleRefreshFromLive() {
  if (!state.liveModeEnabled || !state.currentEnvironment || !currentAuthority()) {
    return;
  }
  clearLiveTimer("debounceTimer");
  state.live.debounceTimer = window.setTimeout(() => {
    state.live.debounceTimer = null;
    refreshWorkspace({ reloadCatalog: false });
  }, LIVE_EVENT_REFRESH_DEBOUNCE_MS);
}

function startLiveFallbackPolling(streamKey) {
  clearLiveTimer("fallbackTimer");
  state.live.fallbackTimer = window.setInterval(() => {
    if (!state.liveModeEnabled || state.live.streamKey !== streamKey || !state.currentEnvironment || !currentAuthority()) {
      return;
    }
    refreshWorkspace({ reloadCatalog: false });
  }, LIVE_FALLBACK_REFRESH_INTERVAL_MS);
}

function ensureLiveFollow() {
  const environmentName = state.currentEnvironment?.name || "";
  const authority = currentAuthority();
  const streamKey = `${environmentName}|${authority}`;

  if (!state.liveModeEnabled || !environmentName || !authority) {
    stopLiveInfrastructure();
    state.liveConnectionState = state.liveModeEnabled ? "connecting" : "paused";
    renderLiveStatus();
    return;
  }

  if (state.live.streamKey === streamKey && state.live.eventSource) {
    return;
  }

  stopLiveInfrastructure();
  state.live.streamKey = streamKey;
  state.liveConnectionState = "connecting";
  renderLiveStatus();

  startLiveFallbackPolling(streamKey);

  if (typeof EventSource !== "function") {
    state.liveConnectionState = "error";
    renderLiveStatus();
    return;
  }

  const url = buildUrl("/api/contracts/events/sse", {
    environment: environmentName,
  });
  const source = new EventSource(url);
  state.live.eventSource = source;

  source.onopen = () => {
    if (state.live.streamKey !== streamKey) {
      source.close();
      return;
    }
    state.liveConnectionState = "live";
    renderLiveStatus();
  };

  source.onmessage = () => {
    if (state.live.streamKey !== streamKey) {
      return;
    }
    scheduleRefreshFromLive();
  };
  source.addEventListener("pipeline", () => {
    if (state.live.streamKey !== streamKey) {
      return;
    }
    scheduleRefreshFromLive();
  });

  source.onerror = () => {
    if (state.live.streamKey !== streamKey) {
      return;
    }
    closeLiveEventSource();
    state.liveConnectionState = "error";
    renderLiveStatus();
    clearLiveTimer("reconnectTimer");
    state.live.reconnectTimer = window.setTimeout(() => {
      state.live.reconnectTimer = null;
      if (state.liveModeEnabled && state.live.streamKey === streamKey) {
        ensureLiveFollow();
      }
    }, LIVE_RECONNECT_DELAY_MS);
  };
}

function requireProxySuccess(result, label) {
  if (result?.ok === true) {
    return result;
  }
  const message =
    result?.error
    || result?.response_json?.error
    || result?.response_text
    || `${label} failed`;
  throw new Error(message);
}

function unwrapProxyValue(value) {
  if (
    value
    && typeof value === "object"
    && !Array.isArray(value)
    && Object.prototype.hasOwnProperty.call(value, "result")
  ) {
    return value.result;
  }
  return value;
}

async function fetchCatalog() {
  return requestJson("/api/catalog");
}

async function fetchProxyGet(path, params) {
  return requestJson(buildUrl(path, params));
}

async function fetchViewBatch(environment, authority, items, gasLimit = DEFAULT_GAS_LIMIT) {
  return requestJson("/api/view/batch", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      environment,
      authority,
      gas_limit: gasLimit,
      items,
    }),
  });
}

async function fetchProxyPost(path, payload) {
  return requestJson(path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
}

async function callView(environment, contractAddress, authority, entrypoint, payload) {
  const result = requireProxySuccess(
    await fetchProxyPost("/api/view", {
      environment,
      authority,
      contract_address: contractAddress,
      entrypoint,
      payload,
    }),
    `view ${entrypoint}`,
  );
  return unwrapProxyValue(result.response_json);
}

async function listContractActivity(environment, contractAddress, authority, options = {}) {
  const result = requireProxySuccess(
    await fetchProxyGet("/api/contracts/events", {
      environment,
      authority,
      contract_address: contractAddress,
      event_kind: options.contractEntrypoint,
      result_ok: true,
      limit: options.limit ?? DEFAULT_VISIBLE_FILL_LIMIT * 2,
    }),
    "contract events",
  );
  const payload = unwrapProxyValue(result.response_json) || {};
  return Array.isArray(payload.items) ? payload.items.slice() : [];
}

async function fetchTransactionStatus(environment, txHashHex) {
  const result = requireProxySuccess(
    await fetchProxyGet("/api/pipeline/transactions/status", {
      environment,
      hash: txHashHex,
    }),
    "transaction status",
  );
  return unwrapProxyValue(result.response_json) || {};
}

function normalizeInteger(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return Math.trunc(parsed);
    }
  }
  return null;
}

function normalizePrice(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return null;
}

function normalizeRollupFills(items) {
  return (Array.isArray(items) ? items : [])
    .map((item) => {
      const inputIsBase = normalizeInteger(item?.inputIsBase ?? item?.input_is_base);
      const amountIn = normalizeInteger(item?.amountIn ?? item?.amount_in);
      const amountOut = normalizeInteger(item?.amountOut ?? item?.amount_out);
      const minOut = normalizeInteger(item?.minOut ?? item?.min_out);
      const price = normalizePrice(item?.price);
      return {
        recordId: normalizeInteger(item?.recordId ?? item?.record_id),
        trader: typeof item?.trader === "string" ? item.trader : String(item?.authority || ""),
        inputIsBase,
        amountIn,
        amountOut,
        minOut,
        side: item?.side || (inputIsBase === 1 ? "buy" : "sell"),
        price: Number.isFinite(price)
          ? price
          : (inputIsBase === 1
            ? (amountIn || 0) / Math.max(amountOut || 0, 1)
            : (amountOut || 0) / Math.max(amountIn || 0, 1)),
        protectionRatio: normalizePrice(item?.protectionRatio ?? item?.protection_ratio),
        timestampMs: normalizeInteger(item?.timestampMs ?? item?.timestamp_ms),
        executionHash: typeof item?.executionHash === "string"
          ? item.executionHash
          : (typeof item?.tx_hash_hex === "string" ? item.tx_hash_hex : null),
      };
    })
    .filter((item) => Number.isFinite(item.recordId) && Number.isFinite(item.amountIn) && Number.isFinite(item.amountOut))
    .sort((left, right) => (right.timestampMs || right.recordId || 0) - (left.timestampMs || left.recordId || 0));
}

function normalizeRollupCandles(items) {
  return (Array.isArray(items) ? items : [])
    .map((item) => ({
      bucketStartMs: normalizeInteger(item?.bucketStartMs ?? item?.bucket_start_ms),
      open: normalizePrice(item?.open),
      high: normalizePrice(item?.high),
      low: normalizePrice(item?.low),
      close: normalizePrice(item?.close),
      buyCount: normalizeInteger(item?.buyCount ?? item?.buy_count) ?? 0,
      sellCount: normalizeInteger(item?.sellCount ?? item?.sell_count) ?? 0,
      baseVolume: normalizePrice(item?.baseVolume ?? item?.base_volume) ?? 0,
      quoteVolume: normalizePrice(item?.quoteVolume ?? item?.quote_volume) ?? 0,
    }))
    .filter((item) => Number.isFinite(item.bucketStartMs) && Number.isFinite(item.close))
    .sort((left, right) => (right.bucketStartMs || 0) - (left.bucketStartMs || 0));
}

function normalizeTraderActivityItems(items) {
  return (Array.isArray(items) ? items : [])
    .map((item) => ({
      moduleKey: typeof item?.moduleKey === "string"
        ? item.moduleKey
        : (typeof item?.module === "string" ? item.module : "swaps"),
      moduleLabel: typeof item?.moduleLabel === "string"
        ? item.moduleLabel
        : humanizeEntrypoint(item?.moduleKey || item?.module || "swaps"),
      timestampMs: normalizeInteger(item?.timestampMs ?? item?.timestamp_ms),
      action: typeof item?.action === "string" ? item.action : humanizeEntrypoint(item?.event_kind || "action"),
      exposure: typeof item?.exposure === "string" ? item.exposure : summarizePayload(item?.payload),
      context: typeof item?.context === "string" ? item.context : "-",
      executionHash: typeof item?.executionHash === "string"
        ? item.executionHash
        : (typeof item?.tx_hash_hex === "string" ? item.tx_hash_hex : "-"),
    }))
    .sort((left, right) => (right.timestampMs || 0) - (left.timestampMs || 0))
    .slice(0, DEFAULT_UNIFIED_ACTIVITY_LIMIT);
}

function normalizeModuleCards(items) {
  return (Array.isArray(items) ? items : []).map((item) => ({
    key: typeof item?.key === "string" ? item.key : "swaps",
    label: typeof item?.label === "string" ? item.label : "Swaps",
    contractKey: typeof item?.contractKey === "string" ? item.contractKey : moduleContractKey(item?.key || "swaps"),
    contractAddress: typeof item?.contractAddress === "string" ? item.contractAddress : null,
    statusTone: typeof item?.statusTone === "string" ? item.statusTone : "watch",
    statusLabel: typeof item?.statusLabel === "string" ? item.statusLabel : "Watching",
    hero: typeof item?.hero === "string" ? item.hero : "-",
    blurb: typeof item?.blurb === "string" ? item.blurb : "",
    radarValue: typeof item?.radarValue === "string" ? item.radarValue : "-",
    metrics: Array.isArray(item?.metrics)
      ? item.metrics.map((metric) => ({
        label: typeof metric?.label === "string" ? metric.label : "Metric",
        value: typeof metric?.value === "string" ? metric.value : "-",
      }))
      : [],
  }));
}

function normalizeActivityItems(items) {
  return items
    .map((item) => {
      const timestampMs = normalizeInteger(item?.timestamp_ms);
      return {
        authority: typeof item?.authority === "string" ? item.authority : null,
        timestampMs,
        entrypointHash: typeof item?.tx_hash_hex === "string"
          ? item.tx_hash_hex
          : (typeof item?.entrypoint_hash === "string" ? item.entrypoint_hash : null),
        contractAddress: typeof item?.contract_address === "string" ? item.contract_address : null,
        contractAlias: typeof item?.contract_alias === "string" ? item.contract_alias : null,
        contractEntrypoint: typeof item?.event_kind === "string"
          ? item.event_kind
          : (typeof item?.contract_entrypoint === "string" ? item.contract_entrypoint : null),
        resultOk: item?.result_ok === undefined ? null : Boolean(item.result_ok),
        contractPayload: item?.payload && typeof item.payload === "object"
          ? item.payload
          : (item?.contract_payload && typeof item.contract_payload === "object"
            ? item.contract_payload
            : null),
        blockHeight: normalizeInteger(item?.block_height),
        module: typeof item?.module === "string" ? item.module : null,
        participants: Array.isArray(item?.participants) ? item.participants.filter((value) => typeof value === "string") : [],
        assetIds: Array.isArray(item?.asset_ids) ? item.asset_ids.filter((value) => typeof value === "string") : [],
        provenance: typeof item?.provenance === "string" ? item.provenance : null,
      };
    })
    .sort((left, right) => (right.timestampMs || 0) - (left.timestampMs || 0));
}

function normalizeHistoryRecord(recordId, raw) {
  const value = unwrapProxyValue(raw);
  let tuple = null;
  if (Array.isArray(value)) {
    tuple = value;
  } else if (value && typeof value === "object") {
    tuple = [
      value.trader ?? value.authority,
      value.input_is_base,
      value.amount_in,
      value.amount_out,
      value.min_out,
    ];
  }
  if (!tuple || tuple.length < 5) {
    throw new Error(`swap history record ${recordId} returned an unexpected shape`);
  }
  const trader = typeof tuple[0] === "string" ? tuple[0] : String(tuple[0] ?? "");
  const inputIsBase = normalizeInteger(tuple[1]);
  const amountIn = normalizeInteger(tuple[2]);
  const amountOut = normalizeInteger(tuple[3]);
  const minOut = normalizeInteger(tuple[4]);
  if (!trader || inputIsBase === null || amountIn === null || amountOut === null || minOut === null) {
    throw new Error(`swap history record ${recordId} is incomplete`);
  }
  return {
    recordId,
    trader,
    inputIsBase,
    amountIn,
    amountOut,
    minOut,
  };
}

function currentAuthority() {
  return authorityInput.value.trim();
}

function currentSymbols() {
  const assets = state.workspace?.assets;
  const baseAssetId = assets?.baseAssetId || "xor#universal";
  const quoteAssetId = assets?.quoteAssetId || "quote";
  return {
    baseAssetId,
    quoteAssetId,
    baseSymbol: assetTicker(baseAssetId),
    quoteSymbol: assetTicker(quoteAssetId),
  };
}

function assetTicker(assetId) {
  const text = String(assetId || "").trim();
  if (!text) {
    return "?";
  }
  const symbol = text.split("#")[0] || text;
  return symbol.toUpperCase();
}

function truncateMiddle(value, left = 10, right = 6) {
  if (!value || value.length <= left + right + 1) {
    return value || "-";
  }
  return `${value.slice(0, left)}…${value.slice(-right)}`;
}

function formatCount(value) {
  if (!Number.isFinite(value)) {
    return "-";
  }
  return new Intl.NumberFormat().format(value);
}

function formatAmount(value, maximumFractionDigits = 4) {
  if (!Number.isFinite(value)) {
    return "-";
  }
  return new Intl.NumberFormat(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits,
  }).format(value);
}

function formatAssetAmount(value, symbol, maximumFractionDigits = 4) {
  if (!Number.isFinite(value)) {
    return "-";
  }
  return `${formatAmount(value, maximumFractionDigits)} ${symbol}`;
}

function formatSignedAssetAmount(value, symbol) {
  if (!Number.isFinite(value)) {
    return "-";
  }
  const sign = value > 0 ? "+" : value < 0 ? "-" : "";
  return `${sign}${formatAmount(Math.abs(value), 4)} ${symbol}`;
}

function formatPercent(ratio) {
  if (!Number.isFinite(ratio)) {
    return "-";
  }
  return `${formatAmount(ratio * 100, 2)}%`;
}

function formatTimestamp(timestampMs, fallbackLabel) {
  if (!Number.isFinite(timestampMs) || timestampMs <= 0) {
    return fallbackLabel || "-";
  }
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(timestampMs));
}

function pairLabel(baseSymbol, quoteSymbol) {
  return `${baseSymbol} / ${quoteSymbol}`;
}

function normalizeTupleValue(raw) {
  const value = unwrapProxyValue(raw);
  if (Array.isArray(value)) {
    return value;
  }
  if (value && typeof value === "object") {
    return Object.values(value);
  }
  return null;
}

function formatBasisPoints(value) {
  if (!Number.isFinite(value)) {
    return "-";
  }
  return `${formatAmount(value / 100, 2)}%`;
}

function formatRatioBasisPoints(value) {
  if (!Number.isFinite(value)) {
    return "-";
  }
  return formatPercent(value / 10000);
}

function joinCompact(parts) {
  return parts.filter(Boolean).join(" · ");
}

function createMetric(label, value) {
  return { label, value: value || "-" };
}

function findPayloadInteger(payload, names) {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  for (const name of names) {
    const value = normalizeInteger(payload[name]);
    if (value !== null) {
      return value;
    }
  }
  return null;
}

function findPayloadString(payload, names) {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  for (const name of names) {
    const raw = payload[name];
    if (typeof raw === "string" && raw.trim()) {
      return raw.trim();
    }
  }
  return null;
}

function humanizeEntrypoint(entrypoint) {
  if (!entrypoint) {
    return "Contract call";
  }
  const explicit = {
    route_swap: "Route swap",
    submit_order: "Submitted auction order",
    cancel_order: "Cancelled auction order",
    settle_order: "Settled auction order",
    deposit_and_mint: "Minted n3x",
    burn_and_redeem: "Redeemed n3x",
    open_position: "Opened perp",
    close_position: "Closed perp",
    add_margin: "Added margin",
    reduce_position: "Reduced perp",
    liquidate_position: "Liquidated perp",
    stake: "Staked farm",
    unstake: "Unstaked farm",
    claim: "Claimed rewards",
    buy: "Bought allocation",
    claim_sale: "Claimed launchpad",
    refund: "Refunded launchpad",
    create_series: "Created option series",
    buy_option: "Bought option",
    settle_series: "Settled series",
    exercise: "Exercised option",
    register_policy: "Opened cover",
    claim_policy: "Claimed cover",
    schedule_twamm_v2: "Scheduled TWAMM",
    cancel_twamm: "Cancelled TWAMM",
    claim_twamm: "Claimed TWAMM",
    open_escrow: "Opened escrow",
    accept_escrow: "Accepted escrow",
    cancel_escrow: "Cancelled escrow",
    refund_expired: "Refunded escrow",
  };
  if (explicit[entrypoint]) {
    return explicit[entrypoint];
  }
  return entrypoint
    .split("_")
    .filter(Boolean)
    .map((segment) => segment[0].toUpperCase() + segment.slice(1))
    .join(" ");
}

function summarizePayload(payload) {
  if (!payload || typeof payload !== "object") {
    return "-";
  }
  const parts = [];
  Object.entries(payload).some(([key, value]) => {
    if (value === null || value === undefined || value === "") {
      return false;
    }
    if (typeof value === "object") {
      return false;
    }
    parts.push(`${key}=${value}`);
    return parts.length >= 3;
  });
  return parts.length ? parts.join(" · ") : "-";
}

function moduleStatusRank(statusTone) {
  return (
    {
      live: 0,
      watch: 1,
      guarded: 2,
      missing: 3,
      error: 4,
    }[statusTone] ?? 5
  );
}

function moduleContractKey(moduleKey) {
  return PRODUCT_DEFINITIONS.find((definition) => definition.key === moduleKey)?.contractKey || moduleKey;
}

function resolveEnvironmentContract(environment, contractKey) {
  if (!environment) {
    return null;
  }
  return (
    (environment.contracts || []).find((contract) => contract.contract_key === contractKey)
    || null
  );
}

function workspaceModules() {
  return Array.isArray(state.workspace?.modules) ? state.workspace.modules : [];
}

function availableModuleKey(candidateKey) {
  const modules = workspaceModules();
  if (candidateKey && modules.some((module) => module.key === candidateKey)) {
    return candidateKey;
  }
  return modules[0]?.key || "swaps";
}

function currentSelectedModule() {
  const key = availableModuleKey(state.selectedModuleKey);
  return workspaceModules().find((module) => module.key === key) || null;
}

function currentActionRail() {
  return ACTION_RAILS[availableModuleKey(state.selectedModuleKey)] || ACTION_RAILS.swaps;
}

function ensureSelectedAction(moduleKey = state.selectedModuleKey) {
  const rail = ACTION_RAILS[moduleKey] || ACTION_RAILS.swaps;
  const defaultAction = rail.actions[0];
  if (!rail.actions.some((action) => action.key === state.selectedActionKey)) {
    state.selectedActionKey = defaultAction?.key || "swap_buy";
  }
  return rail;
}

function currentActionDefinition() {
  const rail = ensureSelectedAction();
  return rail.actions.find((action) => action.key === state.selectedActionKey) || rail.actions[0] || null;
}

function actionDraftFor(action) {
  if (!action) {
    return {};
  }
  if (!state.tradeDrafts[action.key]) {
    state.tradeDrafts[action.key] = Object.fromEntries(
      action.fields.map((field) => [field.key, field.defaultValue ?? ""]),
    );
  }
  return state.tradeDrafts[action.key];
}

function applyModuleSelection(moduleKey, options = {}) {
  state.selectedModuleKey = availableModuleKey(moduleKey);
  ensureSelectedAction(state.selectedModuleKey);
  if (options.syncActivityFilter !== false) {
    state.activityFilterKey = state.selectedModuleKey;
  }
  if (!options.skipRender) {
    renderWorkspace();
  }
}

function applyActivityFilter(filterKey, options = {}) {
  if (filterKey !== "all" && !workspaceModules().some((module) => module.key === filterKey)) {
    filterKey = "all";
  }
  state.activityFilterKey = filterKey;
  if (filterKey !== "all" && options.syncSelection !== false) {
    state.selectedModuleKey = filterKey;
    ensureSelectedAction(state.selectedModuleKey);
  }
  if (!options.skipRender) {
    renderWorkspace();
  }
}

async function callViewOptional(environment, contractAddress, authority, entrypoint, payload) {
  try {
    return await callView(environment, contractAddress, authority, entrypoint, payload);
  } catch (error) {
    console.warn(`view ${entrypoint} failed for ${contractAddress}`, error);
    return null;
  }
}

function buildModuleCard(definition, contract, values = {}) {
  return {
    key: definition.key,
    label: definition.label,
    contractKey: definition.contractKey,
    contractAddress: contract?.contract_address || null,
    statusTone: values.statusTone || "watch",
    statusLabel: values.statusLabel || "Watching",
    hero: values.hero || "No recent wallet activity",
    blurb: values.blurb || "No cross-product summary is available yet.",
    metrics: Array.isArray(values.metrics) && values.metrics.length
      ? values.metrics.slice(0, 3)
      : [createMetric("Contract", contract?.contract_address ? truncateMiddle(contract.contract_address, 10, 8) : "Unavailable")],
    radarValue: values.radarValue || values.statusLabel || "Watching",
    rawActivities: Array.isArray(values.rawActivities) ? values.rawActivities : [],
  };
}

function buildMissingModule(definition) {
  return buildModuleCard(definition, null, {
    statusTone: "missing",
    statusLabel: "Not deployed",
    hero: "Not available here",
    blurb: `${definition.contractKey} is not deployed in this environment yet.`,
    radarValue: "Missing",
  });
}

function buildErrorModule(definition, contract, error) {
  return buildModuleCard(definition, contract, {
    statusTone: "error",
    statusLabel: "View error",
    hero: "Summary unavailable",
    blurb: error?.message || "The contract view failed for this product surface.",
    radarValue: "Error",
  });
}

function parseRouterAssets(raw) {
  const value = unwrapProxyValue(raw);
  if (Array.isArray(value) && value.length >= 2) {
    return {
      baseAssetId: String(value[0]),
      quoteAssetId: String(value[1]),
    };
  }
  if (value && typeof value === "object") {
    return {
      baseAssetId: String(value.base_asset || value.baseAsset || value[0] || "xor#universal"),
      quoteAssetId: String(value.quote_asset || value.quoteAsset || value[1] || "quote"),
    };
  }
  throw new Error("router_assets returned an unexpected shape");
}

function normalizeEnvironmentSelection(catalog) {
  state.catalog = catalog;
  state.environments = Array.isArray(catalog?.environments) ? catalog.environments.slice() : [];

  environmentSelect.innerHTML = "";
  state.environments.forEach((environment) => {
    const option = document.createElement("option");
    option.value = environment.name;
    option.textContent = environment.name;
    environmentSelect.append(option);
  });

  const preferred =
    state.local.selectedEnvironment
    && state.environments.some((environment) => environment.name === state.local.selectedEnvironment)
      ? state.local.selectedEnvironment
      : state.environments[0]?.name || "";
  applyEnvironment(preferred);
}

function applyEnvironment(environmentName) {
  state.currentEnvironment =
    state.environments.find((environment) => environment.name === environmentName) || null;
  state.currentContract = resolveRouterContract(state.currentEnvironment);
  environmentSelect.value = state.currentEnvironment?.name || "";

  if (state.currentEnvironment?.name) {
    state.local.selectedEnvironment = state.currentEnvironment.name;
    saveStorage(STORAGE_KEYS.selectedEnvironment, state.local.selectedEnvironment);
  }

  const savedAuthority = state.currentEnvironment
    ? state.local.authorityByEnvironment[state.currentEnvironment.name] || ""
    : "";
  const defaultAuthority = savedAuthority || state.currentEnvironment?.signer?.authority || "";
  authorityInput.value = defaultAuthority;

  renderDeploymentSummary();
  syncTradeControls();
}

function resolveRouterContract(environment) {
  if (!environment) {
    return null;
  }
  return (
    environment.preferred_contract
    || (environment.contracts || []).find(
      (contract) => contract.contract_key === environment.preferred_contract_key,
    )
    || null
  );
}

function renderDeploymentSummary() {
  const environment = state.currentEnvironment;
  const contract = state.currentContract;

  routerContractLabel.textContent = contract?.contract_key || "Router unavailable";
  routerAddress.textContent = contract?.contract_address || "-";
  routerTorii.textContent = environment?.torii_url
    ? `${environment.torii_url} (${environment.torii_url_source || "deployment"})`
    : "Unconfigured";
  routerCallAccess.textContent = describeCallAccess(environment);

  if (!state.workspace) {
    historyHeadDisplay.textContent = "-";
    historyCountDisplay.textContent = "-";
  }
}

function describeCallAccess(environment) {
  if (!environment) {
    return "No environment selected";
  }
  const signer = environment.signer || {};
  const mutationPolicy = environment.mutation_policy || {};
  if (!signer.call_enabled) {
    return "Read-only: no signer with private key";
  }
  if (!mutationPolicy.allowed) {
    return mutationPolicy.reason || "Signed mutations disabled";
  }
  return `Enabled (${signer.source || "configured"})`;
}

function rememberAuthority() {
  const environmentName = state.currentEnvironment?.name;
  if (!environmentName) {
    return;
  }
  state.local.authorityByEnvironment[environmentName] = currentAuthority();
  saveStorage(STORAGE_KEYS.authorityByEnvironment, state.local.authorityByEnvironment);
}

function selectedTradeModule() {
  return currentSelectedModule() || workspaceModules().find((module) => module.key === "swaps") || null;
}

function buildTradePreview() {
  const environment = state.currentEnvironment;
  const module = selectedTradeModule();
  const action = currentActionDefinition();
  const gasLimit = normalizeInteger(tradeGasLimitInput.value) ?? DEFAULT_GAS_LIMIT;
  const draft = actionDraftFor(action);
  return {
    environment: environment?.name || "",
    authority: currentAuthority(),
    contract_address: module?.contractAddress || "",
    entrypoint: action?.entrypoint || "",
    gas_limit: gasLimit,
    payload: action ? action.buildPayload(draft) : {},
  };
}

function tradeValidationError() {
  const environment = state.currentEnvironment;
  const module = selectedTradeModule();
  const action = currentActionDefinition();
  const authority = currentAuthority();
  const gasLimit = normalizeInteger(tradeGasLimitInput.value);
  const preview = buildTradePreview();

  if (!environment) {
    return "No environment selected.";
  }
  if (!module?.contractAddress) {
    return "The selected product is not deployed in this environment.";
  }
  if (!authority) {
    return "Enter an authority to load trader state and submit actions.";
  }
  if (!action) {
    return "No action rail is available for the selected product.";
  }
  if (!environment.signer?.call_enabled) {
    return "Bind a signer with a private key to submit signed trader actions from this cockpit.";
  }
  if (!environment.mutation_policy?.allowed) {
    return environment.mutation_policy?.reason || "Signed mutations are disabled for this environment.";
  }
  if (!Number.isSafeInteger(gasLimit) || gasLimit <= 0) {
    return "Gas limit must be a positive integer.";
  }
  for (const field of action.fields) {
    const value = preview.payload[field.key];
    if (field.type === "number") {
      if (!Number.isSafeInteger(value)) {
        return `${field.label} must be an integer.`;
      }
      if ((field.min ?? 0) > 0 && value < field.min) {
        return `${field.label} must be at least ${field.min}.`;
      }
      if ((field.min ?? 0) === 0 && value < 0) {
        return `${field.label} must not be negative.`;
      }
    }
    if (field.type === "text" && !String(value || "").trim()) {
      return `${field.label} is required.`;
    }
  }
  return null;
}

function syncTradeControls() {
  const rail = ensureSelectedAction();
  const action = currentActionDefinition();
  const draft = actionDraftFor(action);

  tradeKicker.textContent = selectedTradeModule()?.label || "Action Rail";
  tradeTitle.textContent = rail.title;
  tradeCopy.textContent = rail.copy;
  tradeModeBar.replaceChildren();
  rail.actions.forEach((item) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "segment";
    button.classList.toggle("active", item.key === state.selectedActionKey);
    button.textContent = item.label;
    button.addEventListener("click", () => {
      state.selectedActionKey = item.key;
      syncTradeControls();
    });
    tradeModeBar.append(button);
  });

  tradeFields.replaceChildren();
  if (action) {
    action.fields.forEach((field) => {
      const wrapper = document.createElement("label");
      wrapper.className = "field";

      const label = document.createElement("span");
      label.textContent = field.label;
      wrapper.append(label);

      const input = document.createElement("input");
      input.type = field.type === "number" ? "number" : "text";
      if (field.type === "number") {
        if (field.min !== undefined) {
          input.min = String(field.min);
        }
        if (field.step !== undefined) {
          input.step = String(field.step);
        }
      }
      input.value = String(draft[field.key] ?? field.defaultValue ?? "");
      input.addEventListener("input", () => {
        state.tradeDrafts[action.key][field.key] = field.type === "number" ? normalizeInteger(input.value) ?? input.value : input.value;
        syncTradeControls();
      });
      wrapper.append(input);

      if (field.help) {
        const help = document.createElement("div");
        help.className = "field-help";
        help.textContent = field.help;
        wrapper.append(help);
      }
      tradeFields.append(wrapper);
    });
  }

  tradePreview.textContent = JSON.stringify(buildTradePreview(), null, 2);
  const error = tradeValidationError();
  tradeSubmit.disabled = Boolean(error);
  tradeSubmit.title = error || "";
  tradeSubmit.textContent = action?.submitLabel || "Submit Action";
}

async function loadSwapHistory(environmentName, contractAddress, authority, historyHead) {
  const visible = [];
  let scanned = 0;
  let cursor = historyHead;

  while (
    cursor > 0
    && scanned < DEFAULT_HISTORY_SCAN_LIMIT
    && visible.length < DEFAULT_VISIBLE_FILL_LIMIT
  ) {
    const batchIds = [];
    while (cursor > 0 && batchIds.length < HISTORY_BATCH_SIZE && scanned < DEFAULT_HISTORY_SCAN_LIMIT) {
      batchIds.push(cursor);
      cursor -= 1;
      scanned += 1;
    }

    const batchValues = await Promise.all(
      batchIds.map(async (recordId) => {
        try {
          const raw = await callView(
            environmentName,
            contractAddress,
            authority,
            "mirror_swap_history",
            { record_id: recordId },
          );
          return normalizeHistoryRecord(recordId, raw);
        } catch (error) {
          console.warn(`failed to load swap history ${recordId}`, error);
          return null;
        }
      }),
    );

    batchValues.forEach((record) => {
      if (!record) {
        return;
      }
      if (authority && record.trader !== authority) {
        return;
      }
      visible.push(record);
    });
  }

  return visible;
}

function activityMatchesRecord(activity, record) {
  const payload = activity?.contractPayload;
  if (!payload || typeof payload !== "object") {
    return false;
  }
  const payloadAmountIn = normalizeInteger(payload.amount_in ?? payload.amountIn);
  const payloadMinOut = normalizeInteger(payload.min_out ?? payload.minOut);
  const payloadInputIsBase = normalizeInteger(payload.input_is_base ?? payload.inputIsBase);
  return (
    payloadAmountIn === record.amountIn
    && payloadMinOut === record.minOut
    && (payloadInputIsBase === null || payloadInputIsBase === record.inputIsBase)
  );
}

function stitchRecords(records, activities) {
  const remaining = activities.slice();
  return records.map((record) => {
    let activityIndex = remaining.findIndex((activity) => activityMatchesRecord(activity, record));
    if (activityIndex < 0 && remaining.length > 0) {
      activityIndex = 0;
    }
    const activity = activityIndex >= 0 ? remaining.splice(activityIndex, 1)[0] : null;
    const side = record.inputIsBase === 1 ? "buy" : "sell";
    const price = record.inputIsBase === 1
      ? record.amountIn / Math.max(record.amountOut, 1)
      : record.amountOut / Math.max(record.amountIn, 1);
    const protectionRatio = record.minOut > 0
      ? (record.amountOut - record.minOut) / record.minOut
      : null;
    return {
      ...record,
      side,
      price,
      protectionRatio,
      timestampMs: activity?.timestampMs ?? null,
      executionHash: activity?.entrypointHash ?? null,
    };
  });
}

function computeAnalytics(fills) {
  let quoteInventory = 0;
  let costBasisBase = 0;
  let realizedPnlBase = 0;
  let totalBaseSpent = 0;
  let totalBaseRealized = 0;
  let totalQuoteBought = 0;
  let totalQuoteSold = 0;
  let winCount = 0;
  let sellCount = 0;
  let cushionRatioSum = 0;
  let cushionCount = 0;

  fills
    .slice()
    .reverse()
    .forEach((fill) => {
      if (fill.side === "buy") {
        totalBaseSpent += fill.amountIn;
        totalQuoteBought += fill.amountOut;
        quoteInventory += fill.amountOut;
        costBasisBase += fill.amountIn;
      } else {
        totalBaseRealized += fill.amountOut;
        totalQuoteSold += fill.amountIn;
        sellCount += 1;

        const inventoryBefore = quoteInventory;
        const basisBefore = costBasisBase;
        const soldQuote = Math.min(fill.amountIn, inventoryBefore);
        const costPortion = inventoryBefore > 0
          ? (basisBefore * soldQuote) / inventoryBefore
          : 0;
        const tradeRealized = fill.amountOut - costPortion;
        realizedPnlBase += tradeRealized;
        if (tradeRealized > 0) {
          winCount += 1;
        }
        quoteInventory = Math.max(0, inventoryBefore - fill.amountIn);
        costBasisBase = Math.max(0, basisBefore - costPortion);
      }

      if (Number.isFinite(fill.protectionRatio)) {
        cushionRatioSum += fill.protectionRatio;
        cushionCount += 1;
      }
    });

  const avgEntry = totalQuoteBought > 0 ? totalBaseSpent / totalQuoteBought : null;
  const avgExit = totalQuoteSold > 0 ? totalBaseRealized / totalQuoteSold : null;
  const lastPrice = fills.length > 0 ? fills[0].price : null;
  const unrealizedPnlBase =
    Number.isFinite(lastPrice) ? (quoteInventory * lastPrice) - costBasisBase : null;
  const totalPnlBase =
    Number.isFinite(unrealizedPnlBase) ? realizedPnlBase + unrealizedPnlBase : realizedPnlBase;

  return {
    avgEntry,
    avgExit,
    openQuoteAmount: quoteInventory,
    realizedPnlBase,
    unrealizedPnlBase,
    totalPnlBase,
    totalBaseSpent,
    totalBaseRealized,
    lastPrice,
    winRate: sellCount > 0 ? winCount / sellCount : null,
    avgCushionRatio: cushionCount > 0 ? cushionRatioSum / cushionCount : null,
  };
}

function buildSwapModule(fills, metrics, symbols, contract) {
  return buildModuleCard(
    PRODUCT_DEFINITIONS[0],
    contract,
    {
      statusTone: fills.length ? "live" : "watch",
      statusLabel: fills.length ? "Trading" : "Awaiting flow",
      hero: Number.isFinite(metrics.totalPnlBase)
        ? formatSignedAssetAmount(metrics.totalPnlBase, symbols.baseSymbol)
        : "No personal PnL yet",
      blurb: fills.length
        ? joinCompact([
            `Avg entry ${Number.isFinite(metrics.avgEntry) ? `${formatAmount(metrics.avgEntry, 4)} ${symbols.baseSymbol}` : "-"}`,
            `Open ${formatAssetAmount(metrics.openQuoteAmount, symbols.quoteSymbol)}`,
            `${formatCount(fills.length)} executed fills`,
          ])
        : "The router is deployed, but this wallet has no successful fills in the visible journal window yet.",
      metrics: [
        createMetric(
          "Avg Entry",
          Number.isFinite(metrics.avgEntry) ? `${formatAmount(metrics.avgEntry, 4)} ${symbols.baseSymbol}` : "-",
        ),
        createMetric(
          "Realized",
          formatSignedAssetAmount(metrics.realizedPnlBase, symbols.baseSymbol),
        ),
        createMetric(
          "Open Quote",
          formatAssetAmount(metrics.openQuoteAmount, symbols.quoteSymbol),
        ),
      ],
      radarValue: fills.length
        ? `${formatCount(fills.length)} fills`
        : "No fills",
    },
  );
}

async function loadN3xModule(environment, authority) {
  const definition = PRODUCT_DEFINITIONS.find((item) => item.key === "n3x");
  const contract = resolveEnvironmentContract(environment, definition.contractKey);
  if (!contract) {
    return buildMissingModule(definition);
  }

  try {
    const [configRaw, stateRaw, activityRaw] = await Promise.all([
      callView(environment.name, contract.contract_address, authority, "hub_config"),
      callView(environment.name, contract.contract_address, authority, "mirror_state"),
      listContractActivity(environment.name, contract.contract_address, authority, {
        limit: DEFAULT_MODULE_ACTIVITY_LIMIT,
      }),
    ]);
    const config = normalizeTupleValue(configRaw) || [];
    const tuple = normalizeTupleValue(stateRaw) || [];
    const totalN3x = normalizeInteger(tuple[4]) ?? 0;
    const basketUsdt = normalizeInteger(tuple[1]) ?? 0;
    const basketUsdc = normalizeInteger(tuple[2]) ?? 0;
    const basketKusd = normalizeInteger(tuple[3]) ?? 0;
    const mintFeeBps = normalizeInteger(config[5]) ?? normalizeInteger(tuple[5]) ?? 0;
    const redeemFeeBps = normalizeInteger(config[6]) ?? normalizeInteger(tuple[6]) ?? 0;
    const n3xSymbol = assetTicker(config[3] || "n3x#soraswap.universal");
    const activities = normalizeActivityItems(activityRaw);
    return buildModuleCard(definition, contract, {
      statusTone: "live",
      statusLabel: "Basket live",
      hero: `${formatAmount(totalN3x)} ${n3xSymbol}`,
      blurb: joinCompact([
        `Basket ${formatAmount(basketUsdt)} USDT / ${formatAmount(basketUsdc)} USDC / ${formatAmount(basketKusd)} KUSD`,
        `Mint ${formatBasisPoints(mintFeeBps)}`,
        `Redeem ${formatBasisPoints(redeemFeeBps)}`,
      ]),
      metrics: [
        createMetric("Supply", `${formatAmount(totalN3x)} ${n3xSymbol}`),
        createMetric("Mint Fee", formatBasisPoints(mintFeeBps)),
        createMetric("Redeem Fee", formatBasisPoints(redeemFeeBps)),
      ],
      radarValue: `${formatAmount(totalN3x)} ${n3xSymbol}`,
      rawActivities: activities,
    });
  } catch (error) {
    return buildErrorModule(definition, contract, error);
  }
}

async function loadPerpsModule(environment, authority) {
  const definition = PRODUCT_DEFINITIONS.find((item) => item.key === "perps");
  const contract = resolveEnvironmentContract(environment, definition.contractKey);
  if (!contract) {
    return buildMissingModule(definition);
  }

  try {
    const [configRaw, automationRaw, activityRaw] = await Promise.all([
      callView(environment.name, contract.contract_address, authority, "engine_config"),
      callView(environment.name, contract.contract_address, authority, "automation_state"),
      listContractActivity(environment.name, contract.contract_address, authority, {
        limit: DEFAULT_MODULE_ACTIVITY_LIMIT,
      }),
    ]);
    const config = normalizeTupleValue(configRaw) || [];
    const automation = normalizeTupleValue(automationRaw) || [];
    const activities = normalizeActivityItems(activityRaw);
    const nextMarketId = normalizeInteger(config[3]) ?? 0;
    const nextPositionId = normalizeInteger(config[4]) ?? 0;
    const marketId =
      findPayloadInteger(activities[0]?.contractPayload, ["market_id", "marketId"])
      ?? (nextMarketId > 1 ? 1 : null);
    const positionId =
      findPayloadInteger(activities[0]?.contractPayload, ["position_id", "positionId"])
      ?? (nextPositionId > 1 ? 1 : null);

    let market = null;
    let oracle = null;
    let risk = null;
    let position = null;
    if (marketId !== null) {
      market = normalizeTupleValue(
        await callViewOptional(environment.name, contract.contract_address, authority, "market_state", {
          market_id: marketId,
        }),
      );
      if ((normalizeInteger(market?.[0]) ?? 0) === 1) {
        [oracle, risk] = await Promise.all([
          callViewOptional(environment.name, contract.contract_address, authority, "market_oracle_state", {
            market_id: marketId,
          }),
          callViewOptional(environment.name, contract.contract_address, authority, "risk_state", {
            market_id: marketId,
          }),
        ]);
        oracle = normalizeTupleValue(oracle);
        risk = normalizeTupleValue(risk);
      }
    }
    if (positionId !== null) {
      position = normalizeTupleValue(
        await callViewOptional(environment.name, contract.contract_address, authority, "position_state", {
          position_id: positionId,
        }),
      );
    }

    const openInterest = normalizeInteger(market?.[2]) ?? 0;
    const openInterestCap = normalizeInteger(market?.[3]) ?? 0;
    const guardFlags = normalizeInteger(market?.[11]) ?? 0;
    const markPrice = normalizeInteger(oracle?.[0]) ?? normalizeInteger(position?.[8]) ?? 0;
    const indexPrice = normalizeInteger(oracle?.[1]) ?? normalizeInteger(position?.[9]) ?? 0;
    const utilisationBps = normalizeInteger(risk?.[3]) ?? 0;
    const backlog = normalizeInteger(automation[5]) ?? 0;
    const safeMode = normalizeInteger(automation[6]) ?? 0;
    const withdrawalOnly = normalizeInteger(config[2]) ?? 0;
    const positionRegistered = (normalizeInteger(position?.[0]) ?? 0) === 1;
    const positionSize = normalizeInteger(position?.[3]) ?? 0;
    const positionMargin = normalizeInteger(position?.[4]) ?? 0;
    const positionRealized = normalizeInteger(position?.[6]) ?? 0;

    return buildModuleCard(definition, contract, {
      statusTone: safeMode > 0 || withdrawalOnly > 0 || guardFlags > 0 ? "guarded" : "live",
      statusLabel: safeMode > 0 || withdrawalOnly > 0 ? "Guarded" : "Market live",
      hero: openInterestCap > 0
        ? `${formatAmount(openInterest)} / ${formatAmount(openInterestCap)} OI`
        : "Perps live",
      blurb: joinCompact([
        `Mark ${formatAmount(markPrice, 2)} / index ${formatAmount(indexPrice, 2)}`,
        `Utilisation ${formatRatioBasisPoints(utilisationBps)}`,
        `Backlog ${formatCount(backlog)}`,
      ]),
      metrics: [
        createMetric("Open Interest", openInterestCap > 0 ? `${formatAmount(openInterest)} / ${formatAmount(openInterestCap)}` : "-"),
        createMetric("Utilisation", formatRatioBasisPoints(utilisationBps)),
        createMetric(
          "Tracked Position",
          positionRegistered
            ? joinCompact([
                `${formatAmount(positionSize)} size`,
                `${formatAmount(positionMargin)} margin`,
                `${formatSignedAssetAmount(positionRealized, assetTicker(config[0] || "usdt"))}`,
              ])
            : "No recent position",
        ),
      ],
      radarValue: formatRatioBasisPoints(utilisationBps),
      rawActivities: activities,
    });
  } catch (error) {
    return buildErrorModule(definition, contract, error);
  }
}

async function loadFarmsModule(environment, authority) {
  const definition = PRODUCT_DEFINITIONS.find((item) => item.key === "farms");
  const contract = resolveEnvironmentContract(environment, definition.contractKey);
  if (!contract) {
    return buildMissingModule(definition);
  }

  try {
    const [configRaw, stateRaw, activityRaw] = await Promise.all([
      callView(environment.name, contract.contract_address, authority, "farm_config"),
      callView(environment.name, contract.contract_address, authority, "farm_state"),
      listContractActivity(environment.name, contract.contract_address, authority, {
        limit: DEFAULT_MODULE_ACTIVITY_LIMIT,
      }),
    ]);
    const config = normalizeTupleValue(configRaw) || [];
    const stateTuple = normalizeTupleValue(stateRaw) || [];
    const activities = normalizeActivityItems(activityRaw);
    const positionName = findPayloadString(activities[0]?.contractPayload, ["position", "position_name"]);
    const positionState = positionName
      ? normalizeTupleValue(
        await callViewOptional(environment.name, contract.contract_address, authority, "mirror_position", {
          position: positionName,
        }),
      )
      : null;
    const staked = normalizeInteger(positionState?.[1]) ?? 0;
    const accrued = normalizeInteger(positionState?.[2]) ?? 0;
    const claimed = normalizeInteger(positionState?.[3]) ?? 0;
    const rewardRate = normalizeInteger(config[3]) ?? normalizeInteger(positionState?.[7]) ?? 0;
    const stakeSymbol = assetTicker(config[0] || "stake");
    const rewardSymbol = assetTicker(config[1] || "reward");
    return buildModuleCard(definition, contract, {
      statusTone: rewardRate > 0 ? "live" : "watch",
      statusLabel: rewardRate > 0 ? "Yielding" : "Idle",
      hero: staked > 0 ? `${formatAmount(staked)} ${stakeSymbol}` : `Reward rate ${formatAmount(rewardRate)}`,
      blurb: joinCompact([
        positionName ? `Position ${positionName}` : "No tracked farm position",
        `Accrued ${formatAmount(accrued)} ${rewardSymbol}`,
        `Slot ${formatCount(normalizeInteger(stateTuple[0]) ?? 0)}`,
      ]),
      metrics: [
        createMetric("Staked", `${formatAmount(staked)} ${stakeSymbol}`),
        createMetric("Accrued", `${formatAmount(accrued)} ${rewardSymbol}`),
        createMetric("Claimed", `${formatAmount(claimed)} ${rewardSymbol}`),
      ],
      radarValue: staked > 0 ? `${formatAmount(staked)} staked` : "No stake",
      rawActivities: activities,
    });
  } catch (error) {
    return buildErrorModule(definition, contract, error);
  }
}

async function loadLaunchpadModule(environment, authority) {
  const definition = PRODUCT_DEFINITIONS.find((item) => item.key === "launchpad");
  const contract = resolveEnvironmentContract(environment, definition.contractKey);
  if (!contract) {
    return buildMissingModule(definition);
  }

  try {
    const [bindingRaw, activityRaw] = await Promise.all([
      callView(environment.name, contract.contract_address, authority, "factory_binding_state"),
      listContractActivity(environment.name, contract.contract_address, authority, {
        limit: DEFAULT_MODULE_ACTIVITY_LIMIT,
      }),
    ]);
    const binding = normalizeTupleValue(bindingRaw) || [];
    const activities = normalizeActivityItems(activityRaw);
    const saleName = findPayloadString(activities[0]?.contractPayload, ["sale", "sale_name"]);
    const allocationName = findPayloadString(activities[0]?.contractPayload, ["allocation", "allocation_name"]);
    const saleState = saleName
      ? normalizeTupleValue(
        await callViewOptional(environment.name, contract.contract_address, authority, "mirror_sale", {
          sale: saleName,
        }),
      )
      : null;
    const saleConfig = saleName
      ? normalizeTupleValue(
        await callViewOptional(environment.name, contract.contract_address, authority, "sale_config", {
          sale: saleName,
        }),
      )
      : null;
    const allocationState = allocationName
      ? normalizeTupleValue(
        await callViewOptional(environment.name, contract.contract_address, authority, "mirror_allocation", {
          allocation: allocationName,
        }),
      )
      : null;
    const raised = normalizeInteger(saleState?.[1]) ?? 0;
    const sold = normalizeInteger(saleState?.[2]) ?? 0;
    const closed = normalizeInteger(saleState?.[3]) ?? 0;
    const successful = normalizeInteger(saleState?.[4]) ?? 0;
    const softCap = normalizeInteger(saleConfig?.[4]) ?? 0;
    const hardCap = normalizeInteger(saleConfig?.[5]) ?? 0;
    const allocationClaimed = normalizeInteger(allocationState?.[3]) ?? 0;
    return buildModuleCard(definition, contract, {
      statusTone:
        (normalizeInteger(binding[0]) ?? 0) === 0 || (normalizeInteger(binding[1]) ?? 0) === 0
          ? "guarded"
          : "live",
      statusLabel: closed > 0 ? (successful > 0 ? "Successful" : "Closed") : "Sale live",
      hero: saleName ? `${saleName}` : "Factory ready",
      blurb: saleName
        ? joinCompact([
            `Raised ${formatAmount(raised)} / ${formatAmount(hardCap || softCap)}`,
            `Sold ${formatAmount(sold)}`,
            allocationName ? `Claimed ${formatAmount(allocationClaimed)}` : null,
          ])
        : "Bindings are deployed; waiting for a sale or wallet allocation to summarize.",
      metrics: [
        createMetric("Raised", hardCap > 0 ? `${formatAmount(raised)} / ${formatAmount(hardCap)}` : formatAmount(raised)),
        createMetric("Soft Cap", softCap > 0 ? formatAmount(softCap) : "-"),
        createMetric("Allocation", allocationName ? formatAmount(allocationClaimed) : "No allocation"),
      ],
      radarValue: saleName ? `${formatAmount(raised)} raised` : "Factory bound",
      rawActivities: activities,
    });
  } catch (error) {
    return buildErrorModule(definition, contract, error);
  }
}

async function loadOptionsManagerModule(environment, authority) {
  const definition = PRODUCT_DEFINITIONS.find((item) => item.key === "optionsManager");
  const contract = resolveEnvironmentContract(environment, definition.contractKey);
  if (!contract) {
    return buildMissingModule(definition);
  }

  try {
    const [configRaw, automationRaw, activityRaw] = await Promise.all([
      callView(environment.name, contract.contract_address, authority, "manager_config"),
      callView(environment.name, contract.contract_address, authority, "automation_state"),
      listContractActivity(environment.name, contract.contract_address, authority, {
        limit: DEFAULT_MODULE_ACTIVITY_LIMIT,
      }),
    ]);
    const config = normalizeTupleValue(configRaw) || [];
    const automation = normalizeTupleValue(automationRaw) || [];
    const activities = normalizeActivityItems(activityRaw);
    const nextTemplateId = normalizeInteger(config[2]) ?? 0;
    const nextSeriesId = normalizeInteger(config[3]) ?? 0;
    const seriesId =
      findPayloadInteger(activities[0]?.contractPayload, ["series_id", "seriesId"])
      ?? (nextSeriesId > 1 ? nextSeriesId - 1 : null);
    let seriesState = null;
    let templateState = null;
    if (seriesId !== null) {
      seriesState = normalizeTupleValue(
        await callViewOptional(environment.name, contract.contract_address, authority, "series_state", {
          series_id: seriesId,
        }),
      );
      const templateId =
        findPayloadInteger(activities[0]?.contractPayload, ["template_id", "templateId"])
        ?? normalizeInteger(seriesState?.[2])
        ?? (nextTemplateId > 1 ? nextTemplateId - 1 : null);
      if (templateId !== null) {
        templateState = normalizeTupleValue(
          await callViewOptional(environment.name, contract.contract_address, authority, "template_state", {
            template_id: templateId,
          }),
        );
      }
    }
    const withdrawalOnly = normalizeInteger(config[1]) ?? 0;
    const safeMode = normalizeInteger(automation[6]) ?? normalizeInteger(config[8]) ?? 0;
    const premiumBps = normalizeInteger(seriesState?.[5]) ?? 0;
    const strikeBps = normalizeInteger(seriesState?.[6]) ?? normalizeInteger(templateState?.[3]) ?? 0;
    const activeSeries = Math.max(0, (normalizeInteger(config[3]) ?? 1) - 1);
    return buildModuleCard(definition, contract, {
      statusTone: withdrawalOnly > 0 || safeMode > 0 ? "guarded" : "live",
      statusLabel: withdrawalOnly > 0 || safeMode > 0 ? "Guarded" : "Series live",
      hero: activeSeries > 0 ? `${formatCount(activeSeries)} series` : "Options ready",
      blurb: joinCompact([
        seriesId !== null ? `Series #${seriesId}` : "No tracked series",
        `Premium ${formatBasisPoints(premiumBps)}`,
        `Strike ${formatBasisPoints(strikeBps)}`,
      ]),
      metrics: [
        createMetric("Series", formatCount(activeSeries)),
        createMetric("Premium", formatBasisPoints(premiumBps)),
        createMetric("Strike", formatBasisPoints(strikeBps)),
      ],
      radarValue: activeSeries > 0 ? `${formatCount(activeSeries)} series` : "No series",
      rawActivities: activities,
    });
  } catch (error) {
    return buildErrorModule(definition, contract, error);
  }
}

async function loadOptionsFactoryModule(environment, authority) {
  const definition = PRODUCT_DEFINITIONS.find((item) => item.key === "optionsFactory");
  const contract = resolveEnvironmentContract(environment, definition.contractKey);
  if (!contract) {
    return buildMissingModule(definition);
  }

  try {
    const [configRaw, automationRaw, activityRaw] = await Promise.all([
      callView(environment.name, contract.contract_address, authority, "factory_config"),
      callView(environment.name, contract.contract_address, authority, "automation_state"),
      listContractActivity(environment.name, contract.contract_address, authority, {
        limit: DEFAULT_MODULE_ACTIVITY_LIMIT,
      }),
    ]);
    const config = normalizeTupleValue(configRaw) || [];
    const automation = normalizeTupleValue(automationRaw) || [];
    const activities = normalizeActivityItems(activityRaw);
    const nextPositionId = normalizeInteger(config[2]) ?? 0;
    const positionId =
      findPayloadInteger(activities[0]?.contractPayload, ["position_id", "positionId"])
      ?? (nextPositionId > 1 ? nextPositionId - 1 : null);
    const seriesId =
      findPayloadInteger(activities[0]?.contractPayload, ["series_id", "seriesId"])
      ?? null;
    const seriesState = seriesId !== null
      ? normalizeTupleValue(
        await callViewOptional(environment.name, contract.contract_address, authority, "series_state", {
          series_id: seriesId,
        }),
      )
      : null;
    const positionState = positionId !== null
      ? normalizeTupleValue(
        await callViewOptional(environment.name, contract.contract_address, authority, "position_state", {
          position_id: positionId,
        }),
      )
      : null;
    const withdrawalOnly = normalizeInteger(config[1]) ?? 0;
    const safeMode = normalizeInteger(automation[6]) ?? normalizeInteger(config[6]) ?? 0;
    const utilisationBps = normalizeInteger(seriesState?.[6]) ?? 0;
    const premiumPaid = normalizeInteger(positionState?.[4]) ?? 0;
    const collateralLocked = normalizeInteger(positionState?.[5]) ?? 0;
    const positionRegistered = (normalizeInteger(positionState?.[0]) ?? 0) === 1;
    return buildModuleCard(definition, contract, {
      statusTone: withdrawalOnly > 0 || safeMode > 0 ? "guarded" : "live",
      statusLabel: withdrawalOnly > 0 || safeMode > 0 ? "Guarded" : "Buying live",
      hero: positionRegistered ? `Position #${positionId}` : "Factory ready",
      blurb: joinCompact([
        seriesId !== null ? `Series #${seriesId}` : "No tracked series",
        `Utilisation ${formatRatioBasisPoints(utilisationBps)}`,
        `Premium ${formatAmount(premiumPaid)}`,
      ]),
      metrics: [
        createMetric("Utilisation", formatRatioBasisPoints(utilisationBps)),
        createMetric("Premium Paid", formatAmount(premiumPaid)),
        createMetric("Collateral", formatAmount(collateralLocked)),
      ],
      radarValue: positionRegistered ? `#${positionId}` : "No position",
      rawActivities: activities,
    });
  } catch (error) {
    return buildErrorModule(definition, contract, error);
  }
}

async function loadCoverModule(environment, authority) {
  const definition = PRODUCT_DEFINITIONS.find((item) => item.key === "cover");
  const contract = resolveEnvironmentContract(environment, definition.contractKey);
  if (!contract) {
    return buildMissingModule(definition);
  }

  try {
    const [configRaw, automationRaw, activityRaw] = await Promise.all([
      callView(environment.name, contract.contract_address, authority, "manager_config"),
      callView(environment.name, contract.contract_address, authority, "automation_state"),
      listContractActivity(environment.name, contract.contract_address, authority, {
        limit: DEFAULT_MODULE_ACTIVITY_LIMIT,
      }),
    ]);
    const config = normalizeTupleValue(configRaw) || [];
    const automation = normalizeTupleValue(automationRaw) || [];
    const activities = normalizeActivityItems(activityRaw);
    const policyId = findPayloadInteger(activities[0]?.contractPayload, ["policy_id", "policyId"]);
    const policyState = policyId !== null
      ? normalizeTupleValue(
        await callViewOptional(environment.name, contract.contract_address, authority, "policy_state", {
          policy_id: policyId,
        }),
      )
      : null;
    const withdrawalOnly = normalizeInteger(config[2]) ?? 0;
    const safeMode = normalizeInteger(automation[6]) ?? normalizeInteger(config[8]) ?? 0;
    const payout = normalizeInteger(policyState?.[4]) ?? 0;
    const coveredNotional = normalizeInteger(policyState?.[7]) ?? 0;
    const observationCount = normalizeInteger(policyState?.[9]) ?? 0;
    const lastObserved = normalizeInteger(policyState?.[10]) ?? 0;
    return buildModuleCard(definition, contract, {
      statusTone: withdrawalOnly > 0 || safeMode > 0 ? "guarded" : "live",
      statusLabel: withdrawalOnly > 0 || safeMode > 0 ? "Guarded" : "Monitoring",
      hero: policyId !== null ? `Policy #${policyId}` : "Cover ready",
      blurb: joinCompact([
        `Payout ${formatAmount(payout)}`,
        `Notional ${formatAmount(coveredNotional)}`,
        lastObserved > 0 ? `Last observed ${formatAmount(lastObserved, 2)}` : null,
      ]),
      metrics: [
        createMetric("Payout", formatAmount(payout)),
        createMetric("Covered", formatAmount(coveredNotional)),
        createMetric("Observations", formatCount(observationCount)),
      ],
      radarValue: policyId !== null ? `#${policyId}` : "Ready",
      rawActivities: activities,
    });
  } catch (error) {
    return buildErrorModule(definition, contract, error);
  }
}

async function loadGenericProductModule(environment, authority, moduleKey) {
  const definition = PRODUCT_DEFINITIONS.find((item) => item.key === moduleKey);
  const contract = resolveEnvironmentContract(environment, definition.contractKey);
  if (!contract) {
    return buildMissingModule(definition);
  }

  try {
    const activities = normalizeActivityItems(
      await listContractActivity(environment.name, contract.contract_address, authority, {
        limit: DEFAULT_MODULE_ACTIVITY_LIMIT,
      }),
    );
    const latest = activities[0];
    const description = latest ? describeContractActivity(definition, latest) : null;
    return buildModuleCard(definition, contract, {
      statusTone: latest ? "live" : "watch",
      statusLabel: latest ? "Live" : "Watching",
      hero: description?.exposure || "No recent wallet activity",
      blurb: description ? `${description.action} - ${description.context}` : "Deployed and ready for signed trader actions.",
      metrics: [
        createMetric("Contract", truncateMiddle(contract.contract_address, 10, 8)),
        createMetric("Latest", description?.action || "None yet"),
        createMetric("Events", formatCount(activities.length)),
      ],
      radarValue: description?.action || "Watching",
      rawActivities: activities,
    });
  } catch (error) {
    return buildErrorModule(definition, contract, error);
  }
}

async function loadProductModules(environment, authority, fills, metrics, symbols) {
  const routerContract = resolveEnvironmentContract(environment, moduleContractKey("swaps"));
  const modules = [
    buildSwapModule(fills, metrics, symbols, routerContract),
    ...(await Promise.all([
      loadGenericProductModule(environment, authority, "batchAuction"),
      loadN3xModule(environment, authority),
      loadPerpsModule(environment, authority),
      loadFarmsModule(environment, authority),
      loadLaunchpadModule(environment, authority),
      loadGenericProductModule(environment, authority, "options"),
      loadCoverModule(environment, authority),
      loadGenericProductModule(environment, authority, "intents"),
      loadGenericProductModule(environment, authority, "vaults"),
      loadGenericProductModule(environment, authority, "escrow"),
      loadGenericProductModule(environment, authority, "operators"),
      loadGenericProductModule(environment, authority, "margin"),
      loadGenericProductModule(environment, authority, "rwa"),
      loadGenericProductModule(environment, authority, "dlmmHooks"),
    ])),
  ];

  return modules.sort((left, right) => {
    const statusOrder = moduleStatusRank(left.statusTone) - moduleStatusRank(right.statusTone);
    if (statusOrder !== 0) {
      return statusOrder;
    }
    return left.label.localeCompare(right.label);
  });
}

function buildSwapActivityFeed(fills, symbols) {
  return fills.map((fill) => ({
    moduleKey: "swaps",
    moduleLabel: "Swaps",
    timestampMs: fill.timestampMs,
    action: fill.side === "buy" ? "Bought quote" : "Sold quote",
    exposure: fill.side === "buy"
      ? `${formatAssetAmount(fill.amountIn, symbols.baseSymbol)} -> ${formatAssetAmount(fill.amountOut, symbols.quoteSymbol)}`
      : `${formatAssetAmount(fill.amountIn, symbols.quoteSymbol)} -> ${formatAssetAmount(fill.amountOut, symbols.baseSymbol)}`,
    context: joinCompact([
      `Price ${formatAmount(fill.price, 4)} ${symbols.baseSymbol}`,
      `Min out ${fill.side === "buy" ? formatAssetAmount(fill.minOut, symbols.quoteSymbol) : formatAssetAmount(fill.minOut, symbols.baseSymbol)}`,
    ]),
    executionHash: fill.executionHash || `record-${fill.recordId}`,
  }));
}

function describeContractActivity(module, activity) {
  const payload = activity.contractPayload || {};
  const entrypoint = activity.contractEntrypoint || "";

  switch (module.key) {
    case "batchAuction": {
      const orderId = findPayloadString(payload, ["order_id", "orderId"]);
      const amount = findPayloadInteger(payload, ["amount"]);
      const limitTick = findPayloadInteger(payload, ["limit_tick", "limitTick"]);
      const side = findPayloadInteger(payload, ["side"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: joinCompact([
          amount !== null ? `${formatAmount(amount)} ${side === 2 ? "base" : "quote"}` : null,
          limitTick !== null ? `tick ${formatAmount(limitTick)}` : null,
        ]) || "Auction order",
        context: orderId ? `Order ${orderId}` : "Epoch auction",
      };
    }
    case "n3x": {
      const usdt = findPayloadInteger(payload, ["usdt_in"]);
      const usdc = findPayloadInteger(payload, ["usdc_in"]);
      const kusd = findPayloadInteger(payload, ["kusd_in"]);
      const n3xAmount = findPayloadInteger(payload, ["n3x_amount"]);
      if (entrypoint === "deposit_and_mint") {
        return {
          action: "Minted n3x",
          exposure: `${formatAmount((usdt || 0) + (usdc || 0) + (kusd || 0))} basket in`,
          context: joinCompact([
            usdt ? `${formatAmount(usdt)} USDT` : null,
            usdc ? `${formatAmount(usdc)} USDC` : null,
            kusd ? `${formatAmount(kusd)} KUSD` : null,
          ]),
        };
      }
      if (entrypoint === "burn_and_redeem") {
        return {
          action: "Redeemed n3x",
          exposure: `${formatAmount(n3xAmount || 0)} N3X`,
          context: "Redeem basket",
        };
      }
      break;
    }
    case "perps": {
      const marketId = findPayloadInteger(payload, ["market_id", "marketId"]);
      const positionId = findPayloadInteger(payload, ["position_id", "positionId"]);
      const size = findPayloadInteger(payload, ["size"]);
      const margin = findPayloadInteger(payload, ["margin"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: joinCompact([
          size !== null ? `${formatAmount(size)} size` : null,
          margin !== null ? `${formatAmount(margin)} margin` : null,
        ]) || "Perp action",
        context: joinCompact([
          marketId !== null ? `Market ${marketId}` : null,
          positionId !== null ? `Position #${positionId}` : null,
        ]),
      };
    }
    case "farms": {
      const amount = findPayloadInteger(payload, ["amount"]);
      const position = findPayloadString(payload, ["position"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: amount !== null ? formatAmount(amount) : "Farm action",
        context: position ? `Position ${position}` : "Farm position",
      };
    }
    case "launchpad": {
      const paymentAmount = findPayloadInteger(payload, ["payment_amount"]);
      const saleAmount = findPayloadInteger(payload, ["sale_amount"]);
      const sale = findPayloadString(payload, ["sale"]);
      const allocation = findPayloadString(payload, ["allocation"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: joinCompact([
          paymentAmount !== null ? `${formatAmount(paymentAmount)} pay` : null,
          saleAmount !== null ? `${formatAmount(saleAmount)} sale` : null,
        ]) || "Launchpad action",
        context: joinCompact([
          sale ? `${sale}` : null,
          allocation ? `${allocation}` : null,
        ]),
      };
    }
    case "optionsManager": {
      const seriesId = findPayloadInteger(payload, ["series_id", "seriesId"]);
      const templateId = findPayloadInteger(payload, ["template_id", "templateId"]);
      const maxNotional = findPayloadInteger(payload, ["max_notional"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: maxNotional !== null ? `${formatAmount(maxNotional)} max notional` : "Series action",
        context: joinCompact([
          seriesId !== null ? `Series #${seriesId}` : null,
          templateId !== null ? `Template #${templateId}` : null,
        ]),
      };
    }
    case "optionsFactory": {
      const seriesId = findPayloadInteger(payload, ["series_id", "seriesId"]);
      const positionId = findPayloadInteger(payload, ["position_id", "positionId"]);
      const notional = findPayloadInteger(payload, ["notional"]);
      const premiumPaid = findPayloadInteger(payload, ["premium_paid"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: joinCompact([
          notional !== null ? `${formatAmount(notional)} notional` : null,
          premiumPaid !== null ? `${formatAmount(premiumPaid)} premium` : null,
        ]) || "Option action",
        context: joinCompact([
          seriesId !== null ? `Series #${seriesId}` : null,
          positionId !== null ? `Position #${positionId}` : null,
        ]),
      };
    }
    case "cover": {
      const policyId = findPayloadInteger(payload, ["policy_id", "policyId"]);
      const covered = findPayloadInteger(payload, ["covered_notional"]);
      const payout = findPayloadInteger(payload, ["payout_amount"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: joinCompact([
          covered !== null ? `${formatAmount(covered)} covered` : null,
          payout !== null ? `${formatAmount(payout)} payout` : null,
        ]) || "Policy action",
        context: policyId !== null ? `Policy #${policyId}` : "Cover policy",
      };
    }
    case "intents": {
      const intentId = findPayloadString(payload, ["intent_id", "intentId"]);
      const amountIn = findPayloadInteger(payload, ["amount_in", "amountIn"]);
      const amountOut = findPayloadInteger(payload, ["amount_out", "amountOut"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: joinCompact([
          amountIn !== null ? `${formatAmount(amountIn)} in` : null,
          amountOut !== null ? `${formatAmount(amountOut)} out` : null,
        ]) || "Intent action",
        context: intentId ? `Intent ${intentId}` : "Solver intent",
      };
    }
    case "vaults": {
      const vaultId = findPayloadString(payload, ["vault_id", "vaultId"]);
      const positionId = findPayloadString(payload, ["position_id", "positionId"]);
      const amount = findPayloadInteger(payload, ["amount", "shares"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: amount !== null ? formatAmount(amount) : "Vault action",
        context: joinCompact([vaultId, positionId]) || "Vault position",
      };
    }
    case "escrow": {
      const escrowId = findPayloadString(payload, ["escrow_id", "escrowId"]);
      const amount = findPayloadInteger(payload, ["amount"]);
      const conditionCode = findPayloadInteger(payload, ["condition_code", "conditionCode"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: joinCompact([
          amount !== null ? formatAmount(amount) : null,
          conditionCode !== null ? `condition ${conditionCode}` : null,
        ]) || "Escrow action",
        context: escrowId ? `Escrow ${escrowId}` : "Conditional escrow",
      };
    }
    case "operators": {
      const service = findPayloadString(payload, ["service"]);
      const amount = findPayloadInteger(payload, ["amount", "min_bond", "fees_accrued"]);
      const health = findPayloadInteger(payload, ["health_bps", "healthBps"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: joinCompact([
          amount !== null ? formatAmount(amount) : null,
          health !== null ? `${formatBasisPoints(health)} health` : null,
        ]) || "Operator action",
        context: service ? `Service ${service}` : "Bonded operator",
      };
    }
    case "margin": {
      const marketId = findPayloadString(payload, ["market_id", "marketId"]);
      const accountKey = findPayloadString(payload, ["account_key", "accountKey"]);
      const amount = findPayloadInteger(payload, ["amount", "exposure_delta", "exposureDelta"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: amount !== null ? formatAmount(amount) : "Margin action",
        context: joinCompact([marketId, accountKey]) || "Portfolio margin",
      };
    }
    case "rwa": {
      const marketId = findPayloadString(payload, ["market_id", "marketId"]);
      const redemptionId = findPayloadString(payload, ["redemption_id", "redemptionId"]);
      const shares = findPayloadInteger(payload, ["shares", "total_shares", "totalShares"]);
      const nav = findPayloadInteger(payload, ["nav_per_share", "initial_nav_per_share"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: joinCompact([
          shares !== null ? `${formatAmount(shares)} shares` : null,
          nav !== null ? `${formatAmount(nav)} NAV` : null,
        ]) || "RWA action",
        context: joinCompact([marketId, redemptionId]) || "RWA market",
      };
    }
    case "dlmmHooks": {
      const hookId = findPayloadString(payload, ["hook_id", "hookId"]);
      const orderId = findPayloadString(payload, ["order_id", "orderId"]);
      const amountIn = findPayloadInteger(payload, ["amount_in", "amountIn"]);
      const minOut = findPayloadInteger(payload, ["min_out", "minOut", "amount_out", "amountOut"]);
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: joinCompact([
          amountIn !== null ? `${formatAmount(amountIn)} in` : null,
          minOut !== null ? `${formatAmount(minOut)} out` : null,
        ]) || "Hook action",
        context: joinCompact([hookId, orderId]) || "DLMM hook",
      };
    }
    default:
      return {
        action: humanizeEntrypoint(entrypoint),
        exposure: summarizePayload(payload),
        context: module.label,
      };
  }

  return {
    action: humanizeEntrypoint(entrypoint),
    exposure: summarizePayload(payload),
    context: module.label,
  };
}

function buildUnifiedActivityFeed(modules, fills, symbols) {
  const items = buildSwapActivityFeed(fills, symbols);
  modules
    .filter((module) => module.key !== "swaps")
    .forEach((module) => {
      (module.rawActivities || []).forEach((activity) => {
        const description = describeContractActivity(module, activity);
        items.push({
          moduleKey: module.key,
          moduleLabel: module.label,
          timestampMs: activity.timestampMs,
          action: description.action,
          exposure: description.exposure,
          context: description.context,
          executionHash: activity.entrypointHash || activity.contractEntrypoint || module.key,
        });
      });
    });

  return items
    .sort((left, right) => (right.timestampMs || 0) - (left.timestampMs || 0))
    .slice(0, DEFAULT_UNIFIED_ACTIVITY_LIMIT);
}

function createSvgElement(tagName, attributes = {}) {
  const element = document.createElementNS("http://www.w3.org/2000/svg", tagName);
  Object.entries(attributes).forEach(([name, value]) => {
    element.setAttribute(name, String(value));
  });
  return element;
}

function renderChart(fills, candles, metrics, symbols) {
  priceChart.replaceChildren();
  const hasSeries = candles.length || fills.length;
  if (!hasSeries) {
    chartEmpty.style.display = "grid";
    chartEmpty.textContent = currentAuthority()
      ? `No successful router swaps were found for ${truncateMiddle(currentAuthority(), 14, 8)}.`
      : "Enter an authority and refresh to load router history.";
    return;
  }

  chartEmpty.style.display = "none";
  const orderedCandles = candles.length
    ? candles.slice().reverse().map((candle) => ({
      timestampMs: candle.bucketStartMs,
      price: candle.close,
      high: candle.high,
      low: candle.low,
    }))
    : fills.slice().reverse().map((fill) => ({
      timestampMs: fill.timestampMs,
      price: fill.price,
      high: fill.price,
      low: fill.price,
    }));
  const values = orderedCandles
    .flatMap((point) => [point.low, point.high, point.price])
    .filter((value) => Number.isFinite(value));
  if (Number.isFinite(metrics.avgEntry)) {
    values.push(metrics.avgEntry);
  }
  if (Number.isFinite(metrics.lastPrice)) {
    values.push(metrics.lastPrice);
  }
  let minValue = Math.min(...values);
  let maxValue = Math.max(...values);
  if (!Number.isFinite(minValue) || !Number.isFinite(maxValue)) {
    minValue = 0;
    maxValue = 1;
  }
  if (minValue === maxValue) {
    minValue *= 0.92;
    maxValue *= 1.08;
    if (minValue === maxValue) {
      minValue = 0;
      maxValue = maxValue || 1;
    }
  }
  const rangePadding = (maxValue - minValue) * 0.12;
  minValue -= rangePadding;
  maxValue += rangePadding;

  const width = 1000;
  const height = 420;
  const padding = { top: 36, right: 84, bottom: 36, left: 36 };
  const plotWidth = width - padding.left - padding.right;
  const plotHeight = height - padding.top - padding.bottom;
  const step = orderedCandles.length > 1 ? plotWidth / (orderedCandles.length - 1) : 0;

  const xForIndex = (index) => padding.left + (orderedCandles.length === 1 ? plotWidth / 2 : step * index);
  const yForValue = (value) => {
    const ratio = (value - minValue) / Math.max(maxValue - minValue, 1e-9);
    return height - padding.bottom - (ratio * plotHeight);
  };

  const defs = createSvgElement("defs");
  const gradient = createSvgElement("linearGradient", {
    id: "fill-area-gradient",
    x1: "0%",
    y1: "0%",
    x2: "0%",
    y2: "100%",
  });
  gradient.append(
    createSvgElement("stop", {
      offset: "0%",
      "stop-color": "#63bbff",
      "stop-opacity": "0.44",
    }),
    createSvgElement("stop", {
      offset: "100%",
      "stop-color": "#63bbff",
      "stop-opacity": "0.02",
    }),
  );
  defs.append(gradient);
  priceChart.append(defs);

  for (let index = 0; index < 5; index += 1) {
    const value = minValue + ((maxValue - minValue) * index) / 4;
    const y = yForValue(value);
    priceChart.append(
      createSvgElement("line", {
        x1: padding.left,
        x2: width - padding.right,
        y1: y,
        y2: y,
        stroke: "rgba(255,255,255,0.10)",
        "stroke-width": 1,
      }),
    );
    const label = createSvgElement("text", {
      x: width - padding.right + 12,
      y: y + 4,
      fill: "rgba(255,255,255,0.68)",
      "font-size": 14,
      "font-family": "SFMono-Regular, SF Mono, JetBrains Mono, monospace",
    });
    label.textContent = formatAmount(value, 4);
    priceChart.append(label);
  }

  const points = orderedCandles.map((point, index) => ({
    ...point,
    x: xForIndex(index),
    y: yForValue(point.price),
  }));
  const linePath = points
    .map((point, index) => `${index === 0 ? "M" : "L"} ${point.x.toFixed(2)} ${point.y.toFixed(2)}`)
    .join(" ");
  const areaPath = [
    linePath,
    `L ${points[points.length - 1].x.toFixed(2)} ${(height - padding.bottom).toFixed(2)}`,
    `L ${points[0].x.toFixed(2)} ${(height - padding.bottom).toFixed(2)}`,
    "Z",
  ].join(" ");

  priceChart.append(
    createSvgElement("path", {
      d: areaPath,
      fill: "url(#fill-area-gradient)",
      opacity: 1,
    }),
  );

  if (Number.isFinite(metrics.avgEntry)) {
    const avgY = yForValue(metrics.avgEntry);
    priceChart.append(
      createSvgElement("line", {
        x1: padding.left,
        x2: width - padding.right,
        y1: avgY,
        y2: avgY,
        stroke: "#f4c95d",
        "stroke-width": 2,
        "stroke-dasharray": "8 8",
      }),
    );
    const avgLabel = createSvgElement("text", {
      x: width - padding.right + 12,
      y: avgY - 8,
      fill: "#f4c95d",
      "font-size": 12,
      "font-family": "SFMono-Regular, SF Mono, JetBrains Mono, monospace",
    });
    avgLabel.textContent = `avg ${formatAmount(metrics.avgEntry, 4)}`;
    priceChart.append(avgLabel);
  }

  priceChart.append(
    createSvgElement("path", {
      d: linePath,
      fill: "none",
      stroke: "#8bc4ff",
      "stroke-width": 3,
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
    }),
  );

  const minTimestamp = orderedCandles[0]?.timestampMs ?? 0;
  const maxTimestamp = orderedCandles[orderedCandles.length - 1]?.timestampMs ?? minTimestamp;
  const xForTimestamp = (timestampMs, fallbackIndex = 0) => {
    if (!Number.isFinite(timestampMs) || minTimestamp === maxTimestamp) {
      return xForIndex(fallbackIndex);
    }
    const ratio = (timestampMs - minTimestamp) / Math.max(maxTimestamp - minTimestamp, 1);
    return padding.left + (ratio * plotWidth);
  };

  fills.slice().reverse().forEach((fill, index) => {
    const marker = createSvgElement("circle", {
      cx: xForTimestamp(fill.timestampMs, index),
      cy: yForValue(fill.price),
      r: index === fills.length - 1 ? 6 : 4,
      fill: fill.side === "buy" ? "#1f9b69" : "#cf4856",
      stroke: "#0f1722",
      "stroke-width": 2,
    });
    priceChart.append(marker);
  });

  const title = createSvgElement("text", {
    x: padding.left,
    y: 22,
    fill: "rgba(255,255,255,0.82)",
    "font-size": 15,
    "font-family": "Avenir Next, Segoe UI, sans-serif",
  });
  title.textContent = candles.length
    ? `Swap candles in ${symbols.baseSymbol} per ${symbols.quoteSymbol}`
    : `Executed price in ${symbols.baseSymbol} per ${symbols.quoteSymbol}`;
  priceChart.append(title);
}

function renderRecentFills(fills, symbols) {
  recentFills.replaceChildren();
  if (!fills.length) {
    recentFills.textContent = "No fills loaded yet.";
    recentFills.className = "fill-stack empty-copy";
    return;
  }

  recentFills.className = "fill-stack";
  fills.slice(0, 6).forEach((fill) => {
    const card = document.createElement("article");
    card.className = "fill-card";

    const headline = document.createElement("strong");
    headline.textContent = fill.side === "buy"
      ? `Bought ${formatAssetAmount(fill.amountOut, symbols.quoteSymbol)}`
      : `Sold ${formatAssetAmount(fill.amountIn, symbols.quoteSymbol)}`;
    card.append(headline);

    const detail = document.createElement("div");
    detail.className = "subdued";
    detail.textContent = fill.side === "buy"
      ? `Spent ${formatAssetAmount(fill.amountIn, symbols.baseSymbol)} at ${formatAmount(fill.price, 4)} ${symbols.baseSymbol}`
      : `Realized ${formatAssetAmount(fill.amountOut, symbols.baseSymbol)} at ${formatAmount(fill.price, 4)} ${symbols.baseSymbol}`;
    card.append(detail);

    const meta = document.createElement("div");
    meta.className = "fill-meta";
    const left = document.createElement("span");
    left.textContent = formatTimestamp(fill.timestampMs, `Record #${fill.recordId}`);
    const right = document.createElement("span");
    right.textContent = fill.executionHash
      ? truncateMiddle(fill.executionHash, 10, 8)
      : `journal #${fill.recordId}`;
    meta.append(left, right);
    card.append(meta);

    recentFills.append(card);
  });
}

function renderJournal(fills, symbols) {
  journalBody.replaceChildren();
  if (!fills.length) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 7;
    cell.className = "empty-row";
    cell.textContent = currentAuthority()
      ? "No executed router fills were found for this authority."
      : "Enter an authority and refresh to load fills.";
    row.append(cell);
    journalBody.append(row);
    return;
  }

  fills.forEach((fill) => {
    const row = document.createElement("tr");

    const timeCell = document.createElement("td");
    timeCell.textContent = formatTimestamp(fill.timestampMs, `#${fill.recordId}`);
    row.append(timeCell);

    const sideCell = document.createElement("td");
    const sidePill = document.createElement("span");
    sidePill.className = `side-pill ${fill.side}`;
    sidePill.textContent = fill.side === "buy" ? "Buy Quote" : "Sell Quote";
    sideCell.append(sidePill);
    row.append(sideCell);

    const inCell = document.createElement("td");
    inCell.textContent = fill.side === "buy"
      ? formatAssetAmount(fill.amountIn, symbols.baseSymbol)
      : formatAssetAmount(fill.amountIn, symbols.quoteSymbol);
    row.append(inCell);

    const outCell = document.createElement("td");
    outCell.textContent = fill.side === "buy"
      ? formatAssetAmount(fill.amountOut, symbols.quoteSymbol)
      : formatAssetAmount(fill.amountOut, symbols.baseSymbol);
    row.append(outCell);

    const priceCell = document.createElement("td");
    priceCell.textContent = `${formatAmount(fill.price, 4)} ${symbols.baseSymbol}`;
    row.append(priceCell);

    const protectionCell = document.createElement("td");
    protectionCell.textContent = formatPercent(fill.protectionRatio);
    row.append(protectionCell);

    const hashCell = document.createElement("td");
    const hashCode = document.createElement("code");
    hashCode.title = fill.executionHash || `journal record ${fill.recordId}`;
    hashCode.textContent = fill.executionHash
      ? truncateMiddle(fill.executionHash, 10, 8)
      : `record-${fill.recordId}`;
    hashCell.append(hashCode);
    row.append(hashCell);

    journalBody.append(row);
  });
}

function renderModuleRadar(modules) {
  moduleRadar.replaceChildren();
  if (!modules.length) {
    moduleRadar.textContent = "No module summaries loaded yet.";
    moduleRadar.className = "radar-stack empty-copy";
    return;
  }

  moduleRadar.className = "radar-stack";
  modules.forEach((module) => {
    const row = document.createElement("button");
    row.type = "button";
    row.className = `radar-row ${module.statusTone}`;
    row.classList.toggle("selected", module.key === availableModuleKey(state.selectedModuleKey));
    row.addEventListener("click", () => {
      applyModuleSelection(module.key);
    });

    const heading = document.createElement("div");
    heading.className = "radar-heading";

    const label = document.createElement("strong");
    label.textContent = module.label;
    heading.append(label);

    const status = document.createElement("span");
    status.className = `status-chip ${module.statusTone}`;
    status.textContent = module.statusLabel;
    heading.append(status);
    row.append(heading);

    const value = document.createElement("div");
    value.className = "radar-value";
    value.textContent = module.radarValue;
    row.append(value);

    const copy = document.createElement("div");
    copy.className = "subdued";
    copy.textContent = module.blurb;
    row.append(copy);

    moduleRadar.append(row);
  });
}

function renderModuleGrid(modules) {
  moduleGrid.replaceChildren();
  if (!modules.length) {
    const panel = document.createElement("article");
    panel.className = "module-card empty-panel";
    panel.textContent = "No module summaries loaded yet.";
    moduleGrid.append(panel);
    return;
  }

  modules.forEach((module) => {
    const card = document.createElement("button");
    card.type = "button";
    card.className = `module-card ${module.statusTone}`;
    card.classList.toggle("selected", module.key === availableModuleKey(state.selectedModuleKey));
    card.addEventListener("click", () => {
      applyModuleSelection(module.key);
    });

    const header = document.createElement("div");
    header.className = "module-card-header";

    const titleLockup = document.createElement("div");
    const title = document.createElement("h4");
    title.textContent = module.label;
    const contract = document.createElement("p");
    contract.className = "subdued module-contract";
    contract.textContent = module.contractKey;
    titleLockup.append(title, contract);
    header.append(titleLockup);

    const status = document.createElement("span");
    status.className = `status-chip ${module.statusTone}`;
    status.textContent = module.statusLabel;
    header.append(status);
    card.append(header);

    const hero = document.createElement("div");
    hero.className = "module-hero";
    hero.textContent = module.hero;
    card.append(hero);

    const copy = document.createElement("p");
    copy.className = "subdued module-copy";
    copy.textContent = module.blurb;
    card.append(copy);

    const metricGrid = document.createElement("div");
    metricGrid.className = "module-metrics";
    module.metrics.forEach((metric) => {
      const cell = document.createElement("article");
      cell.className = "module-metric";
      const label = document.createElement("span");
      label.textContent = metric.label;
      const value = document.createElement("strong");
      value.textContent = metric.value;
      cell.append(label, value);
      metricGrid.append(cell);
    });
    card.append(metricGrid);

    const footer = document.createElement("div");
    footer.className = "module-footer";
    const address = document.createElement("code");
    address.textContent = module.contractAddress
      ? truncateMiddle(module.contractAddress, 14, 10)
      : "no contract";
    footer.append(address);
    card.append(footer);

    moduleGrid.append(card);
  });
}

function filteredUnifiedActivities() {
  if (!Array.isArray(state.workspace?.unifiedActivities)) {
    return [];
  }
  if (state.activityFilterKey === "all") {
    return state.workspace.unifiedActivities;
  }
  return state.workspace.unifiedActivities.filter((item) => item.moduleKey === state.activityFilterKey);
}

function renderActivityFilters(modules) {
  activityFilterBar.replaceChildren();

  const allButton = document.createElement("button");
  allButton.type = "button";
  allButton.className = "filter-chip";
  allButton.classList.toggle("active", state.activityFilterKey === "all");
  allButton.textContent = "All products";
  allButton.addEventListener("click", () => {
    applyActivityFilter("all");
  });
  activityFilterBar.append(allButton);

  modules.forEach((module) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `filter-chip ${module.key}`;
    button.classList.toggle("active", state.activityFilterKey === module.key);
    button.textContent = module.label;
    button.addEventListener("click", () => {
      applyActivityFilter(module.key);
    });
    activityFilterBar.append(button);
  });
}

function renderFocusedModule(module, items) {
  if (!module) {
    focusTitle.textContent = "Swaps";
    focusCopy.textContent = "Select a product from the radar or overview to keep one surface in focus while the rest stay visible.";
    focusHero.textContent = "-";
    focusContract.innerHTML = "<code>-</code>";
    focusMetrics.innerHTML = '<article class="module-metric"><span>Loading</span><strong>-</strong></article>';
    focusFeedCount.textContent = "0";
    focusFeed.textContent = "No focused product activity yet.";
    focusFeed.className = "focus-event-list empty-copy";
    return;
  }

  focusTitle.textContent = module.label;
  focusCopy.textContent = module.blurb;
  focusHero.textContent = module.hero;
  focusContract.innerHTML = "";
  const contractCode = document.createElement("code");
  contractCode.textContent = module.contractAddress
    ? `${module.contractKey} · ${truncateMiddle(module.contractAddress, 18, 12)}`
    : `${module.contractKey} · not deployed`;
  focusContract.append(contractCode);

  focusMetrics.replaceChildren();
  module.metrics.forEach((metric) => {
    const cell = document.createElement("article");
    cell.className = "module-metric";
    const label = document.createElement("span");
    label.textContent = metric.label;
    const value = document.createElement("strong");
    value.textContent = metric.value;
    cell.append(label, value);
    focusMetrics.append(cell);
  });

  focusFeedCount.textContent = String(items.length);
  focusFeed.replaceChildren();
  if (!items.length) {
    focusFeed.textContent = "No focused product activity yet.";
    focusFeed.className = "focus-event-list empty-copy";
    return;
  }

  focusFeed.className = "focus-event-list";
  items.slice(0, 5).forEach((item) => {
    const event = document.createElement("article");
    event.className = "focus-event";

    const header = document.createElement("div");
    header.className = "focus-event-header";
    const action = document.createElement("strong");
    action.textContent = item.action;
    const time = document.createElement("span");
    time.className = "subdued";
    time.textContent = formatTimestamp(item.timestampMs, "-");
    header.append(action, time);
    event.append(header);

    const exposure = document.createElement("div");
    exposure.className = "focus-event-body";
    exposure.textContent = item.exposure;
    event.append(exposure);

    const context = document.createElement("div");
    context.className = "subdued";
    context.textContent = item.context;
    event.append(context);

    focusFeed.append(event);
  });
}

function renderUnifiedActivity(items) {
  activityBody.replaceChildren();
  if (!items.length) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 6;
    cell.className = "empty-row";
    cell.textContent = currentAuthority()
      ? "No recent cross-product activity was found for this authority."
      : "Enter an authority to load recent product activity.";
    row.append(cell);
    activityBody.append(row);
    return;
  }

  items.forEach((item) => {
    const row = document.createElement("tr");

    const timeCell = document.createElement("td");
    timeCell.textContent = formatTimestamp(item.timestampMs, "-");
    row.append(timeCell);

    const productCell = document.createElement("td");
    const pill = document.createElement("span");
    pill.className = `product-pill ${item.moduleKey}`;
    pill.textContent = item.moduleLabel;
    productCell.append(pill);
    row.append(productCell);

    const actionCell = document.createElement("td");
    actionCell.textContent = item.action;
    row.append(actionCell);

    const exposureCell = document.createElement("td");
    exposureCell.textContent = item.exposure;
    row.append(exposureCell);

    const contextCell = document.createElement("td");
    contextCell.textContent = item.context;
    row.append(contextCell);

    const executionCell = document.createElement("td");
    const code = document.createElement("code");
    code.textContent = truncateMiddle(item.executionHash || "-", 10, 8);
    code.title = item.executionHash || "-";
    executionCell.append(code);
    row.append(executionCell);

    activityBody.append(row);
  });
}

function applySignedClass(element, value) {
  element.classList.remove("positive", "negative", "neutral");
  if (!Number.isFinite(value) || value === 0) {
    element.classList.add("neutral");
    return;
  }
  element.classList.add(value > 0 ? "positive" : "negative");
}

function renderWorkspace() {
  renderDeploymentSummary();
  renderLiveStatus();

  if (!state.workspace) {
    pairSymbol.textContent = "XOR / ???";
    pairCopy.textContent = "Swap history is stitched from the router journal plus Torii contract events.";
    metricAvgEntry.textContent = "-";
    metricAvgExit.textContent = "-";
    metricOpenPosition.textContent = "-";
    metricRealizedPnl.textContent = "-";
    metricTotalPnl.textContent = "-";
    insightLastPrice.textContent = "-";
    insightUnrealizedPnl.textContent = "-";
    insightWinRate.textContent = "-";
    insightCushion.textContent = "-";
    insightBaseSpent.textContent = "-";
    insightBaseRealized.textContent = "-";
    recentFills.textContent = "No fills loaded yet.";
    recentFills.className = "fill-stack empty-copy";
    moduleRadar.textContent = "No module summaries loaded yet.";
    moduleRadar.className = "radar-stack empty-copy";
    focusTitle.textContent = "Swaps";
    focusCopy.textContent = "Select a product from the radar or overview to keep one surface in focus while the rest stay visible.";
    focusHero.textContent = "-";
    focusContract.innerHTML = "<code>-</code>";
    focusMetrics.innerHTML = '<article class="module-metric"><span>Loading</span><strong>-</strong></article>';
    focusFeedCount.textContent = "0";
    focusFeed.textContent = "No focused product activity yet.";
    focusFeed.className = "focus-event-list empty-copy";
    historyHeadDisplay.textContent = "-";
    historyCountDisplay.textContent = "-";
    applySignedClass(metricRealizedPnl, NaN);
    applySignedClass(metricTotalPnl, NaN);
    applySignedClass(insightUnrealizedPnl, NaN);
    moduleGrid.innerHTML = '<article class="module-card empty-panel">Loading module summaries…</article>';
    activityFilterBar.innerHTML = '<button type="button" class="filter-chip active">All products</button>';
    journalBody.innerHTML = '<tr><td colspan="7" class="empty-row">Loading…</td></tr>';
    activityBody.innerHTML = '<tr><td colspan="6" class="empty-row">Loading…</td></tr>';
    priceChart.replaceChildren();
    chartEmpty.style.display = "grid";
    chartEmpty.textContent = "No successful router swaps found for this authority.";
    syncTradeControls();
    return;
  }

  const {
    assets,
    historyHead,
    fills,
    candles,
    metrics,
    authority,
    modules,
    unifiedActivities,
  } = state.workspace;
  const symbols = {
    baseAssetId: assets.baseAssetId,
    quoteAssetId: assets.quoteAssetId,
    baseSymbol: assetTicker(assets.baseAssetId),
    quoteSymbol: assetTicker(assets.quoteAssetId),
  };
  const newestVisibleRecord = fills[0]?.recordId ?? null;
  const oldestVisibleRecord = fills[fills.length - 1]?.recordId ?? null;
  state.selectedModuleKey = availableModuleKey(state.selectedModuleKey);
  if (state.activityFilterKey !== "all" && !modules.some((module) => module.key === state.activityFilterKey)) {
    state.activityFilterKey = state.selectedModuleKey;
  }
  const selectedModule = currentSelectedModule();
  const visibleActivities = filteredUnifiedActivities();
  const focusedItems = (state.workspace.unifiedActivities || []).filter(
    (item) => item.moduleKey === selectedModule?.key,
  );

  pairSymbol.textContent = pairLabel(symbols.baseSymbol, symbols.quoteSymbol);
  pairCopy.textContent = authority
    ? `Executed fills, swap candles, and wallet-level trader math for ${truncateMiddle(authority, 16, 10)} using the deployed DLMM router.`
    : "Swap candles and fills loaded without an authority filter.";

  metricAvgEntry.textContent = Number.isFinite(metrics.avgEntry)
    ? `${formatAmount(metrics.avgEntry, 4)} ${symbols.baseSymbol}`
    : "-";
  metricAvgExit.textContent = Number.isFinite(metrics.avgExit)
    ? `${formatAmount(metrics.avgExit, 4)} ${symbols.baseSymbol}`
    : "-";
  metricOpenPosition.textContent = formatAssetAmount(metrics.openQuoteAmount, symbols.quoteSymbol);
  metricRealizedPnl.textContent = formatSignedAssetAmount(metrics.realizedPnlBase, symbols.baseSymbol);
  metricTotalPnl.textContent = formatSignedAssetAmount(metrics.totalPnlBase, symbols.baseSymbol);
  applySignedClass(metricRealizedPnl, metrics.realizedPnlBase);
  applySignedClass(metricTotalPnl, metrics.totalPnlBase);

  insightLastPrice.textContent = Number.isFinite(metrics.lastPrice)
    ? `${formatAmount(metrics.lastPrice, 4)} ${symbols.baseSymbol}`
    : "-";
  insightUnrealizedPnl.textContent = formatSignedAssetAmount(metrics.unrealizedPnlBase, symbols.baseSymbol);
  applySignedClass(insightUnrealizedPnl, metrics.unrealizedPnlBase);
  insightWinRate.textContent = formatPercent(metrics.winRate);
  insightCushion.textContent = formatPercent(metrics.avgCushionRatio);
  insightBaseSpent.textContent = formatAssetAmount(metrics.totalBaseSpent, symbols.baseSymbol);
  insightBaseRealized.textContent = formatAssetAmount(metrics.totalBaseRealized, symbols.baseSymbol);
  insightNote.textContent = fills.length
    ? `Showing ${formatCount(fills.length)} exact fills through router journal head ${historyHead}; newest visible record #${newestVisibleRecord}, oldest visible record #${oldestVisibleRecord}. The chart is sourced from ${formatCount(candles.length)} rollup candle${candles.length === 1 ? "" : "s"} while ${formatCount(modules.length)} trader surfaces stay live beside it.`
    : `No successful router fills are visible for this wallet yet. ${formatCount(modules.length)} trader surfaces are still summarized so the user can see product posture and submit from one frame.`;

  historyHeadDisplay.textContent = formatCount(historyHead);
  historyCountDisplay.textContent = formatCount(fills.length);

  renderRecentFills(fills, symbols);
  renderModuleRadar(modules);
  renderModuleGrid(modules);
  renderFocusedModule(selectedModule, focusedItems);
  renderActivityFilters(modules);
  renderJournal(fills, symbols);
  renderUnifiedActivity(visibleActivities);
  renderChart(fills, candles, metrics, symbols);
  syncTradeControls();
}

function clearWorkspaceForLoading(message) {
  state.workspace = null;
  renderWorkspace();
  setBanner(statusBanner, message, "muted");
}

async function refreshWorkspace(options = {}) {
  const token = ++state.refreshToken;
  const reloadCatalog = options.reloadCatalog !== false;

  try {
    if (reloadCatalog) {
      const catalog = await fetchCatalog();
      if (token !== state.refreshToken) {
        return;
      }
      normalizeEnvironmentSelection(catalog);
    }

    const environment = state.currentEnvironment;
    const contract = state.currentContract;
    const authority = currentAuthority();
    rememberAuthority();
    syncTradeControls();

    if (!environment) {
      throw new Error("No deployment environment was found.");
    }
    if (!contract) {
      throw new Error(`No deployed ${state.catalog?.preferred_contract_key || "router"} contract is available in ${environment.name}.`);
    }
    if (!authority) {
      clearWorkspaceForLoading("Enter an authority to load router state, chart history, and PnL.");
      ensureLiveFollow();
      return;
    }

    clearWorkspaceForLoading(
      `Loading ${environment.name} trader cockpit for ${truncateMiddle(authority, 16, 10)}…`,
    );

    const [
      accountResult,
      fillsResult,
      candlesResult,
      activityResult,
    ] = await Promise.all([
      fetchProxyGet("/api/contracts/rollups/trader/account", {
        environment: environment.name,
        authority,
      }),
      fetchProxyGet("/api/contracts/rollups/swaps/fills", {
        environment: environment.name,
        authority,
        limit: DEFAULT_VISIBLE_FILL_LIMIT,
      }),
      fetchProxyGet("/api/contracts/rollups/swaps/candles", {
        environment: environment.name,
        authority,
        limit: DEFAULT_CANDLE_LIMIT,
      }),
      fetchProxyGet("/api/contracts/rollups/trader/activity", {
        environment: environment.name,
        authority,
        limit: DEFAULT_UNIFIED_ACTIVITY_LIMIT,
      }),
    ]);

    if (token !== state.refreshToken) {
      return;
    }

    const accountPayload = unwrapProxyValue(
      requireProxySuccess(accountResult, "trader account").response_json,
    ) || {};
    const fillsPayload = unwrapProxyValue(
      requireProxySuccess(fillsResult, "swap fills").response_json,
    ) || {};
    const candlesPayload = unwrapProxyValue(
      requireProxySuccess(candlesResult, "swap candles").response_json,
    ) || {};
    const activityPayload = unwrapProxyValue(
      requireProxySuccess(activityResult, "trader activity").response_json,
    ) || {};

    const assets = {
      baseAssetId: accountPayload?.assets?.baseAssetId || fillsPayload.base_asset_id || "xor#universal",
      quoteAssetId: accountPayload?.assets?.quoteAssetId || fillsPayload.quote_asset_id || "quote",
    };
    const symbols = {
      baseAssetId: assets.baseAssetId,
      quoteAssetId: assets.quoteAssetId,
      baseSymbol: assetTicker(assets.baseAssetId),
      quoteSymbol: assetTicker(assets.quoteAssetId),
    };
    const fills = normalizeRollupFills(fillsPayload.items);
    const candles = normalizeRollupCandles(candlesPayload.items);
    const metrics = accountPayload?.metrics && typeof accountPayload.metrics === "object"
      ? accountPayload.metrics
      : computeAnalytics(fills);
    let modules = normalizeModuleCards(accountPayload.modules);
    const missingModuleKeys = PRODUCT_DEFINITIONS
      .map((definition) => definition.key)
      .filter((key) => !modules.some((module) => module.key === key));
    if (missingModuleKeys.length) {
      const fallbackModules = await loadProductModules(environment, authority, fills, metrics, symbols);
      const fallbackByKey = new Map(fallbackModules.map((module) => [module.key, module]));
      modules = modules.concat(
        missingModuleKeys
          .map((key) => fallbackByKey.get(key))
          .filter(Boolean),
      );
    }
    const unifiedActivities = normalizeTraderActivityItems(activityPayload.items);
    const historyHead = normalizeInteger(accountPayload.historyHead ?? fillsPayload.history_head) ?? 0;

    state.workspace = {
      authority,
      assets,
      historyHead,
      fills,
      candles,
      metrics,
      modules,
      unifiedActivities,
    };
    renderWorkspace();

    setBanner(
      statusBanner,
      `Loaded ${formatCount(fills.length)} executed fill${fills.length === 1 ? "" : "s"} and ${formatCount(unifiedActivities.length)} recent product actions for ${truncateMiddle(authority, 16, 10)} on ${environment.name}.`,
      "success",
    );
    state.lastRefreshMs = Date.now();
    renderLiveStatus();
    ensureLiveFollow();
  } catch (error) {
    if (token !== state.refreshToken) {
      return;
    }
    console.error(error);
    state.workspace = null;
    renderWorkspace();
    setBanner(statusBanner, error.message || "Failed to load trader cockpit.", "error");
    ensureLiveFollow();
  }
}

function extractStatusKind(payload) {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  const directStatus = payload.status;
  if (directStatus && typeof directStatus === "object" && typeof directStatus.kind === "string") {
    return directStatus.kind;
  }
  if (typeof directStatus === "string") {
    return directStatus;
  }
  const nested = payload.content?.status;
  if (nested && typeof nested === "object" && typeof nested.kind === "string") {
    return nested.kind;
  }
  if (typeof nested === "string") {
    return nested;
  }
  return null;
}

async function waitForTransaction(environmentName, txHashHex) {
  const deadline = Date.now() + DEFAULT_TRANSACTION_POLL_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const payload = await fetchTransactionStatus(environmentName, txHashHex);
    const statusKind = extractStatusKind(payload);
    if (statusKind && (SUCCESS_STATUSES.has(statusKind) || FAILURE_STATUSES.has(statusKind))) {
      return statusKind;
    }
    await new Promise((resolve) => {
      window.setTimeout(resolve, DEFAULT_TRANSACTION_POLL_INTERVAL_MS);
    });
  }
  return "TimedOut";
}

async function submitTrade() {
  const validationError = tradeValidationError();
  if (validationError) {
    setBanner(tradeResult, validationError, "error");
    return;
  }

  const environment = state.currentEnvironment;
  const action = currentActionDefinition();
  const module = selectedTradeModule();
  const requestPayload = buildTradePreview();
  const confirmed = await confirmSignedMutation({
    environment: environment?.name,
    authority: requestPayload.authority,
    contract: module?.contractKey || selectedTradeModule()?.label || "Selected product",
    contractAddress: requestPayload.contract_address,
    action: action?.label || "Trader action",
    entrypoint: requestPayload.entrypoint,
    gasLimit: requestPayload.gas_limit,
    payload: requestPayload.payload,
  });
  if (!confirmed) {
    setBanner(tradeResult, "Cancelled before submission. No signed call was sent.", "muted");
    return;
  }

  tradeSubmit.disabled = true;
  setBanner(tradeResult, `Submitting ${action?.label || "action"}…`, "muted");

  try {
    const result = requireProxySuccess(
      await fetchProxyPost("/api/call", requestPayload),
      action?.entrypoint || "trader action",
    );
    const txHashHex = result.tx_hash_hex || result.response_json?.tx_hash_hex || result.entrypoint_hash;
    if (!txHashHex) {
      setBanner(tradeResult, `${action?.label || "Action"} submitted, but no transaction hash was returned.`, "success");
      await refreshWorkspace({ reloadCatalog: false });
      return;
    }

    setBanner(
      tradeResult,
      `${action?.label || "Action"} submitted. Waiting for ${truncateMiddle(txHashHex, 12, 10)}…`,
      "muted",
    );
    const statusKind = await waitForTransaction(environment.name, txHashHex);
    if (SUCCESS_STATUSES.has(statusKind)) {
      setBanner(
        tradeResult,
        `${action?.label || "Action"} committed as ${truncateMiddle(txHashHex, 12, 10)}.`,
        "success",
      );
      await refreshWorkspace({ reloadCatalog: false });
      return;
    }
    if (FAILURE_STATUSES.has(statusKind)) {
      setBanner(
        tradeResult,
        `${action?.label || "Action"} ${statusKind.toLowerCase()} for ${truncateMiddle(txHashHex, 12, 10)}.`,
        "error",
      );
      return;
    }
    setBanner(
      tradeResult,
      `${action?.label || "Action"} submitted as ${truncateMiddle(txHashHex, 12, 10)}, but status polling timed out.`,
      "muted",
    );
  } catch (error) {
    console.error(error);
    setBanner(tradeResult, error.message || "Trader action submission failed.", "error");
  } finally {
    syncTradeControls();
  }
}

function attachEventListeners() {
  refreshWorkspaceButton.addEventListener("click", () => {
    refreshWorkspace({ reloadCatalog: true });
  });

  environmentSelect.addEventListener("change", () => {
    applyEnvironment(environmentSelect.value);
    refreshWorkspace({ reloadCatalog: false });
  });

  authorityInput.addEventListener("input", () => {
    rememberAuthority();
    syncTradeControls();
    ensureLiveFollow();
  });

  authorityInput.addEventListener("change", () => {
    rememberAuthority();
    refreshWorkspace({ reloadCatalog: false });
  });

  tradeGasLimitInput.addEventListener("input", syncTradeControls);

  liveToggle.addEventListener("click", () => {
    state.liveModeEnabled = !state.liveModeEnabled;
    saveStorage(STORAGE_KEYS.liveModeEnabled, state.liveModeEnabled);
    if (!state.liveModeEnabled) {
      stopLiveInfrastructure();
      state.liveConnectionState = "paused";
      renderLiveStatus();
      return;
    }
    ensureLiveFollow();
  });

  window.addEventListener("beforeunload", () => {
    stopLiveInfrastructure();
  });

  tradeSubmit.addEventListener("click", submitTrade);
}

async function init() {
  tradeGasLimitInput.value = String(DEFAULT_GAS_LIMIT);
  attachEventListeners();
  renderLiveStatus();
  renderWorkspace();
  await refreshWorkspace({ reloadCatalog: true });
}

void init();
