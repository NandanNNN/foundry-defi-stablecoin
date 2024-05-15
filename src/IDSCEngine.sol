// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    //deposit btc to get stable coin
    function depositCollateralAndMintDsc(address tokenCollateraladdress, uint256 amount) external;

    //get btc back by giving back dsc
    function redeemCollateralForDsc() external;

    function redeemCollateral() external;

    function depositCollateral(address tokenCollateraladdress, uint256 amountColletral) external;

    function burnDsc() external;

    function mintDsc() external;

    function liquidate() external;

    function getHealthFactor() external view;
}
