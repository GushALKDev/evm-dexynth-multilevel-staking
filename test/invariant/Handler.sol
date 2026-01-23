// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DexynthStakingV2_1} from "../../src/DexynthStaking.sol";
import {DEXYToken} from "../../src/DEXY.sol";
import {RewardToken} from "../../src/RewardToken.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title Handler for DexynthStakingV2_1 Invariant Testing
 * @notice Provides bounded actions for stateful fuzz testing
 * @dev Tracks ghost variables to verify protocol invariants
 */
contract Handler is Test {
    /*//////////////////////////////////////////////////////////////
                               STATE
    //////////////////////////////////////////////////////////////*/
    
    DexynthStakingV2_1 public staking;
    DEXYToken public dexy;
    RewardToken public rewardToken;

    // Ghost variables - shadow state for invariant verification
    uint256 public ghost_totalStaked;
    uint256 public ghost_totalRewardsAdded;
    uint256 public ghost_totalRewardsHarvested;
    mapping(uint8 => uint256) public ghost_levelStaked;
    mapping(address => uint256) public ghost_userStaked;
    mapping(address => uint256) public ghost_userHarvested;
    
    // Actor management
    address[] public actors;
    address internal currentActor;
    mapping(address => bool) public isActor;
    uint256 public constant NUM_ACTORS = 10;
    
    // Call tracking for debugging
    mapping(bytes4 => uint256) public callCount;
    uint256 public totalCalls;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(DexynthStakingV2_1 _staking, DEXYToken _dexy, RewardToken _rewardToken) {
        staking = _staking;
        dexy = _dexy;
        rewardToken = _rewardToken;
        
        // Pre-initialize actors for more realistic testing
        for (uint256 i = 0; i < NUM_ACTORS; i++) {
            address actor = address(uint160(0x1000 + i));
            actors.push(actor);
            isActor[actor] = true;
            
            // Approve staking contract
            vm.prank(actor);
            dexy.approve(address(staking), type(uint256).max);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[actorIndexSeed % NUM_ACTORS];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }
    
    modifier trackCall() {
        callCount[msg.sig]++;
        totalCalls++;
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          HANDLER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake DEXY tokens at a given level
     * @param actorSeed Seed to select actor
     * @param amount Amount to stake (will be bounded)
     * @param levelIndex Level index (will be bounded to 0-4)
     */
    function stake(
        uint256 actorSeed, 
        uint256 amount, 
        uint8 levelIndex
    ) public useActor(actorSeed) trackCall {
        // Bound inputs
        amount = bound(amount, 1 ether, 100_000 ether);
        levelIndex = uint8(bound(levelIndex, 0, staking.getNumberOfLevels() - 1));
        
        // Fund the actor
        deal(address(dexy), currentActor, amount);

        staking.stake(amount, levelIndex);

        // Update ghost state
        ghost_totalStaked += amount;
        ghost_levelStaked[levelIndex] += amount;
        ghost_userStaked[currentActor] += amount;
    }

    /**
     * @notice Unstake DEXY tokens from a specific stake
     * @param actorSeed Seed to select actor
     * @param stakeIndexSeed Seed to select stake index
     */
    function unstake(
        uint256 actorSeed, 
        uint256 stakeIndexSeed
    ) public useActor(actorSeed) trackCall {
        (uint64 userStakeCount, , ) = staking.users(currentActor);
        
        // Skip if user has no stakes
        if (userStakeCount == 0) return;

        uint64 stakeIndex = uint64(stakeIndexSeed % userStakeCount);
        
        // Get stake info
        (
            bool unstaked, 
            uint8 level, 
            , 
            , 
            uint40 unlockTime, 
            uint128 stakedDexy, 
        ) = staking.stakeInfo(currentActor, stakeIndex);

        // Skip if already unstaked or still locked
        if (unstaked) return;
        if (block.timestamp < unlockTime) return;

        // Get pending rewards before unstake (unstake also harvests)
        uint256 rewardBalanceBefore = rewardToken.balanceOf(currentActor);
        
        staking.unstake(stakeIndex);
        
        uint256 rewardBalanceAfter = rewardToken.balanceOf(currentActor);
        uint256 harvestedOnUnstake = rewardBalanceAfter - rewardBalanceBefore;

        // Update ghost state
        ghost_totalStaked -= stakedDexy;
        ghost_levelStaked[level] -= stakedDexy;
        ghost_userStaked[currentActor] -= stakedDexy;
        ghost_totalRewardsHarvested += harvestedOnUnstake;
        ghost_userHarvested[currentActor] += harvestedOnUnstake;
    }

    /**
     * @notice Harvest pending rewards for an actor
     * @param actorSeed Seed to select actor
     */
    function harvest(uint256 actorSeed) public useActor(actorSeed) trackCall {
        (, uint128 totalStakedDexy, ) = staking.users(currentActor);
        
        // Skip if user has nothing staked
        if (totalStakedDexy == 0) return;
        
        // Check if there are pending rewards
        uint256 pending = staking.pendingRewards(currentActor);
        if (pending == 0) return;
        
        uint256 rewardBalanceBefore = rewardToken.balanceOf(currentActor);
        
        staking.harvest();
        
        uint256 rewardBalanceAfter = rewardToken.balanceOf(currentActor);
        uint256 harvested = rewardBalanceAfter - rewardBalanceBefore;

        // Update ghost state
        ghost_totalRewardsHarvested += harvested;
        ghost_userHarvested[currentActor] += harvested;
    }

    /**
     * @notice Add staking rewards (owner action)
     * @param amount Amount of rewards to add
     * @param duration Duration over which to distribute
     */
    function addStakingReward(
        uint256 amount, 
        uint256 duration
    ) public trackCall {
        amount = bound(amount, 1 ether, 500_000 ether);
        duration = bound(duration, 1 days, 180 days);

        address owner = staking.owner();
        
        // Fund owner with reward tokens
        deal(address(rewardToken), owner, amount);
        
        vm.startPrank(owner);
        rewardToken.approve(address(staking), amount);
        staking.addStakingReward(amount, duration);
        vm.stopPrank();

        // Update ghost state
        ghost_totalRewardsAdded += amount;
    }

    /**
     * @notice Advance time (critical for lock periods and rewards)
     * @param secondsSeed Seed for time advancement
     */
    function advanceTime(uint256 secondsSeed) public trackCall {
        uint256 seconds_ = bound(secondsSeed, 1 hours, 90 days);
        vm.warp(block.timestamp + seconds_);
    }

    /**
     * @notice Advance time by exactly one epoch
     */
    function advanceOneEpoch() public trackCall {
        uint32 epochDuration = staking.epochDuration();
        vm.warp(block.timestamp + epochDuration);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get current actor count
     */
    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    /**
     * @notice Get actor by index
     */
    function getActor(uint256 index) external view returns (address) {
        return actors[index % actors.length];
    }

    /**
     * @notice Get ghost level staked for a specific level
     */
    function getGhostLevelStaked(uint8 level) external view returns (uint256) {
        return ghost_levelStaked[level];
    }

    /**
     * @notice Get ghost user staked amount
     */
    function getGhostUserStaked(address user) external view returns (uint256) {
        return ghost_userStaked[user];
    }

    /**
     * @notice Print call summary for debugging
     */
    function callSummary() external view {
        console.log("\n=== Handler Call Summary ===");
        console.log("Total calls:", totalCalls);
        console.log("---");
        console.log("stake():", callCount[this.stake.selector]);
        console.log("unstake():", callCount[this.unstake.selector]);
        console.log("harvest():", callCount[this.harvest.selector]);
        console.log("addStakingReward():", callCount[this.addStakingReward.selector]);
        console.log("advanceTime():", callCount[this.advanceTime.selector]);
        console.log("advanceOneEpoch():", callCount[this.advanceOneEpoch.selector]);
        console.log("---");
        console.log("Ghost Total Staked:", ghost_totalStaked / 1e18, "DEXY");
        console.log("Ghost Total Rewards Added:", ghost_totalRewardsAdded / 1e18);
        console.log("Ghost Total Rewards Harvested:", ghost_totalRewardsHarvested / 1e18);
        console.log("============================\n");
    }
}
