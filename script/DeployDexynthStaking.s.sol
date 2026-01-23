// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DexynthStakingV2_1} from "../src/DexynthStaking.sol";

contract DeployDexynthStaking is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address dexy = vm.envAddress("DEXY_ADDRESS");
        address rewardToken = vm.envAddress("USDT_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);

        DexynthStakingV2_1.Level[] memory levels = new DexynthStakingV2_1.Level[](5);
        // Level(lockingPeriod, boostP, totalStaked)
        levels[0] = DexynthStakingV2_1.Level(2592000, 6500000000, 0);
        levels[1] = DexynthStakingV2_1.Level(7776000, 8500000000, 0);
        levels[2] = DexynthStakingV2_1.Level(15552000, 10000000000, 0);
        levels[3] = DexynthStakingV2_1.Level(31536000, 11500000000, 0);
        levels[4] = DexynthStakingV2_1.Level(62208000, 13500000000, 0);

        uint256 epochDuration = 1296000; // 15 days

        new DexynthStakingV2_1(dexy, rewardToken, levels, epochDuration);

        vm.stopBroadcast();
    }
}
