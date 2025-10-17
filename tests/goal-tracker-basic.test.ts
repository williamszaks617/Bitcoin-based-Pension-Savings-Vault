import { describe, expect, it } from "vitest";

describe("Basic Goal Tracker Test", () => {
  it("ensures simnet is available", () => {
    expect(simnet).toBeDefined();
    expect(simnet.blockHeight).toBeDefined();
  });
});