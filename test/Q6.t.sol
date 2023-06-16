// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {MyErc20} from "../src/MyErc20.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {CErc20} from "compound-protocol/contracts/CErc20.sol";
import {CErc20Delegator} from "compound-protocol/contracts/CErc20Delegator.sol";
import {WhitePaperInterestRateModel} from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {CErc20Delegate} from "compound-protocol/contracts/CErc20Delegate.sol";
import {Comptroller} from "compound-protocol/contracts/Comptroller.sol";
import {Unitroller} from "compound-protocol/contracts/Unitroller.sol";
import {SimplePriceOracle} from "compound-protocol/contracts/SimplePriceOracle.sol";
import {CToken} from "compound-protocol/contracts/CToken.sol";
import {AaveFlashLoan} from "../src/AaveFlashLoan.sol";

contract Q6Test is Test {
    uint256 mainnetFork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    address USDC_Addr = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address UNI_Addr = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    address constant POOL_ADDRESSES_PROVIDER =
        0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    uint blockNumber = 17465000;

    uint256 initialBalance = 100 * 10 ** 18;

    address public admin;
    address public user1;
    address public user2;

    ERC20 tokenA;
    Comptroller comptroller;
    SimplePriceOracle priceOracle;
    Unitroller unitroller;
    Comptroller unitrollerProxy;
    WhitePaperInterestRateModel interestRateModelA;
    CErc20Delegate cErc20DelegateA;
    CErc20Delegator cTokenA;

    ERC20 tokenB;
    WhitePaperInterestRateModel interestRateModelB;
    CErc20Delegate cErc20DelegateB;
    CErc20Delegator cTokenB;

    AaveFlashLoan public liquidator;

    /*
    Q6:  請使用 Foundry 的 fork 模式撰寫測試，並使用 AAVE 的 Flash loan 來清算 User1，請遵循以下細節：
    Fork Ethereum mainnet at block 17465000(Reference)
    cERC20 的 decimals 皆為 18，初始 exchangeRate 為 1:1
    Close factor 設定為 50%
    Liquidation incentive 設為 8% (1.08 * 1e18)
    使用 USDC 以及 UNI 代幣來作為 token A 以及 Token B
    USDC decimals = 6
    UNI decimals = 18

    在 Oracle 中設定 USDC 的價格為 $1，UNI 的價格為 $5
    設定 UNI 的 collateral factor 為 50%
    User1 使用 1000 顆 UNI 作為抵押品借出 2500 顆 USDC
    將 UNI 價格改為 $4 使 User1 產生 Shortfall，並讓 User2 透過 AAVE 的 Flash loan 來借錢清算 User1
    可以自行檢查清算 50% 後是不是大約可以賺 63 USDC
    */

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);

        vm.selectFork(mainnetFork);
        vm.rollFork(blockNumber);
        assertEq(vm.activeFork(), mainnetFork);
        assertEq(block.number, blockNumber);

        admin = makeAddr("Admin");
        user1 = makeAddr("User1");
        user2 = makeAddr("User2");

        vm.label(address(admin), "Admin");
        vm.label(address(user1), "User1");
        vm.label(address(user2), "User2");

        deal(admin, initialBalance);
        deal(user1, initialBalance);
        deal(user2, initialBalance);

        vm.makePersistent(user2);

        vm.startPrank(admin);

        // Erc20 token
        tokenA = ERC20(USDC_Addr);

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
        comptroller._setLiquidationIncentive(108e16); // 108%
        interestRateModelA = new WhitePaperInterestRateModel(0, 0);
        cErc20DelegateA = new CErc20Delegate();

        cTokenA = new CErc20Delegator(
            address(tokenA),
            comptroller,
            interestRateModelA,
            1e6,
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
        priceOracle.setUnderlyingPrice(CToken(address(cTokenA)), 1e30); //

        uint setCollateralFactorA = comptroller._setCollateralFactor(
            CToken(address(cTokenA)),
            5e17
        );
        require(
            setCollateralFactorA == 0,
            "set CollateralFactor A factor failed"
        );

        // Token B
        tokenB = ERC20(UNI_Addr);
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

        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 5 * 10 ** 18);

        uint setCollateralFactorB = comptroller._setCollateralFactor(
            CToken(address(cTokenB)),
            5e17
        );
        require(
            setCollateralFactorB == 0,
            "set CollateralFactor B factor failed"
        );

        vm.stopPrank();

        vm.label(address(tokenA), "USDC");
        vm.label(address(cTokenA), "cUSDC");
        vm.label(address(tokenB), "UNI");
        vm.label(address(cTokenB), "cUNI");

        liquidator = new AaveFlashLoan(
            payable(address(cTokenA)),
            payable(address(cTokenB))
        );
    }

    function test_AAVE_liquidate() public {
        uint user1TokenBInitialAmount = 1000 * 10 ** tokenB.decimals();
        deal(address(tokenB), user1, user1TokenBInitialAmount);
        deal(
            address(tokenA),
            address(cTokenA),
            100000000 * 10 ** cTokenA.decimals()
        );

        console.log("-----------START Mint cTokenB -----------");
        vm.startPrank(user1);
        _summaryUser("User 1 before mint", user1);

        tokenB.approve(address(cTokenB), user1TokenBInitialAmount);
        cTokenB.mint(user1TokenBInitialAmount);
        _summaryUser("User 1 after mint", user1);

        // Enter to market for collateral
        address[] memory cTokens = new address[](1);
        cTokens[0] = address(cTokenB);
        unitrollerProxy.enterMarkets(cTokens);

        _summaryAccountLiquidity("Did not meet liquidation condition");

        console.log("-----------START Borrow tokenA -----------");
        cTokenA.borrow(2500 * 10 ** tokenA.decimals());
        _summaryUser("User 1 after borrow", user1);
        _summaryAccountLiquidity("after borrow");

        vm.stopPrank();

        console.log(
            "----Change tokenB price to meet liquidation condition-----"
        );
        vm.startPrank(admin);
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 4e18);
        _summaryAccountLiquidity(
            "Under Liquidity line, because tokenB price changed."
        );
        vm.stopPrank();

        console.log("-----------START Borrow tokenA from AAve -----------");

        vm.prank(user2);
        liquidator.execute(user1, 1250 * 10 ** 6);

        console.log("-----------RESULT-----------");
        _summaryUser("User 1 Final", user1);
        _summaryUser("User 2 Final", user2);
        _summaryUser("TEST CONTRACT Final", address(this));
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
