pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {CErc20} from "compound-protocol/contracts/CErc20.sol";
import {CErc20Delegator} from "compound-protocol/contracts/CErc20Delegator.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {CToken} from "compound-protocol/contracts/CToken.sol";

contract AaveFlashLoan is IFlashLoanSimpleReceiver {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    address constant POOL_ADDRESSES_PROVIDER =
        0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    IERC20 tokenA = IERC20(USDC);
    IERC20 tokenB = IERC20(UNI);

    CErc20Delegator cTokenA;
    CErc20Delegator cTokenB;

    address borrower;

    constructor(address payable cTokenA_addr, address payable cTokenB_addr) {
        cTokenA = CErc20Delegator(cTokenA_addr);
        cTokenB = CErc20Delegator(cTokenB_addr);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        uint256 usdcAmount = IERC20(USDC).balanceOf(address(this));
        console.log("USDC amount:", usdcAmount);

        tokenA.approve(address(cTokenA), usdcAmount);
        cTokenA.liquidateBorrow(borrower, usdcAmount, CToken(address(cTokenB)));

        //Redeem cUNI, get UNI
        cTokenB.redeem(cTokenB.balanceOf(address(this)));

        uint uniAmount = tokenB.balanceOf(address(this));
        console.log("UNI amount:", uniAmount);

        // Test Contract Swap UNI to USDC
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: UNI,
                tokenOut: USDC,
                fee: 3000, // 0.3%
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: uniAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        ISwapRouter swapRouter = ISwapRouter(
            0xE592427A0AEce92De3Edee1F18E0157C05861564
        );
        tokenB.approve(address(swapRouter), uniAmount);
        uint amountOut = swapRouter.exactInputSingle(swapParams);
        console.log("Uniswap back USDC amount", amountOut);

        return true;
    }

    function execute(address borrower_, uint liquidateAmount) external {
        borrower = borrower_;
        IPool pool = POOL();
        IERC20(USDC).approve(
            address(pool),
            liquidateAmount + ((liquidateAmount * 5) / 1e4)
        ); // 0.05 %

        pool.flashLoanSimple(address(this), USDC, liquidateAmount, "", 0);

        // Transfer all the rest USDC to User2
        tokenA.transfer(msg.sender, tokenA.balanceOf(address(this)));
    }

    function ADDRESSES_PROVIDER() public view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
    }

    function POOL() public view returns (IPool) {
        return IPool(ADDRESSES_PROVIDER().getPool());
    }
}
