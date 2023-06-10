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

contract Q2Test is Test {
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

    function setUp() public {
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
        tokenA = new MyErc20("TokenA", "AAA", 18);

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
        comptroller._setLiquidationIncentive(110e16); // 110%
        interestRateModelA = new WhitePaperInterestRateModel(0, 0);
        cErc20DelegateA = new CErc20Delegate();

        cTokenA = new CErc20Delegator(
            address(tokenA),
            comptroller,
            interestRateModelA,
            1e18,
            "cAAA",
            "cTokenA",
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
        tokenB = new MyErc20("TokenB", "BBB", 18);
        interestRateModelB = new WhitePaperInterestRateModel(0, 0);
        cErc20DelegateB = new CErc20Delegate();

        cTokenB = new CErc20Delegator(
            address(tokenB),
            comptroller,
            interestRateModelB,
            1e18,
            "cBBB",
            "cTokenB",
            18,
            payable(msg.sender),
            address(cErc20DelegateB),
            "0x0"
        );

        uint setSupportB = comptroller._supportMarket(CToken(address(cTokenB)));
        require(setSupportB == 0, "set support B marker failed");

        priceOracle.setUnderlyingPrice(
            CToken(address(cTokenB)),
            100 * 10 ** 18
        );

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

        vm.label(address(tokenA), "AAA");
        vm.label(address(cTokenA), "cAAA");
    }

    /*
Q2:

讓 User1 mint/redeem cERC20, 實現以下場景：
User1 使用 100 顆（100 * 10^18） ERC20 去 mint 出 100 cERC20 token，
再用 100 cERC20 token redeem 回 100 顆 ERC20

*/

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

    function test_MintRedeem() public {
        console.log("-----------Start test_MintRedeem-----------");
        deal(address(tokenA), user1, initialBalance);

        vm.startPrank(user1);
        _summaryUser("User 1 Before Mint", user1);

        // Approve before mint
        tokenA.approve(address(cTokenA), initialBalance);
        cTokenA.mint(initialBalance);
        _summaryUser("User 1 After Mint", user1);

        uint cTokenABalanceAfterMint = cTokenA.balanceOf(user1);
        assertEq(cTokenABalanceAfterMint, initialBalance);

        // Redeem
        cTokenA.redeem(cTokenABalanceAfterMint);
        _summaryUser("User 1 After Redeem", user1);
        uint tokenABalanceAfterRedeem = tokenA.balanceOf(user1);

        assertEq(tokenABalanceAfterRedeem, initialBalance);

        vm.stopPrank();
    }

    /*
    Q3:

    讓 User1 borrow/repay

    部署第二份 cERC20 合約，以下稱它們的 underlying tokens 為 token A 與 token B。
    在 Oracle 中設定一顆 token A 的價格為 $1，一顆 token B 的價格為 $100
    Token B 的 collateral factor 為 50%
    User1 使用 1 顆 token B 來 mint cToken
    User1 使用 token B 作為抵押品來借出 50 顆 token A

    */
    function test_borrow() public {
        uint user1TokenBInitialAmount = 1 * 10 ** 18;
        deal(address(tokenB), user1, user1TokenBInitialAmount);
        deal(address(tokenA), address(cTokenA), 1000 * 10 ** 18);

        console.log("-----------START test_borrow-----------");
        vm.startPrank(user1);
        _summaryUser("User 1 before mint", user1);

        tokenB.approve(address(cTokenB), initialBalance);
        cTokenB.mint(user1TokenBInitialAmount);
        _summaryUser("User 1 after mint", user1);

        // Enter to market for collateral
        address[] memory cTokens = new address[](2);
        cTokens[0] = address(cTokenA);
        cTokens[1] = address(cTokenB);
        unitrollerProxy.enterMarkets(cTokens);

        _summaryAccountLiquidity("Above Liquidity line");

        cTokenA.borrow(50 * 10 ** 18);
        _summaryUser("User 1 after borrow", user1);

        vm.stopPrank();
    }

    /*
    Q4:  延續 (3.) 的借貸場景，調整 token B 的 collateral factor，讓 User1 被 User2 清算
    */

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

    function test_liquidate_by_collateralFactor_changed() public {
        test_borrow();
        vm.startPrank(admin);
        uint setCollateralFactorB = comptroller._setCollateralFactor(
            CToken(address(cTokenB)),
            3e17
        );
        _summaryAccountLiquidity(
            "Under Liquidity line, coz collateral factor changed."
        );
        require(
            setCollateralFactorB == 0,
            "Reset tokenB CollateralFactor factor failed"
        );
        vm.stopPrank();

        uint initialAmount = 100 * 10 ** 18;
        deal(user2, initialAmount);
        deal(address(tokenA), user2, initialAmount);

        _summaryUser("User 1 before liquate", user1);
        _summaryUser("User 2 before liquate", user2);

        vm.startPrank(user2);

        // User2 repay borrow the borrowAmount * closeFactor of user1
        // Before repay, user2 should approve tokenA for cTokenA pool
        uint repayAmountMax = (cTokenA.borrowBalanceCurrent(user1) *
            comptroller.closeFactorMantissa()) / 1e18;
        tokenA.approve(address(cTokenA), repayAmountMax);

        uint resultLiquidate = cTokenA.liquidateBorrow(
            user1,
            repayAmountMax,
            CToken(address(cTokenB))
        );
        require(resultLiquidate == 0, "Liquidate fail");

        _summaryUser("User 1 after liquate", user1);
        _summaryUser("User 2 after liquate", user2);
        _summaryAccountLiquidity("After Liquidated");
        // User 1 still shortfall 3.25 tokenA
        // Can liquidate again

        vm.stopPrank();
    }

    /*
    Q5:  延續 (3.) 的借貸場景，調整 oracle 中 token B 的價格，讓 User1 被 User2 清算
    */
    function test_liquidate_by_price_changed() public {
        test_borrow();
        vm.startPrank(admin);
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 80e18);
        vm.stopPrank();
        _summaryAccountLiquidity(
            "Under Liquidity line, coz tokenB price changed."
        );

        uint initialAmount = 100 * 10 ** 18;
        deal(user2, initialAmount);
        deal(address(tokenA), user2, initialAmount);

        _summaryUser("User 1 before liquate", user1);
        _summaryUser("User 2 before liquate", user2);

        vm.startPrank(user2);

        // User2 repay borrow the borrowAmount * closeFactor of user1
        // Before repay, user2 should approve tokenA for cTokenA pool
        uint repayAmountMax = (cTokenA.borrowBalanceCurrent(user1) *
            comptroller.closeFactorMantissa()) / 1e18;
        tokenA.approve(address(cTokenA), repayAmountMax);

        uint resultLiquidate = cTokenA.liquidateBorrow(
            user1,
            repayAmountMax,
            CToken(address(cTokenB))
        );
        require(resultLiquidate == 0, "Liquidate fail");

        _summaryUser("User 1 after liquate", user1);
        _summaryUser("User 2 after liquate", user2);
        _summaryAccountLiquidity("After Liquidated");
        // User 1 still shortfall 3.25 tokenA
        // Can liquidate again

        vm.stopPrank();
    }

    /*
    Q6:  請使用 Foundry 的 fork 模式撰寫測試，並使用 AAVE 的 Flash loan 來清算 User1，請遵循以下細節：
    Fork Ethereum mainnet at block 15815693 (Reference)
    cERC20 的 decimals 皆為 18，初始 exchangeRate 為 1:1
    Close factor 設定為 50%
    Liquidation incentive 設為 8% (1.08 * 1e18)
    使用 USDC 以及 UNI 代幣來作為 token A 以及 Token B
    在 Oracle 中設定 USDC 的價格為 $1，UNI 的價格為 $10
    設定 UNI 的 collateral factor 為 50%
    User1 使用 1000 顆 UNI 作為抵押品借出 5000 顆 USDC
    將 UNI 價格改為 $6.2 使 User1 產生 Shortfall，並讓 User2 透過 AAVE 的 Flash loan 來借錢清算 User1
    可以自行檢查清算 50% 後是不是大約可以賺 121 USD（Liquidation incentive = 8%）
    在合約中如需將 UNI 換成 USDC 可以使用以下程式碼片段：
    */
}
