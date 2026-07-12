import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    clearMocks: true,
    restoreMocks: true,
    coverage: {
      reporter: ["text", "json-summary"],
    },
  },
});
