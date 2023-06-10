// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {MyErc20} from "../src/MyErc20.sol";
import {CErc20} from "compound-protocol/contracts/CErc20.sol";
import {CErc20Delegator} from "compound-protocol/contracts/CErc20Delegator.sol";
import {WhitePaperInterestRateModel} from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {CErc20Delegate} from "compound-protocol/contracts/CErc20Delegate.sol";

import {Comptroller} from "compound-protocol/contracts/Comptroller.sol";
import {Unitroller} from "compound-protocol/contracts/Unitroller.sol";
import {SimplePriceOracle} from "compound-protocol/contracts/SimplePriceOracle.sol";
import {CToken} from "compound-protocol/contracts/CToken.sol";

contract Q1Script is Script {
    address public alice;
    address public bob;

    MyErc20 qqq;
    Comptroller comptroller;
    SimplePriceOracle priceOracle;
    Unitroller unitroller;
    Comptroller unitrollerProxy;
    WhitePaperInterestRateModel interestRateModel;
    CErc20Delegate cErc20Delegate;
    CErc20Delegator cErc20Delegator;

    function setUp() public virtual {
        alice = makeAddr("Alice");
        bob = makeAddr("Bob");

        vm.label(address(alice), "Alice");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.envAddress("TEST_ACCOUNT_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        qqq = new MyErc20("TripleQ", "QQQ", 18);

        comptroller = new Comptroller();

        unitroller = new Unitroller();
        unitrollerProxy = Comptroller(address(comptroller));
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        priceOracle = new SimplePriceOracle();

        unitrollerProxy._setPriceOracle(priceOracle);
        unitrollerProxy._setCloseFactor(5e16);
        unitrollerProxy._setLiquidationIncentive(108e16);

        interestRateModel = new WhitePaperInterestRateModel(0, 0);
        cErc20Delegate = new CErc20Delegate();

        cErc20Delegator = new CErc20Delegator(
            address(qqq),
            comptroller,
            interestRateModel,
            1e18, // uint initialExchangeRateMantissa_,  1:1   1e18
            "TripleQPool",
            "cQQQ",
            18,
            payable(msg.sender),
            address(cErc20Delegate),
            "0x0" // bytes memory becomeImplementationData
        );

        uint setSupport = unitrollerProxy._supportMarket(cErc20Delegate);
        require(setSupport == 0, "support marker error");

        vm.stopBroadcast();
    }
}
