const { defineConfig } = require("@playwright/test");

function requireTcpPort(name, rawValue) {
  if (!/^[0-9]+$/.test(rawValue)) {
    throw new Error(`${name} must be a TCP port from 1 through 65535; got '${rawValue}'`);
  }
  const port = Number(rawValue);
  if (port < 1 || port > 65535) {
    throw new Error(`${name} must be a TCP port from 1 through 65535; got '${rawValue}'`);
  }
  return String(port);
}

function requireBinaryFlag(name, rawValue) {
  if (rawValue === undefined || rawValue === "") {
    return true;
  }
  if (rawValue === "1") {
    return true;
  }
  if (rawValue === "0") {
    return false;
  }
  throw new Error(`${name} must be 0 or 1; got '${rawValue}'`);
}

function optionalBrowserChannel(name, rawValue) {
  if (rawValue === undefined || rawValue === "") {
    return undefined;
  }
  if (rawValue === "chrome" || rawValue === "msedge") {
    return rawValue;
  }
  throw new Error(`${name} must be chrome or msedge; got '${rawValue}'`);
}

const staticServerPort = requireTcpPort("SORASWAP_PLAYWRIGHT_PORT", process.env.SORASWAP_PLAYWRIGHT_PORT || "43174");
const staticServerUrl = `http://127.0.0.1:${staticServerPort}`;
const staticServerEnabled = requireBinaryFlag(
  "SORASWAP_PLAYWRIGHT_STATIC_SERVER",
  process.env.SORASWAP_PLAYWRIGHT_STATIC_SERVER,
);
const browserChannel = optionalBrowserChannel(
  "PLAYWRIGHT_SYSTEM_BROWSER_CHANNEL",
  process.env.PLAYWRIGHT_SYSTEM_BROWSER_CHANNEL,
);

module.exports = defineConfig({
  testDir: "./tests",
  testMatch: ["contract_console*.spec.js", "trader_ui.spec.js"],
  timeout: 30000,
  expect: {
    timeout: 5000,
  },
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: staticServerUrl,
    headless: true,
    channel: browserChannel,
  },
  webServer: staticServerEnabled
    ? {
      command: `python3 -m http.server ${staticServerPort} --bind 127.0.0.1 -d ui/contract_console`,
      url: staticServerUrl,
      reuseExistingServer: false,
    }
    : undefined,
});
