module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/simulations/tests"],
  moduleFileExtensions: ["ts", "js", "json"],
  testMatch: ["**/*.spec.ts"]
};
