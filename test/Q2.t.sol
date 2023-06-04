// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../script/Q1.s.sol";

contract Q2Test is Test, Q1Script {
    uint256 initialBalance = 100 * 10 ** 18;
    address admin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public override {
        super.setUp();
        super.run();
        console.log(address(qqq));
        console.log(address(cErc20Delegator));

        deal(address(qqq), alice, initialBalance);
        deal(alice, 100 * 10 ** 18);
        vm.label(address(qqq), "QQQ");
        vm.label(address(cErc20Delegator), "cQQQ");
    }

    function test_MintRedeem() public {
        vm.startPrank(alice);
        uint qqqBalanceBeforeMint = qqq.balanceOf(alice);
        uint cqqqBalanceBeforeMint = cErc20Delegator.balanceOf(alice);
        console.log("QQQ balance before mint:", qqqBalanceBeforeMint);
        console.log("cQQQ balance before mint:", cqqqBalanceBeforeMint);

        qqq.approve(address(cErc20Delegator), initialBalance);
        cErc20Delegator.mint(initialBalance);

        uint qqqBalanceAfterMint = qqq.balanceOf(alice);
        uint cqqqBalanceAfterMint = cErc20Delegator.balanceOf(alice);
        console.log("QQQ balance after mint:", qqqBalanceAfterMint);
        console.log("cQQQ balance after mint:", cqqqBalanceAfterMint);

        // assertEq(cqqqBalanceAfterMint, initialBalance);

        // cErc20Delegator.redeem(cqqqBalanceAfterMint);

        uint qqqBalanceAfterRedeem = qqq.balanceOf(alice);
        uint cqqqBalanceAfterRedeem = cErc20Delegator.balanceOf(alice);
        console.log("QQQ balance after redeem:", qqqBalanceAfterRedeem);
        console.log("cQQQ balance after redeem:", cqqqBalanceAfterRedeem);

        vm.stopPrank();
    }
}
