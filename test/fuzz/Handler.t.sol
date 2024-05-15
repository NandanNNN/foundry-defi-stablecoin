// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc;
    uint256 public counter = 0;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator wethUsdPriceFeed;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;
        address[] memory collateralToken = dsce.getCollateralTokens();
        weth = collateralToken[0];
        wbtc = collateralToken[1];
        wethUsdPriceFeed = MockV3Aggregator(dsce.getPriceFeed(weth));
    }

    function depositCollateral(uint256 seed, uint256 amount) public {
        address collateral = _getCollateralFromSeed(seed);
        vm.startPrank(msg.sender);
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock(collateral).mint(msg.sender, amount);
        ERC20Mock(collateral).approve(address(dsce), amount);
        //console.log("total supply of collateral ", ERC20Mock(collateral).totalSupply());
        dsce.depositCollateral(collateral, amount);
        usersWithCollateralDeposited.push(msg.sender);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 seed, uint256 amount) public {
        address collateral = _getCollateralFromSeed(seed);
        vm.startPrank(msg.sender);
        uint256 amountCollateralToRedeem = dsce.getCollateralAmountFromUser(msg.sender, collateral);
        amount = bound(amount, 0, amountCollateralToRedeem);
        if (amount == 0) {
            vm.stopPrank();
            return;
        }
        dsce.redeemCollateral(collateral, amount);
        vm.stopPrank();
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        //amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        vm.startPrank(sender);
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dsce.getAccoutInfo(sender);
        int256 maxDscToMint = int256(totalCollateralValueInUsd) / 2 - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            vm.stopPrank();
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            vm.stopPrank();
            return;
        }
        dsce.mintDsc(amount);
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 seed) public view returns (address) {
        if (seed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    /**
     * function updateCollateral(uint96 price) public {
     *     int256 newPrice = int256(uint256(price));
     *     wethUsdPriceFeed.updateAnswer(newPrice);
     *     counter++;
     * }
     */
}
