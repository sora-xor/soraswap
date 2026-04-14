const { defineConfig } = require("@playwright/test");

module.exports = defineConfig({
  testDir: "./tests",
  testMatch: ["contract_console*.spec.js"],
  timeout: 30000,
  expect: {
    timeout: 5000,
  },
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: "http://127.0.0.1:43174",
    headless: true,
  },
  webServer: {
    command: "python3 -m http.server 43174 --bind 127.0.0.1 -d ui/contract_console",
    url: "http://127.0.0.1:43174",
    reuseExistingServer: false,
  },
});
