# Dexynth Multilevel Real Yield Staking

## 🛡️ Security Audit & Hardening (v2.1 - Jan 2026)
A comprehensive internal audit and hardening phase was conducted to ensure mathematical correctness and robust security guarantees.

### 1. Invariant Testing & Fuzzing
- **Stateful Fuzzing Suite**: Implemented a comprehensive invariant testing suite (`test/invariant/`) using Foundry's `Handler` pattern.
- **Math Consistency Verified**: Detected and fixed a critical rounding error in `totalBoostedStake` calculation (rounding error accumulation).
- **Solvency Check**: Verified that the contract is always solvent.

### 2. Reentrancy Protection (CEI + Guard)
- **Strict CEI Pattern**: Refactored all critical functions (`stake`, `unstake`, `addStakingReward`, `executeMigration`) to strictly follow **Checks-Effects-Interactions**.
- **Defense in Depth**: Added `nonReentrant` modifiers to minimal functions including admin migrations.

### 3. Code Quality
- **Explicit Precisions**: Replaced magic numbers with `ACC_PRECISION` and `BOOST_PRECISION` constants.
- **Indexed Events**: Added indexing to `address` parameters in migration events.
- **Loop Optimizations**: Cached array lengths for gas efficiency.

## 🚀 Major Refactoring & Optimization (v2 - Dec 2025)

The staking system has undergone a complete architectural overhaul to transition from an O(N) epoch-looping model to an **O(1) MasterChef-style** accumulator model. This ensures constant gas costs regardless of the number of epochs or stakes.

### ⚡️ Gas Optimizations & Refactoring
- **O(1) MasterChef Rewards**: Replaced heavy loops with `accRewardPerShare` accumulators. Gas usage is now constant (< 200k) even after 10 years of staking.
- **Variable Packaging**: Optimized data types (e.g., `uint40` for timestamps, `uint32` for epochs) and reordered state variables/struct members from smallest to largest to pack them into fewer storage slots.
- **Custom Errors**: Replaced string revert messages with Custom Errors (e.g., `error StakeStillLocked()`) to save deployment and runtime gas.
- **Explicit Types**: Standardized usage of `uint256` instead of implicit `uint` for clarity and consistency.
- **Visibility Optimization**: Refactored public functions to `external` (`stake`, `unstake`, `harvest`, etc.) to reduce gas costs on function calls.
- **Loop Optimization**: Implemented `unchecked` arithmetic in for-loops and epoch math to save gas on increment operations.
- **Generic Token Support**: Renamed `USDT` to `REWARD_TOKEN` to make the contract asset-agnostic.
- **SafeCast**: Integrated OpenZeppelin's `SafeCast` for all type conversions to prevent silent overflows.
- **NatSpec**: 100% documentation coverage.

### 🔐 Security & Code Quality Improvements (Dec 2025)
- **Timelock Migration**: Replaced instant `migrateContract()` with a 30-day timelock system (`requestMigration` → `executeMigration`).
- **Dynamic Immutable Levels**: Refactored from fixed 5-level array to dynamic `Level[]` array set at deployment.
- **Access Control**: Replaced custom `onlyGov` with OpenZeppelin's `onlyOwner`.

### 🧹 Code Cleanup
- Removed deprecated `lastEpochHarvested` field from `User` struct.
- Removed deprecated `EpochClosed` event.
- Removed unused legacy mappings (`sEpoch`, `sStakedTokensPerWallet...`).

### 📊 Gas Performance (Optimized v2.1 - Jan 2026)
Current gas consumption benchmarks showing the evolution from v1 legacy to v2.1 hardened:

| Operation | Original Gas (v1) | V2 Gas (Dec) | **Hardened Gas (v2.1)** | Total Improvement (v1 → v2.1) |
| :--- | :--- | :--- | :--- | :--- |
| **Stake** | 260,117 | ~159,799 | **~167,017** | **~35.8%** 📉 |
| **Unstake** | > 3M+ (linear) | ~95,642 | **~95,083** | **> 96%** 📉 |
| **Harvest** | > 500k+ (linear) | ~166,370 | **~139,235** | **> 72%** 📉 |

> *Note: The slight gas increase in `stake` compared to v2 (+4%) is a deliberate trade-off to guarantee mathematical consistency and prevent rounding error accumulation.*

### 🛠️ Running Tests
```bash
# Run unit tests
forge test

# Run invariant tests (stateful fuzzing)
forge test --match-contract Invariant
```

### 🧪 Advanced Testing Strategy
- **Invariant Tests**: Validates core protocol invariants (solvency, level consistency vs global) using randomized actor sequences (`Handler.sol`).
- **Fuzzing Tests**: Property-based testing using Foundry's Fuzzing capabilities.
- **State-Dependent Fuzzing**: Created complex fuzzing scenarios that simulate time passage and state changes.
- **Tooling Migration**: Hardhat → Foundry complete.

---

## Overview

