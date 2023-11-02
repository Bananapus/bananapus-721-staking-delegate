// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/JB721StakingDelegateDeployer.sol";
import "../src/JB721StakingDelegate.sol";
import {WETH} from "lib/solady/src/tokens/WETH.sol";

// TEMP copied from Tentacles repo
struct TentacleCreateData {
    uint8 id;
    address helper;
}

contract BananapusPayScript is Script {
    IJBPayoutRedemptionPaymentTerminal3_1_1 stakingTerminal =
        IJBPayoutRedemptionPaymentTerminal3_1_1(0x2a402Ba7E72Ddf3CfFDfacE834fc1Dad548710c0); // 0x2a402Ba7E72Ddf3CfFDfacE834fc1Dad548710c0
    WETH stakingToken = WETH(payable(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6)); // WETH on Goerli

    function setUp() public {}

    function run() public {
        uint128 _cost = 1 gwei;

        JB721StakingTier[] memory _tiers = new JB721StakingTier[](1);
        _tiers[0] = JB721StakingTier({tierId: 0, amount: _cost});

        IBPLockManager _lockManager = IBPLockManager(0x79d58bc13Aa1c8CD303D056709EbBC31d7A48Fa7);
        TentacleCreateData[] memory _tentacleData = new TentacleCreateData[](2);
        _tentacleData[0] = TentacleCreateData({
            id: 1,
            helper: address(0) // OptimisticTentacleHelper
        });

        _tentacleData[1] = TentacleCreateData({
            id: 2,
            helper: address(0) // BASE OptimisticTentacleHelper
        });

        vm.startBroadcast();

        // Approve for the payment
        stakingToken.deposit{value: _cost}();
        stakingToken.approve(address(stakingTerminal), _cost);

        // Build the data
        bytes memory _metadata = abi.encode(
            bytes32(0),
            bytes32(0),
            type(IJB721StakingDelegate).interfaceId,
            false,
            tx.origin,
            _tiers,
            _lockManager,
            abi.encode(_tentacleData)
        );

        // Perform the mint
        stakingTerminal.pay(1212, _cost, address(stakingToken), tx.origin, 0, false, string(""), _metadata);
    }
}
