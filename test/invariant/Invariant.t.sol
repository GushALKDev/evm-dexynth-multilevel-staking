// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DexynthStakingV2_1} from "../../src/DexynthStaking.sol";
import {DEXYToken} from "../../src/DEXY.sol";
import {RewardToken} from "../../src/RewardToken.sol";
import {Handler} from "./Handler.sol";

/**
 * @title DexynthStakingV2_1 Invariant Tests
 * @notice Stateful fuzz testing to verify protocol invariants
 * @dev Uses Handler pattern for bounded actions
 */
contract Invariant is StdInvariant, Test {
    /*//////////////////////////////////////////////////////////////
                               STATE
    //////////////////////////////////////////////////////////////*/
    
    DexynthStakingV2_1 public staking;
    DEXYToken public dexy;
    RewardToken public rewardToken;
    Handler public handler;

    /*//////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/
    
    function setUp() public {
        // Set a reasonable starting timestamp
        vm.warp(2_000_000_000);
        
        // Deploy tokens
        dexy = new DEXYToken();
        rewardToken = new RewardToken();

        // Setup staking levels
        DexynthStakingV2_1.Level[] memory levels = new DexynthStakingV2_1.Level[](5);
        levels[0] = DexynthStakingV2_1.Level(2592000, 6500000000, 0);   // 30 days, 0.65x
        levels[1] = DexynthStakingV2_1.Level(7776000, 8500000000, 0);   // 90 days, 0.85x
        levels[2] = DexynthStakingV2_1.Level(15552000, 10000000000, 0); // 180 days, 1.0x
        levels[3] = DexynthStakingV2_1.Level(31536000, 11500000000, 0); // 365 days, 1.15x
        levels[4] = DexynthStakingV2_1.Level(62208000, 13500000000, 0); // 720 days, 1.35x

        // Deploy staking contract
        staking = new DexynthStakingV2_1(
            address(dexy),
            address(rewardToken),
            levels,
            1296000 // 15 days epoch
        );

        // Deploy handler
        handler = new Handler(staking, dexy, rewardToken);

        // Configure invariant testing
        targetContract(address(handler));
        
        // Only fuzz these functions
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = Handler.stake.selector;
        selectors[1] = Handler.unstake.selector;
        selectors[2] = Handler.harvest.selector;
        selectors[3] = Handler.addStakingReward.selector;
        selectors[4] = Handler.advanceTime.selector;
        selectors[5] = Handler.advanceOneEpoch.selector;
        
        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));

        // Exclude direct calls to staking (all actions go through handler)
        excludeContract(address(staking));
        excludeContract(address(dexy));
        excludeContract(address(rewardToken));
    }

    /*//////////////////////////////////////////////////////////////
                     CORE INVARIANTS - SOLVENCY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice INVARIANT: Contract must always hold enough DEXY to cover all stakes
     * @dev This is the most critical invariant - if it fails, users cannot withdraw
     */
    function invariant_dexyStakingSolvency() public view {
        uint256 contractBalance = dexy.balanceOf(address(staking));
        uint256 expectedStaked = handler.ghost_totalStaked();
        
        assertGe(
            contractBalance, 
            expectedStaked, 
            "CRITICAL: Contract DEXY balance < Total staked. Users cannot withdraw!"
        );
    }

    /**
     * @notice INVARIANT: Rewards distributed cannot exceed rewards added
     * @dev Prevents reward inflation or unauthorized minting
     */
    function invariant_rewardsSolvency() public view {
        uint256 totalAdded = handler.ghost_totalRewardsAdded();
        uint256 totalHarvested = handler.ghost_totalRewardsHarvested();
        
        assertGe(
            totalAdded,
            totalHarvested,
            "CRITICAL: More rewards harvested than added!"
        );
    }

    /*//////////////////////////////////////////////////////////////
                 CORE INVARIANTS - STATE CONSISTENCY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice INVARIANT: Sum of level.totalStaked must equal global ghost total
     * @dev Ensures no tokens are "lost" between level accounting
     */
    function invariant_levelTotalConsistency() public view {
        uint256 sumOfLevels = 0;
        DexynthStakingV2_1.Level[] memory levels = staking.getLevels();
        
        for (uint256 i = 0; i < levels.length; i++) {
            sumOfLevels += levels[i].totalStaked;
            
            // Also verify each level matches handler ghost state
            assertEq(
                levels[i].totalStaked,
                handler.getGhostLevelStaked(uint8(i)),
                string.concat("Level ", vm.toString(i), " totalStaked mismatch")
            );
        }
        
        assertEq(
            sumOfLevels,
            handler.ghost_totalStaked(),
            "Sum of all levels != ghost_totalStaked"
        );
    }

    /**
     * @notice INVARIANT: totalBoostedStake must match calculated value
     * @dev Ensures boost calculations are consistent
     */
    function invariant_boostedStakeConsistency() public view {
        uint256 calculatedBoosted = 0;
        DexynthStakingV2_1.Level[] memory levels = staking.getLevels();

        for (uint256 i = 0; i < levels.length; i++) {
            calculatedBoosted += (uint256(levels[i].totalStaked) * levels[i].boostP) / 1e10;
        }

        assertEq(
            calculatedBoosted,
            staking.totalBoostedStake(),
            "totalBoostedStake calculation inconsistent"
        );
    }

    /**
     * @notice INVARIANT: User totalStakedDexy must match sum of their active stakes
     * @dev Prevents accounting errors in user state
     */
    function invariant_userStakeConsistency() public view {
        uint256 actorCount = handler.getActorCount();
        
        for (uint256 a = 0; a < actorCount; a++) {
            address actor = handler.getActor(a);
            (uint64 stakeCount, uint128 totalStakedDexy, ) = staking.users(actor);
            
            // Sum all active stakes for this user
            uint256 sumActiveStakes = 0;
            for (uint64 i = 0; i < stakeCount; i++) {
                (bool unstaked, , , , , uint128 stakedDexy, ) = staking.stakeInfo(actor, i);
                if (!unstaked) {
                    sumActiveStakes += stakedDexy;
                }
            }
            
            assertEq(
                uint256(totalStakedDexy),
                sumActiveStakes,
                string.concat("User ", vm.toString(actor), " stake accounting mismatch")
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INVARIANTS - TEMPORAL CONSTRAINTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice INVARIANT: lastRewardTime <= current block.timestamp
     * @dev Ensures reward time tracking doesn't go into the future
     */
    function invariant_lastRewardTimeNotFuture() public view {
        assertLe(
            staking.lastRewardTime(),
            block.timestamp,
            "lastRewardTime is in the future!"
        );
    }

    /**
     * @notice INVARIANT: Stake unlockTime >= rewardStartTime
     * @dev Lock period starts from next epoch, unlock must be after
     */
    function invariant_unlockTimeAfterRewardStart() public view {
        uint256 actorCount = handler.getActorCount();
        
        for (uint256 a = 0; a < actorCount; a++) {
            address actor = handler.getActor(a);
            (uint64 stakeCount, , ) = staking.users(actor);
            
            for (uint64 i = 0; i < stakeCount; i++) {
                (, , , uint40 rewardStartTime, uint40 unlockTime, , ) = staking.stakeInfo(actor, i);
                
                assertGe(
                    unlockTime,
                    rewardStartTime,
                    "unlockTime < rewardStartTime violates lock semantics"
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                      INVARIANTS - CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice INVARIANT: Number of levels never changes
     * @dev Levels are immutable after deployment
     */
    function invariant_levelsImmutable() public view {
        assertEq(
            staking.getNumberOfLevels(),
            5,
            "Number of levels changed unexpectedly"
        );
    }

    /**
     * @notice INVARIANT: Level boost values are ordered (higher level = higher boost)
     * @dev Ensures incentive structure remains valid
     */
    function invariant_boostOrderPreserved() public view {
        DexynthStakingV2_1.Level[] memory levels = staking.getLevels();
        
        for (uint256 i = 0; i < levels.length - 1; i++) {
            assertLt(
                levels[i].boostP,
                levels[i + 1].boostP,
                "Boost order violated: lower level has higher boost"
            );
            assertLt(
                levels[i].lockingPeriod,
                levels[i + 1].lockingPeriod,
                "Lock period order violated"
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                         AFTER INVARIANT HOOK
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Called after invariant tests complete - prints summary
     */
    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