**Dexynth Multilevel Real Yield Staking** is a staking smart contract designed to distribute **Real Yield** in the form of USDT. Users stake their DEXY tokens and choose a lock-up period (level), which determines their reward multiplier. The longer the lock, the higher the share of the rewards pool they receive.

To ensure the correctness of the staking model and reward logic, the design was first created in an **Excel spreadsheet**, where all calculations were tested under various scenarios. This spreadsheet provided a clear blueprint for the contract implementation and was later validated through a comprehensive **unit test suite** to compare the expected and actual values generated by the contract.

## Key Features

- **Stake and Unstake**: Users can lock $DEXY tokens in the contract and withdraw them after the lock period ends.  
- **Reward Scaling**: Rewards increase based on staking level, incentivizing longer lock durations with higher returns.  
- **Epoch-Based Distribution**: Rewards and staking mechanics are organized into distinct time intervals (epochs).  
- **Administrative Control**: Administrators can add rewards to the pool and adjust contract parameters.

---

## Staking Levels

The contract offers five staking levels, each with different lock periods and reward boosts:

| **Level** | **Lock Period** | **Multiplier** |
|-----------|-----------------|----------------|
| 0         | 30 days         | 0.65x          |
| 1         | 90 days         | 0.85x          |
| 2         | 180 days        | 1.00x          |
| 3         | 1 year          | 1.15x          |
| 4         | 2 years         | 1.35x          |

---

## Core Methods

### **Staking**
Allows users to lock $DEXY tokens in a specific staking level.  
```solidity
function stake(uint256 _amount, uint8 _level) external;
```
- `_amount`: Number of $DEXY tokens to stake (18 decimals).  
- `_level`: Desired staking level (0-4).  

### **Unstaking**
Enables users to withdraw their staked tokens after the lock period ends.  
```solidity
function unstake(uint64 _stakeIndex) external;
```
- `_stakeIndex`: Index of the user's staking position.

### **Harvesting Rewards**
Lets users claim accumulated $USDT rewards.  
```solidity
function harvest() external;
```
### **Adding Rewards**  
Allows administrators to deposit $USDT rewards into the staking pool.  
```solidity
function addStakingReward(uint256 _amount, uint256 _duration) external;
```
- `_amount`: Amount of $USDT to add to the pool (18 decimals).
- `_duration`: Duration in seconds over which to distribute the rewards.

---

## Validation Process: From Excel to Unit Tests  

### **Excel Design**  
The design of the staking contract was first created in an Excel model to simulate and confirm the expected mechanics of the staking system. This allowed for:  
- Simulating rewards for various staking levels and lock periods.  
- Testing scenarios with multiple users staking and unstaking simultaneously.  
- Ensuring token distribution adhered to predefined parameters.  

The Excel model served as a reference for comparison with unit-tests and on-chain results, helping ensure the contract logic was implemented correctly.

![Excel model 1](./images/staking_excel_1.png)

![Excel model 2](./images/staking_excel_2.png)

![Excel model 1](./images/staking_excel_3.png)

---

### **Unit Tests & Fuzzing**  
After validating the logic in Excel, unit tests were created to replicate and rigorously verify the functionality on-chain. The tests, found in [DexynthStaking.t.sol](./test/DexynthStaking.t.sol), focus on critical aspects of the contract, including:

1. **Staking Functionality**  
   - Ensures users can stake $DEXY tokens at any of the defined levels (0-4).  
   - Validates proper updates to staking balances, timestamps, and lock periods.  

2. **Unstaking Behavior**  
   - Confirms users can only unstake their tokens after the defined lock period.  
   - Verifies that early unstaking attempts are correctly rejected.  

3. **Reward Accrual and Distribution**  
   - Matches reward calculations to the Excel model's projections.  
   - Tests for the correct behavior when the reward pool is depleted.

4. **Harvesting Rewards**  
   - Ensures users can claim rewards without unstaking their tokens.  
   - Validates that rewards do not exceed the available balance in the reward pool.

5. **Administrative Functions**  
   - Confirms that only authorized accounts can add rewards or update parameters.  
   - Prevents unauthorized access to sensitive functions.

6. **Edge Cases**  
   - Prevents staking of zero tokens.  
   - Handles cases where rewards have been exhausted gracefully.

7. **Invariant Testing (Stateful Fuzzing)**
   - Validates solvency guarantees (contract always has enough tokens for liabilities).
   - Ensures mathematical consistency of staking levels vs global totals.
   - Verifies system stability under randomized chaotic inputs (`Handler.sol`) over simulated time epochs.

---

## Security Considerations  

The contract implements various security features to protect against vulnerabilities:  
- **Reentrancy Protection**: The `ReentrancyGuard` modifier is used to prevent reentrancy attacks.  
- **Safe Transfers**: The `SafeERC20` library ensures secure interactions with ERC20 tokens.  
- **Access Control**: Administrative actions are restricted to designated roles, mitigating unauthorized changes.

---

## Additional Notes  

This contract has been validated through multiple layers of testing and simulation. Continuous auditing and monitoring are advised to ensure robustness as the system evolves.
