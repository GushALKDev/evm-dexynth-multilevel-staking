// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {Test} from "forge-std/Test.sol";
import {DexynthStakingV2_1} from "../src/DexynthStaking.sol";
import {DEXYToken} from "../src/DEXY.sol";
import {RewardToken} from "../src/RewardToken.sol";

contract DexynthStakingTest is Test {
    DexynthStakingV2_1 public staking;
    DEXYToken public dexy;
    RewardToken public rewardToken;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        // Set timestamp first to avoid underflow in constructor
        vm.warp(2000000000);

        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);

        // Deploy Tokens
        dexy = new DEXYToken();
        rewardToken = new RewardToken();

        // Setup Levels (dynamic array)
        DexynthStakingV2_1.Level[] memory levels = new DexynthStakingV2_1.Level[](5);
        levels[0] = DexynthStakingV2_1.Level(2592000, 6500000000, 0);
        levels[1] = DexynthStakingV2_1.Level(7776000, 8500000000, 0);
        levels[2] = DexynthStakingV2_1.Level(15552000, 10000000000, 0);
        levels[3] = DexynthStakingV2_1.Level(31536000, 11500000000, 0);
        levels[4] = DexynthStakingV2_1.Level(62208000, 13500000000, 0);

        // Deploy Staking
        staking = new DexynthStakingV2_1(
            address(dexy),
            address(rewardToken),
            levels,
            1296000
        );

        // Setup Balances
        require(dexy.transfer(address(staking), 10_000_000 ether), "Transfer failed");
        
        require(dexy.transfer(user1, 100_000 ether), "Transfer failed");
        require(dexy.transfer(user2, 100_000 ether), "Transfer failed");
        require(dexy.transfer(user3, 100_000 ether), "Transfer failed");

        // Approvals
        vm.prank(user1);
        dexy.approve(address(staking), 100_000 ether);
        
        vm.prank(user2);
        dexy.approve(address(staking), 100_000 ether);
        
        vm.prank(user3);
        dexy.approve(address(staking), 100_000 ether);

        // Owner approves USDT for rewards
        rewardToken.approve(address(staking), 100_000 ether);
        
        // Set timestamp
        vm.warp(2000000000);
    }

    function testDeploy() public view {
        assertEq(staking.owner(), owner);
        assertEq(dexy.owner(), owner);
        assertEq(rewardToken.owner(), owner);
    }

    function testLevelsAreImmutable() public view {
        // Verify levels were set correctly in constructor
        assertEq(staking.getNumberOfLevels(), 5);
        
        // getLevels now returns Level[] directly
        DexynthStakingV2_1.Level[] memory levels = staking.getLevels();
        assertEq(levels[0].lockingPeriod, 2592000);
        assertEq(levels[0].boostP, 6500000000);
        assertEq(levels[4].lockingPeriod, 62208000);
        assertEq(levels[4].boostP, 13500000000);
    }

    function testMigrationWithTimelock() public {
        // Setup some balances
        staking.addStakingReward(1000 ether, 30 days); // USDT with 30 day duration
        
        vm.prank(user1);
        staking.stake(500 ether, 0); // DEXY
        
        address newContract = address(0x999);
        
        // Request migration
        staking.requestMigration(newContract);
        
        // Verify state
        assertEq(staking.pendingMigrationAddress(), newContract);
        assertGt(staking.migrationRequestTime(), 0);
        
        // Try to execute before timelock - should fail
        vm.expectRevert(DexynthStakingV2_1.TimelockStillActive.selector);
        staking.executeMigration();
        
        // Wait for timelock (30 days)
        vm.warp(block.timestamp + 30 days + 1);
        
        uint256 rewardTokenBalBefore = rewardToken.balanceOf(newContract);
        uint256 dexyBalBefore = dexy.balanceOf(newContract);
        
        // Execute migration
        staking.executeMigration();
        
        uint256 rewardTokenBalAfter = rewardToken.balanceOf(newContract);
        uint256 dexyBalAfter = dexy.balanceOf(newContract);
        
        assertEq(rewardTokenBalAfter - rewardTokenBalBefore, 1000 ether);
        // In setUp, we transferred 10_000_000 ether DEXY to staking contract.
        // Plus user1 staked 500 ether.
        // Total DEXY in contract = 10_000_000 + 500 = 10_000_500 ether.
        assertEq(dexyBalAfter - dexyBalBefore, 10_000_500 ether);
        
        assertEq(rewardToken.balanceOf(address(staking)), 0);
        assertEq(dexy.balanceOf(address(staking)), 0);
    }

    function testMigrationCancel() public {
        address newContract = address(0x999);
        
        // Request migration
        staking.requestMigration(newContract);
        assertEq(staking.pendingMigrationAddress(), newContract);
        
        // Cancel migration
        staking.cancelMigration();
        
        // Verify state is cleared
        assertEq(staking.pendingMigrationAddress(), address(0));
        assertEq(staking.migrationRequestTime(), 0);
    }

    function testMigrationFailNotGov() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        staking.requestMigration(address(0x999));
    }

    function testMigrationFailAlreadyPending() public {
        staking.requestMigration(address(0x999));
        
        vm.expectRevert(DexynthStakingV2_1.MigrationAlreadyPending.selector);
        staking.requestMigration(address(0x888));
    }

    function testMigrationFailNoRequest() public {
        vm.expectRevert(DexynthStakingV2_1.NoMigrationRequested.selector);
        staking.executeMigration();
        
        vm.expectRevert(DexynthStakingV2_1.NoMigrationRequested.selector);
        staking.cancelMigration();
    }

    function testGetLevels() public view {
        DexynthStakingV2_1.Level[] memory levelsData = staking.getLevels();
        // Check a few values - using hardcoded expected values since levels are set in constructor
        assertEq(levelsData[0].lockingPeriod, 2592000);
        assertEq(levelsData[0].boostP, 6500000000);
        assertEq(levelsData[4].lockingPeriod, 62208000);
        assertEq(levelsData[4].boostP, 13500000000);
    }

    // --- MasterChef Reward Tests ---

    function testRewardRateAccumulation() public {
        staking.addStakingReward(10000 ether, 30 days);
        uint256 rate1 = staking.rewardRate();
        assertGt(rate1, 0); // Verify rate was set
        
        // Wait some time
        vm.warp(block.timestamp + 10 days);
        
        // Second deposit should accumulate with remaining rewards
        staking.addStakingReward(5000 ether, 30 days);
        uint256 rate2 = staking.rewardRate();
        
        // Rate should reflect remaining + new rewards over new duration
        // After 10 days, 20 days remain of original 30 days
        uint256 minExpectedRate = 5000 ether / uint256(30 days);
        assertGt(rate2, minExpectedRate);
    }

    function testPendingRewards() public {
        // User stakes
        vm.prank(user1);
        staking.stake(1000 ether, 0);
        
        // Add rewards
        staking.addStakingReward(30000 ether, 30 days);
        
        // No rewards before next epoch starts
        assertEq(staking.pendingRewards(user1), 0);
        
        // Warp to next epoch + some time
        uint32 epochDuration = staking.epochDuration();
        vm.warp(block.timestamp + epochDuration + 5 days);
        
        // Should have pending rewards now
        uint256 pending = staking.pendingRewards(user1);
        assertGt(pending, 0);
    }

    function testRewardsDistributionByBoostLevel() public {
        // User1 stakes at level 0 (0.65x boost)
        vm.prank(user1);
        staking.stake(1000 ether, 0);
        
        // User2 stakes at level 4 (1.35x boost)
        vm.prank(user2);
        staking.stake(1000 ether, 4);
        
        // Add rewards
        staking.addStakingReward(20000 ether, 30 days);
        
        // Warp past next epoch start
        uint32 epochDuration = staking.epochDuration();
        vm.warp(block.timestamp + epochDuration + 10 days);
        
        // Check pending rewards - user2 should have more due to higher boost
        uint256 pending1 = staking.pendingRewards(user1);
        uint256 pending2 = staking.pendingRewards(user2);
        
        assertGt(pending2, pending1);
        
        // Boost ratio is 1.35 / 0.65 ≈ 2.07
        // So user2 should have roughly 2x user1's rewards
        assertGt(pending2 * 100 / pending1, 150); // At least 1.5x
    }

    function testNoRewardsBeforeRewardStartTime() public {
        // Add rewards first
        staking.addStakingReward(10000 ether, 30 days);
        
        // User stakes
        vm.prank(user1);
        staking.stake(1000 ether, 0);
        
        // Check pending - should be 0 because still before rewardStartTime
        assertEq(staking.pendingRewards(user1), 0);
        
        // Even after some time but before epoch ends
        vm.warp(block.timestamp + 5 days);
        assertEq(staking.pendingRewards(user1), 0);
    }

    function testO1GasPerformance() public {
        // Stake
        vm.prank(user1);
        staking.stake(1000 ether, 0);
        
        // Add rewards
        staking.addStakingReward(100000 ether, 365 days);
        
        // Warp 100 epochs forward - this would be O(n) with old system
        uint32 epochDuration = staking.epochDuration();
        vm.warp(block.timestamp + epochDuration * 100);
        
        // Harvest should still be O(1) - gas should not scale with epochs
        uint256 gasBefore = gasleft();
        vm.prank(user1);
        staking.harvest();
        uint256 gasUsed = gasBefore - gasleft();
        
        // With O(n) implementation, this would use millions of gas
        // With O(1) and SafeCast overhead, it should be constant (approx 190k)
        assertLt(gasUsed, 250000);
    }

    function testLevelTotalStakedUpdates() public {
        // Check initial totalStaked is 0
        DexynthStakingV2_1.Level[] memory levelsBefore = staking.getLevels();
        assertEq(levelsBefore[0].totalStaked, 0);
        
        // Stake
        vm.prank(user1);
        staking.stake(1000 ether, 0);
        
        // Check totalStaked increased
        DexynthStakingV2_1.Level[] memory levelsAfter = staking.getLevels();
        assertEq(levelsAfter[0].totalStaked, 1000 ether);
        
        // Warp and unstake
        vm.warp(block.timestamp + 365 days);
        vm.prank(user1);
        staking.unstake(0);
        
        // Check totalStaked decreased
        DexynthStakingV2_1.Level[] memory levelsEnd = staking.getLevels();
        assertEq(levelsEnd[0].totalStaked, 0);
    }

    // --- Epoch Semantics Tests ---

    function testGetCurrentEpochIndex() public {
        uint32 epochDuration = staking.epochDuration();
        uint32 epoch0 = staking.getCurrentEpochIndex();
        
        // Warp one epoch forward
        vm.warp(block.timestamp + epochDuration);
        uint32 epoch1 = staking.getCurrentEpochIndex();
        assertEq(epoch1, epoch0 + 1);
        
        // Warp another epoch
        vm.warp(block.timestamp + epochDuration);
        uint32 epoch2 = staking.getCurrentEpochIndex();
        assertEq(epoch2, epoch1 + 1);
    }

    function testRewardStartTimeAlignedWithEpoch() public {
        uint32 epochDuration = staking.epochDuration();
        uint40 genesisTimetamp = staking.I_GENESIS_EPOCH_TIMESTAMP();
        uint32 currentEpoch = staking.getCurrentEpochIndex();
        
        // Calculate expected next epoch start
        uint40 expectedNextEpochStart = uint40(genesisTimetamp + uint256(currentEpoch + 1) * epochDuration);
        
        // User stakes
        vm.prank(user1);
        staking.stake(1000 ether, 0);
        
        // Check stake's rewardStartTime matches next epoch start
        (, , , uint40 rewardStartTime, , , ) = staking.stakeInfo(user1, 0);
        assertEq(rewardStartTime, expectedNextEpochStart);
    }

    function testUnlockTimeCalculatedFromEpochStart() public {
        uint32 epochDuration = staking.epochDuration();
        DexynthStakingV2_1.Level[] memory levels = staking.getLevels();
        uint32 lockingPeriod = levels[0].lockingPeriod;
        
        // Get next epoch start
        uint40 genesisTimestamp = staking.I_GENESIS_EPOCH_TIMESTAMP();
        uint32 currentEpoch = staking.getCurrentEpochIndex();
        uint40 nextEpochStart = uint40(genesisTimestamp + uint256(currentEpoch + 1) * epochDuration);
        
        // User stakes at level 0
        vm.prank(user1);
        staking.stake(1000 ether, 0);
        
        // Check unlockTime = nextEpochStart + lockingPeriod
        (, , , , uint40 unlockTime, , ) = staking.stakeInfo(user1, 0);
        assertEq(unlockTime, nextEpochStart + lockingPeriod);
    }

    // --- Stake Tests ---

    function testStakeDifferentLevels() public {
        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);
    }

    function testUsersBalancesAfterStaking() public {
        uint256 balanceUser1Before = dexy.balanceOf(user1);
        uint256 balanceUser2Before = dexy.balanceOf(user2);

        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);

        uint256 balanceUser1After = dexy.balanceOf(user1);
        uint256 balanceUser2After = dexy.balanceOf(user2);

        assertEq(balanceUser1Before - balanceUser1After, 1000 ether);
        assertEq(balanceUser2Before - balanceUser2After, 1800 ether);
        
        // Verify via Level.totalStaked instead of deprecated mapping
        DexynthStakingV2_1.Level[] memory levels = staking.getLevels();
        assertGt(levels[0].totalStaked + levels[4].totalStaked, 0);
    }

    function testUsersDataAfterStaking() public {
        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);

        (uint64 index1, uint128 totalStaked1, uint128 totalHarvested1) = staking.users(user1);
        (uint64 index2, uint128 totalStaked2, uint128 totalHarvested2) = staking.users(user2);

        assertEq(totalStaked1, 1000 ether);
        assertEq(totalStaked2, 1800 ether);
        assertEq(totalHarvested1, 0);
        assertEq(totalHarvested2, 0);
        assertEq(index1, 2);
        assertEq(index2, 1);
    }

    function testStakeDataAfterStaking() public {
        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);

        (, uint8 level1a, , uint40 start1a, , uint128 staked1a, ) = staking.stakeInfo(user1, 0);
        (, uint8 level1b, , uint40 start1b, , uint128 staked1b, ) = staking.stakeInfo(user1, 1);
        (, uint8 level2, , uint40 start2, , uint128 staked2, ) = staking.stakeInfo(user2, 0);

        assertEq(staked1a, 600 ether);
        assertEq(staked1b, 400 ether);
        assertEq(staked2, 1800 ether);

        assertEq(level1a, 0);
        assertEq(level1b, 4);
        assertEq(level2, 1);

        // rewardStartTime is the timestamp of next epoch start, not epoch index
        uint32 epochDuration = staking.epochDuration();
        uint40 genesisTimestamp = staking.I_GENESIS_EPOCH_TIMESTAMP();
        uint32 currentEpoch = staking.getCurrentEpochIndex();
        uint40 expectedStart = uint40(genesisTimestamp + uint256(currentEpoch + 1) * epochDuration);
        
        assertEq(start1a, expectedStart);
        assertEq(start1b, expectedStart);
        assertEq(start2, expectedStart);
    }

    function testStakeFailZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(DexynthStakingV2_1.WrongParams.selector);
        staking.stake(0, 0);
    }

    function testStakeFailInvalidLevel() public {
        vm.prank(user1);
        vm.expectRevert(DexynthStakingV2_1.WrongParams.selector);
        staking.stake(100 ether, 5); // Level 5 does not exist (0-4)
    }

    // --- Unstake Tests ---

    function testUnstake() public {
        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);

        // Forward time to unlock
        vm.warp(block.timestamp + 365 days); // Enough for all levels

        vm.prank(user1);
        staking.unstake(0);

        vm.prank(user2);
        staking.unstake(0);
    }

    function testUsersBalancesAfterUnstaking() public {
        uint256 balanceUser1Before = dexy.balanceOf(user1);
        uint256 balanceUser2Before = dexy.balanceOf(user2);

        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);

        vm.warp(block.timestamp + 365 days);

        vm.prank(user1);
        staking.unstake(0);

        vm.prank(user2);
        staking.unstake(0);

        uint256 balanceUser1After = dexy.balanceOf(user1);
        uint256 balanceUser2After = dexy.balanceOf(user2);

        // User 1 staked 1000 total, unstaked 600. Net change -400.
        assertEq(balanceUser1Before - balanceUser1After, 400 ether);
        // User 2 staked 1800, unstaked 1800. Net change 0.
        assertEq(balanceUser2Before, balanceUser2After);
    }

    function testUsersDataAfterUnstaking() public {
        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);

        vm.warp(block.timestamp + 365 days);

        vm.prank(user1);
        staking.unstake(0);

        vm.prank(user2);
        staking.unstake(0);

        (, uint128 totalStaked1, ) = staking.users(user1);
        (, uint128 totalStaked2, ) = staking.users(user2);

        assertEq(totalStaked1, 400 ether);
        assertEq(totalStaked2, 0);
    }

    function testStakeDataAfterUnstaking() public {
        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);

        vm.warp(block.timestamp + 365 days);

        vm.prank(user1);
        staking.unstake(0);

        vm.prank(user2);
        staking.unstake(0);

        (bool unstaked1a, , , , , , ) = staking.stakeInfo(user1, 0);
        (bool unstaked1b, , , , , , ) = staking.stakeInfo(user1, 1);
        (bool unstaked2, , , , , , ) = staking.stakeInfo(user2, 0);

        assertEq(unstaked1a, true);
        assertEq(unstaked1b, false);
        assertEq(unstaked2, true);
    }

    function testUnstakeLocked() public {
        vm.prank(user1);
        staking.stake(600 ether, 0);

        // Try to unstake immediately
        vm.prank(user1);
        vm.expectRevert(DexynthStakingV2_1.StakeStillLocked.selector);
        staking.unstake(0);
    }

    function testUnstakeTwice() public {
        vm.prank(user1);
        staking.stake(600 ether, 0);

        vm.warp(block.timestamp + 365 days);

        vm.startPrank(user1);
        staking.unstake(0);
        vm.expectRevert(DexynthStakingV2_1.AlreadyUnstaked.selector);
        staking.unstake(0); // Should fail
        vm.stopPrank();
    }

    // --- Harvest Tests ---

    function testHarvest() public {
        staking.addStakingReward(20000 ether, 30 days);

        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);

        vm.warp(block.timestamp + 30 days + 100); // Ensure epochs close

        vm.prank(user1);
        staking.harvest();

        vm.prank(user2);
        staking.harvest();
    }

    function testUsersBalancesAfterHarvesting() public {
        staking.addStakingReward(20000 ether, 30 days);
        uint256 balanceUser1Before = rewardToken.balanceOf(user1);
        uint256 balanceUser2Before = rewardToken.balanceOf(user2);

        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);

        vm.warp(block.timestamp + 30 days + 100);

        vm.prank(user1);
        staking.harvest();

        vm.prank(user2);
        staking.harvest();

        uint256 balanceUser1After = rewardToken.balanceOf(user1);
        uint256 balanceUser2After = rewardToken.balanceOf(user2);

        // Rewards are distributed based on boost points.
        // User 1: 600*1 (L0) + 400*1.75 (L4) = 600 + 700 = 1300 boost points
        // User 2: 1800*1.25 (L1) = 2250 boost points
        // Total boost: 3550
        // Rewards approx 20000 distributed over 2 epochs (Epoch 1 and Epoch 2).
        // Users staked in Epoch 2.
        // Current Epoch at setup is 1.
        // Staking starts at current + 1 = 2.
        // So they only get rewards for Epoch 2.
        // Epoch 2 rewards ~ 10000.
        // User 1 share: 10000 * 1300 / 3550 ~ 3661
        // User 2 share: 10000 * 2250 / 3550 ~ 6338
        
        assertGt(balanceUser1After - balanceUser1Before, 3600 ether);
        assertGt(balanceUser2After - balanceUser2Before, 6000 ether);
    }

    function testUsersDataAfterHarvesting() public {
        staking.addStakingReward(20000 ether, 30 days);

        vm.startPrank(user1);
        staking.stake(600 ether, 0);
        staking.stake(400 ether, 4);
        vm.stopPrank();

        vm.prank(user2);
        staking.stake(1800 ether, 1);

        vm.warp(block.timestamp + 30 days + 100);

        vm.prank(user1);
        staking.harvest();

        vm.prank(user2);
        staking.harvest();

        (, , uint128 totalHarvested1) = staking.users(user1);
        (, , uint128 totalHarvested2) = staking.users(user2);

        assertGt(totalHarvested1, 0);
        assertGt(totalHarvested2, 0);
        // In MasterChef pattern, lastEpochHarvested is no longer updated
    }

    function testHarvestTwice() public {
        staking.addStakingReward(20000 ether, 30 days);
        vm.prank(user1);
        staking.stake(600 ether, 0);

        vm.warp(block.timestamp + 30 days + 100);

        vm.startPrank(user1);
        staking.harvest();
        vm.expectRevert(DexynthStakingV2_1.NoRewardsToHarvest.selector);
        staking.harvest(); // Should fail: NoRewardsToHarvest (already harvested)
        vm.stopPrank();
    }

    function testHarvestNoRewards() public {
        // No rewards added
        vm.prank(user1);
        staking.stake(600 ether, 0);

        vm.warp(block.timestamp + 30 days + 100);

        vm.prank(user1);
        // Even if epochs have passed, if no rewards were added (accRewards = 0),
        // the calculated rewards will be 0.
        // The contract checks if totalUserRewards == 0 at the end of harvest()
        // and reverts with NoRewardsToHarvest if so.
        
        vm.expectRevert(DexynthStakingV2_1.NoRewardsToHarvest.selector);
        staking.harvest(); 
    }

    // --- Fuzz Tests ---
    function testFuzz_Stake(uint256 amount, uint8 level) public {
        // Bound inputs to valid ranges
        // Amount: 1 wei to 100,000 ether (user balance)
        amount = bound(amount, 1, 100_000 ether);
        // Level: 0 to 4
        level = uint8(bound(level, 0, 4));

        uint256 balanceBefore = dexy.balanceOf(user1);
        
        vm.startPrank(user1);
        staking.stake(amount, level);
        vm.stopPrank();

        uint256 balanceAfter = dexy.balanceOf(user1);
        
        // Verify balance change
        assertEq(balanceBefore - balanceAfter, amount);

        // Verify stake info
        (, uint8 stakedLevel, , , , uint128 staked, ) = staking.stakeInfo(user1, 0);
        assertEq(staked, amount);
        assertEq(stakedLevel, level);

        // Verify user totals
        (, uint128 totalStaked, ) = staking.users(user1);
        assertEq(totalStaked, amount);
    }

    function testFuzz_Unstake(uint256 _amount, uint8 _levelIndex) public {
        // Bound inputs
        _amount = bound(_amount, 1 ether, 100_000 ether);
        _levelIndex = uint8(bound(_levelIndex, 0, 4));

        // Setup
        uint256 initialBalance = dexy.balanceOf(user1);
        
        vm.startPrank(user1);
        staking.stake(_amount, _levelIndex);
        
        // Get locking period from contract
        DexynthStakingV2_1.Level[] memory levelsData = staking.getLevels();
        uint256 lockingPeriod = levelsData[_levelIndex].lockingPeriod;
        
        // Warp to unlock (lockingPeriod + 1 epoch buffer to ensure we are in the next epoch)
        // The contract requires: getCurrentEpochIndex() >= unlockingEpoch
        // unlockingEpoch = startingEpoch + (lockingPeriod / epochDuration)
        // startingEpoch = current + 1
        // So we need to pass lockingPeriod + current epoch remainder.
        // Adding 2 * epochDuration is a safe buffer.
        vm.warp(block.timestamp + lockingPeriod + 1296000 * 2);
        
        // Unstake (index 0 because it's the first stake)
        staking.unstake(0);
        vm.stopPrank();

        // Assertions
        assertEq(dexy.balanceOf(user1), initialBalance);
    }

    function testFuzz_Harvest(uint256 _amount, uint8 _levelIndex, uint32 _epochsToWait) public {
        // Bound inputs
        _amount = bound(_amount, 1 ether, 100_000 ether);
        _levelIndex = uint8(bound(_levelIndex, 0, 4));
        _epochsToWait = uint32(bound(_epochsToWait, 2, 50)); // Wait at least 2 epochs to ensure 1 full epoch passed

        // Setup Stake
        vm.prank(user1);
        staking.stake(_amount, _levelIndex);

        // Add Rewards (as owner)
        uint256 rewardAmount = 10_000 ether;
        staking.addStakingReward(rewardAmount, 30 days);

        // Warp time
        // epochDuration is 1296000
        vm.warp(block.timestamp + (uint256(_epochsToWait) * 1296000));

        // Harvest
        vm.prank(user1);
        staking.harvest();

        // Assertions
        assertGt(rewardToken.balanceOf(user1), 0);
    }

    function testFuzz_MultipleStakes(uint256 amount1, uint8 level1, uint256 amount2, uint8 level2) public {
        // Bound inputs
        amount1 = bound(amount1, 1 ether, 50_000 ether);
        amount2 = bound(amount2, 1 ether, 50_000 ether); // Ensure sum doesn't exceed 100k balance
        level1 = uint8(bound(level1, 0, 4));
        level2 = uint8(bound(level2, 0, 4));

        vm.startPrank(user1);
        staking.stake(amount1, level1);
        staking.stake(amount2, level2);
        vm.stopPrank();

        // Verify User Totals
        (uint64 stakeIndex, uint128 totalStaked, ) = staking.users(user1);
        assertEq(totalStaked, amount1 + amount2);
        assertEq(stakeIndex, 2);

        // Verify Individual Stakes
        (, uint8 l1, , , , uint128 staked1, ) = staking.stakeInfo(user1, 0);
        (, uint8 l2, , , , uint128 staked2, ) = staking.stakeInfo(user1, 1);

        assertEq(staked1, amount1);
        assertEq(l1, level1);
        assertEq(staked2, amount2);
        assertEq(l2, level2);
    }

    function testFuzz_DynamicRewards(uint256 stakeAmount, uint8 levelIndex, uint256 rewardAmount, uint32 epochsToWait) public {
        // Bound inputs
        stakeAmount = bound(stakeAmount, 1 ether, 100_000 ether);
        levelIndex = uint8(bound(levelIndex, 0, 4));
        // Reward: from 1 ether to 1M ether
        rewardAmount = bound(rewardAmount, 1 ether, 1_000_000 ether); 
        epochsToWait = uint32(bound(epochsToWait, 2, 50));

        // Setup Stake
        vm.prank(user1);
        staking.stake(stakeAmount, levelIndex);

        // Mint and Approve Rewards
        // Ensure test contract has enough USDT (minted in constructor)
        require(rewardToken.transfer(address(this), rewardAmount), "Transfer failed"); 
        rewardToken.approve(address(staking), rewardAmount);

        // Add Rewards
        staking.addStakingReward(rewardAmount, 30 days);

        // Warp time
        vm.warp(block.timestamp + (uint256(epochsToWait) * 1296000));

        // Harvest
        vm.prank(user1);
        staking.harvest();

        // Assertions
        assertGt(rewardToken.balanceOf(user1), 0);
    }

}
