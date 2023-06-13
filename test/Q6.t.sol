// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {MyErc20} from "../src/MyErc20.sol";
import {CErc20} from "compound-protocol/contracts/CErc20.sol";
import {CErc20Delegator} from "compound-protocol/contracts/CErc20Delegator.sol";
import {WhitePaperInterestRateModel} from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {CErc20Delegate} from "compound-protocol/contracts/CErc20Delegate.sol";

import {Comptroller} from "compound-protocol/contracts/Comptroller.sol";
import {Unitroller} from "compound-protocol/contracts/Unitroller.sol";
import {SimplePriceOracle} from "compound-protocol/contracts/SimplePriceOracle.sol";
import {CToken} from "compound-protocol/contracts/CToken.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

contract Q6Test is Test {
    uint256 mainnetFork;
    uint256 sepoliaFork;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");

    uint256 initialBalance = 100 * 10 ** 18;

    address public admin;
    address public user1;
    address public user2;

    MyErc20 tokenA;
    Comptroller comptroller;
    SimplePriceOracle priceOracle;
    Unitroller unitroller;
    Comptroller unitrollerProxy;
    WhitePaperInterestRateModel interestRateModelA;
    CErc20Delegate cErc20DelegateA;
    CErc20Delegator cTokenA;

    MyErc20 tokenB;
    WhitePaperInterestRateModel interestRateModelB;
    CErc20Delegate cErc20DelegateB;
    CErc20Delegator cTokenB;

    /*
    Q6:  請使用 Foundry 的 fork 模式撰寫測試，並使用 AAVE 的 Flash loan 來清算 User1，請遵循以下細節：
    # Fork Ethereum mainnet at block 15815693 (Reference)
    # cERC20 的 decimals 皆為 18，初始 exchangeRate 為 1:1
    # Close factor 設定為 50%
    # Liquidation incentive 設為 8% (1.08 * 1e18)
    # 使用 USDC 以及 UNI 代幣來作為 token A 以及 Token B
    # 在 Oracle 中設定 USDC 的價格為 $1，UNI 的價格為 $10
    # 設定 UNI 的 collateral factor 為 50%
    # User1 使用 1000 顆 UNI 作為抵押品借出 5000 顆 USDC
    # 將 UNI 價格改為 $6.2 使 User1 產生 Shortfall，並讓 User2 透過 AAVE 的 Flash loan 來借錢清算 User1
    # 可以自行檢查清算 50% 後是不是大約可以賺 121 USD（Liquidation incentive = 8%）
    # 在合約中如需將 UNI 換成 USDC 可以使用以下程式碼片段：
    */

    /*
        進階題:

        1. 使用一套治理框架（例如 Governor Bravo 加上 Timelock）完成 Comptroller 中的設置
        2. 賞析 UniswapAnchoredView 合約並使用其作為 Comptroller 中設置的 oracle 來實現清算
        3. 設計一個能透過 Flash loan 清算多種代幣類型的智能合約
        4. 研究 Aave 協議，比較這些借貸協議在功能上與合約開發上的差異
    */

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        sepoliaFork = vm.createFork(SEPOLIA_RPC_URL);

        vm.selectFork(mainnetFork);
        vm.rollFork(15_815_693);
        assertEq(vm.activeFork(), mainnetFork);
        assertEq(block.number, 15_815_693);

        admin = makeAddr("Admin");
        user1 = makeAddr("User1");
        user2 = makeAddr("User2");

        vm.label(address(admin), "Admin");
        vm.label(address(user1), "User1");
        vm.label(address(user2), "User2");

        deal(admin, initialBalance);
        deal(user1, initialBalance);
        deal(user2, initialBalance);

        vm.startPrank(admin);

        // Erc20 token
        tokenA = new MyErc20("USDC", "USDC", 18);

        // Unitroller & Comptroller
        unitroller = new Unitroller();
        comptroller = new Comptroller();
        unitrollerProxy = Comptroller(address(comptroller));

        // Set Comptroller for Unitroller's implement contract
        unitroller._setPendingImplementation(address(comptroller));

        // Comptroller call _become will result in unitroller._acceptImplementation()
        // unitroller._acceptImplementation() can only called by pendingImplement contract
        comptroller._become(unitroller);

        priceOracle = new SimplePriceOracle();
        comptroller._setPriceOracle(priceOracle);
        comptroller._setCloseFactor(5e17); // 50%
        comptroller._setLiquidationIncentive(108e16); // 110%
        interestRateModelA = new WhitePaperInterestRateModel(0, 0);
        cErc20DelegateA = new CErc20Delegate();

        cTokenA = new CErc20Delegator(
            address(tokenA),
            comptroller,
            interestRateModelA,
            1e18,
            "cUSDC",
            "cUSDC",
            18,
            payable(msg.sender),
            address(cErc20DelegateA),
            "0x0"
        );

        uint setSupportA = comptroller._supportMarket(CToken(address(cTokenA)));
        require(setSupportA == 0, "set support A market failed");

        // Set token Price before set collateralFactor
        priceOracle.setUnderlyingPrice(CToken(address(cTokenA)), 1e18);

        uint setCollateralFactorA = comptroller._setCollateralFactor(
            CToken(address(cTokenA)),
            5e16
        );
        require(
            setCollateralFactorA == 0,
            "set CollateralFactor A factor failed"
        );

        // Token B
        tokenB = new MyErc20("UNI", "UNI", 18);
        interestRateModelB = new WhitePaperInterestRateModel(0, 0);
        cErc20DelegateB = new CErc20Delegate();

        cTokenB = new CErc20Delegator(
            address(tokenB),
            comptroller,
            interestRateModelB,
            1e18,
            "cUNI",
            "cUNI",
            18,
            payable(msg.sender),
            address(cErc20DelegateB),
            "0x0"
        );

        uint setSupportB = comptroller._supportMarket(CToken(address(cTokenB)));
        require(setSupportB == 0, "set support B marker failed");

        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 10 * 10 ** 18);

        uint setCollateralFactorB = comptroller._setCollateralFactor(
            CToken(address(cTokenB)),
            5e17
        );
        require(
            setCollateralFactorB == 0,
            "set CollateralFactor B factor failed"
        );

        vm.stopPrank();

        deal(user1, 100 * 10 ** 18);
        deal(user2, 100 * 10 ** 18);

        vm.label(address(tokenA), "USDC");
        vm.label(address(cTokenA), "cUSDC");
        vm.label(address(tokenB), "UNI");
        vm.label(address(cTokenB), "cUNI");
    }

    function test_AAVE_liquidate() public {
        uint user1TokenBInitialAmount = 1000 * 10 ** 18;
        deal(address(tokenB), user1, user1TokenBInitialAmount);
        deal(address(tokenA), address(cTokenA), 5000000 * 10 ** 18);

        console.log("-----------START test_borrow-----------");
        vm.startPrank(user1);
        _summaryUser("User 1 before mint", user1);

        tokenB.approve(address(cTokenB), user1TokenBInitialAmount);
        cTokenB.mint(user1TokenBInitialAmount);
        _summaryUser("User 1 after mint", user1);

        // Enter to market for collateral
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(cTokenB);
        // cTokens[1] = address(cTokenB);
        unitrollerProxy.enterMarkets(cTokens);

        _summaryAccountLiquidity("Above Liquidity line");

        cTokenA.borrow(5000 * 10 ** 18);
        _summaryUser("User 1 after borrow", user1);
        _summaryAccountLiquidity("after borrow");

        vm.stopPrank();
    }

    function _summaryUser(string memory condiction, address addr) internal {
        uint tokenAAmount = tokenA.balanceOf(addr);
        uint ctokenAAmount = cTokenA.balanceOf(addr);
        uint tokenBAmount = tokenB.balanceOf(addr);
        uint ctokenBAmount = cTokenB.balanceOf(addr);

        console.log(condiction);
        console.log("tokenA amount:", tokenAAmount);
        console.log("cTokenA amount:", ctokenAAmount);
        console.log("tokenB amount:", tokenBAmount);
        console.log("cTokenB amount:", ctokenBAmount);
        console.log("------------------------------");
    }

    function _summaryAccountLiquidity(string memory description) internal {
        console.log("###############");
        console.log(description);

        (uint errorCode, uint liquidity, uint shortfall) = comptroller
            .getAccountLiquidity(user1);

        console.log("User 1 liquidity:", liquidity, "shortfall:", shortfall);

        (uint errorCode2, uint liquidity2, uint shortfall2) = comptroller
            .getAccountLiquidity(user2);

        console.log("User 2 liquidity:", liquidity2, "shortfall:", shortfall2);
        console.log("###############");
    }
}
