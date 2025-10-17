
import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const contractName = "Bitcoin-based-Pension-Savings-Vault";

describe("Pension Savings Vault - Goal Tracker Feature", () => {
  
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("allows user enrollment with valid retirement age", () => {
    const { result } = simnet.callPublicFn(contractName, "enroll", [Cl.uint(65)], address1);
    expect(result).toBeOk(Cl.bool(true));
  });

  it("allows creating a pension goal after enrollment", () => {
    // Enroll user first
    simnet.callPublicFn(contractName, "enroll", [Cl.uint(65)], address1);
    
    // Create pension goal
    const { result } = simnet.callPublicFn(
      contractName,
      "create-pension-goal",
      [Cl.uint(50000000), Cl.uint(100000)], // 50 STX target, ~2 years
      address1
    );
    expect(result).toBeOk(Cl.uint(50000000));
  });

  it("prevents creating goal with invalid parameters", () => {
    simnet.callPublicFn(contractName, "enroll", [Cl.uint(65)], address1);
    
    // Too low amount
    const { result } = simnet.callPublicFn(
      contractName,
      "create-pension-goal",
      [Cl.uint(1000000), Cl.uint(100000)], // 1 STX - too low
      address1
    );
    expect(result).toBeErr(Cl.uint(202)); // ERR-INVALID-GOAL-AMOUNT
  });

  it("allows adding milestones to goals", () => {
    // Setup
    simnet.callPublicFn(contractName, "enroll", [Cl.uint(65)], address1);
    simnet.callPublicFn(contractName, "create-pension-goal", [Cl.uint(50000000), Cl.uint(100000)], address1);
    
    // Add milestone
    const { result } = simnet.callPublicFn(
      contractName,
      "add-goal-milestone",
      [Cl.uint(25)], // 25% milestone
      address1
    );
    expect(result).toBeOk(Cl.uint(0)); // First milestone ID
  });

  it("tracks goal progress correctly", () => {
    // Setup
    simnet.callPublicFn(contractName, "enroll", [Cl.uint(65)], address1);
    simnet.callPublicFn(contractName, "create-pension-goal", [Cl.uint(40000000), Cl.uint(100000)], address1);
    simnet.callPublicFn(contractName, "add-goal-milestone", [Cl.uint(25)], address1);
    
    // Make deposit
    simnet.callPublicFn(contractName, "deposit", [Cl.uint(10000000)], address1);
    
    // Update progress
    const { result } = simnet.callPublicFn(contractName, "update-goal-progress", [], address1);
    expect(result).toBeOk(Cl.stringAscii("progress-updated"));
  });

  it("returns goal information", () => {
    // Setup
    simnet.callPublicFn(contractName, "enroll", [Cl.uint(65)], address1);
    simnet.callPublicFn(contractName, "create-pension-goal", [Cl.uint(30000000), Cl.uint(100000)], address1);
    
    // Check goal info
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-pension-goal",
      [Cl.principal(address1)],
      address1
    );
    expect(result).toBeSome();
  });

  it("calculates progress percentage", () => {
    // Setup
    simnet.callPublicFn(contractName, "enroll", [Cl.uint(65)], address1);
    simnet.callPublicFn(contractName, "create-pension-goal", [Cl.uint(40000000), Cl.uint(100000)], address1);
    simnet.callPublicFn(contractName, "deposit", [Cl.uint(10000000)], address1);
    simnet.callPublicFn(contractName, "update-goal-progress", [], address1);
    
    // Check percentage
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-goal-progress-percentage",
      [Cl.principal(address1)],
      address1
    );
    expect(result).toBeOk(Cl.uint(25)); // 25%
  });

  it("allows goal deactivation", () => {
    // Setup
    simnet.callPublicFn(contractName, "enroll", [Cl.uint(65)], address1);
    simnet.callPublicFn(contractName, "create-pension-goal", [Cl.uint(30000000), Cl.uint(100000)], address1);
    
    // Deactivate
    const { result } = simnet.callPublicFn(contractName, "deactivate-goal", [], address1);
    expect(result).toBeOk(Cl.bool(true));
  });
});
