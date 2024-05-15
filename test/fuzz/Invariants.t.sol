// SPDX-License-Identifier: MIT

//have our invarints aka properties that should always holds true

//invariants in our systems fto test for the time being
// 1. total DSC minted sould be less than collateral
//2. getter view function should never revert

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Invariants is StdInvariant, Test {
    DeployDsc deployDsc;
    HelperConfig helperConfig;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() public {
        deployDsc = new DeployDsc();
        (dsc, dscEngine, helperConfig) = deployDsc.run();
        (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_MustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value ", wethValue);
        console.log("dsc value ", totalSupply);
        console.log("total supply ", totalSupply);
        console.log("times updateCollateral called ", handler.counter());
        assert(wethValue + wbtcValue >= totalSupply);
    }
}
