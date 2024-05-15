//have our invarints aka properties that should always holds true

//invariants in our systems fto test for the time being
// 1. total DSC minted sould be less than collateral
//2. getter view function should never revert

// SPDX-License-Identifier: MIT
/**
 * pragma solidity ^0.8.20;
 * 
 * import {Test, console} from "forge-std/Test.sol";
 * import {StdInvariant} from "forge-std/StdInvariant.sol";
 * import {DeployDsc} from "../../script/DeployDsc.s.sol";
 * import {HelperConfig} from "../../script/HelperConfig.s.sol";
 * import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
 * import {DSCEngine} from "../../src/DSCEngine.sol";
 * import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
 * 
 * contract OpenInvariantTest is StdInvariant, Test {
 *     DeployDsc deployDsc;
 *     HelperConfig helperConfig;
 *     DecentralizedStableCoin dsc;
 *     DSCEngine dscEngine;
 *     address weth;
 *     address wbtc;
 * 
 *     function setUp() public {
 *         deployDsc = new DeployDsc();
 *         (dsc, dscEngine, helperConfig) = deployDsc.run();
 *         (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
 *         targetContract(address(dscEngine));
 *     }
 * 
 *     function invariant_MustHaveMoreValueThanTotalSupply() public view {
 *         uint256 totalSupply = dsc.totalSupply();
 *         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
 *         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
 *         uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
 *         uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);
 * 
 *         console.log("weth value ", wethValue);
 *         console.log("dsc value ", totalSupply);
 *         assert(wethValue + wbtcValue >= totalSupply);
 *     }
 * }
 */
