// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine_HealthFactorNotImproved();
    error DSCEngine__CollateralValueTankedBelowAmountOfDscMinted();

    using OracleLib for AggregatorV3Interface;

    event DepositCollateral(
        address indexed user, address indexed tokenCollateraladdress, uint256 indexed amountColletral
    );
    event collateralRedeemed(
        address indexed reedemedFrom,
        address indexed reedemedTo,
        address indexed tokenCollateraladdress,
        uint256 amountCollateral
    );

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address s_priceFeeds) private s_priceFeeds;
    mapping(address user => mapping(address tokenCollateraladdress => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscToMint) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isTokenAllowed(address tokenCollateraladdress) {
        if (s_priceFeeds[tokenCollateraladdress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /**
     * These price feed will be on different addresses and different chains
     * we will be using it different arrays
     *
     */
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateraladdress,
        uint256 amountColletral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateraladdress, amountColletral);
        mintDsc(amountDscToMint);
    }

    function redeemCollateralAndBurnDsc(
        address tokenCollateraladdress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateraladdress, amountCollateral);
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     * To liquidate someone you have to buy dsc first and then burn it will be burned
     */
    function liquidate(address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 remainingDebt = debtToCover;

        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address tokenAddress = s_collateralTokens[i];
            uint256 amountCollateral = s_collateralDeposited[msg.sender][tokenAddress];
            if (amountCollateral > 0 && remainingDebt > 0) {
                //we have got the amount of tokenn we require to clear off debt
                uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(s_collateralTokens[i], remainingDebt);
                uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
                //Checking if bad user pay of it's debt and bonnus from current collateral
                if (amountCollateral >= (tokenAmountFromDebtCovered + bonusCollateral)) {
                    _redeemCollateral(tokenAddress, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
                    break;
                } else {
                    // take out as much as collateral bad user have and then move to next collateral
                    _redeemCollateral(tokenAddress, amountCollateral, user, msg.sender);
                    //calculate remaining amount of collateral to be taken from next collateral
                    remainingDebt = remainingDebt - getUsdValue(tokenAddress, amountCollateral);
                }
            }
        }

        //remaining debt is not zero that means whole debt of user is not being covered because of less collateral
        if (remainingDebt > 0) {
            revert DSCEngine__CollateralValueTankedBelowAmountOfDscMinted();
        }
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        //uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Burn DSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        //_redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine_HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //follows CEI mode --> checks effect and interactions
    function depositCollateral(address tokenCollateraladdress, uint256 amountColletral)
        public
        moreThanZero(amountColletral)
        isTokenAllowed(tokenCollateraladdress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateraladdress] += amountColletral;
        emit DepositCollateral(msg.sender, tokenCollateraladdress, amountColletral);
        //to wrap our collateral as erc 20 we using IERC20
        bool success = IERC20(tokenCollateraladdress).transferFrom(msg.sender, address(this), amountColletral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //Likely this will never get reverted
    }

    //if we try to reedeem collateral without burning DSC
    //then it will give that health factor is broken
    function redeemCollateral(address tokenCollateraladdress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateraladdress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        view
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    //User can decide how much dsc they want to mint
    //200ETH -> only 3 DSC they can opt to mint
    /*
     * @param amountDscToMint: The amount of DSC you want to mint
     * You can only mint DSC if you have enough collateral
     */

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        //check if they have minted too much DSC token than their collateral
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        console.log("DSC minted for user ", i_dsc.balanceOf(msg.sender));
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function getTokenAmountFromUsd(address collateral, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateral]);
        //(, int256 price,,,) = priceFeed.latestRoundData();
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        //return (usdAmountInWei * PRECISION) / uint256(price);
        //console.logUint((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccoutInfo(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        return _getAccoutInfo(user);
    }

    function _getAccoutInfo(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValue(user);
    }

    //Returns how close a user is against liquidation
    //If a user is below 1, they can get liquidated
    //https://www.youtube.com/watch?v=wUjYK5gwNZs&t=6029s
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccoutInfo(user);
        console.log(
            "totalDscMinted %s and totalCollateralValueInUsd %s", totalDscMinted, (totalCollateralValueInUsd / 1e18)
        );
        return _calculateHealthFactor(totalDscMinted, totalCollateralValueInUsd);
    }

    //check if they have enough collateral
    //Revert if they don't
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        console.log("user health factor ", userHealthFactor);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalUsdValue) {
        uint256 totalCollateralValueInUsd = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        totalUsdValue = totalCollateralValueInUsd;
    }

    //https://youtu.be/wUjYK5gwNZs?t=5861
    //pirce feed returms data in 8 decimal places
    //usually eth is calculated in 18 decimal places so it's referred as 1e18
    // hence we are multiplying by 10 so it become 1e18 and returning in 1e18
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        //(, int256 price,,,) = priceFeed.latestRoundData();
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        //console.logUint(uint256(price));

        // let 1 eth = 1000$
        // returned value from price feed = 1000 * 1e8; (1e8 = 8 decimal places)
        //let amount = 1 so in wei so it will be in 1* 1e18
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; //((1000 * 1e8 * 1e10) * 1000*1e18)/1e18;
    }

    function _redeemCollateral(address tokenCollateraladdress, uint256 amountCollateral, address from, address to)
        private
        moreThanZero(amountCollateral)
    {
        //if they pull out token what they have deposited then solidity compiler will revert
        // it automatically
        //In newer version of solidity unsafe math isn't permitted for uint256
        // for int we can have negative value
        s_collateralDeposited[from][tokenCollateraladdress] -= amountCollateral;
        emit collateralRedeemed(from, to, tokenCollateraladdress, amountCollateral);
        //transferFrom is used when user is sending trx to us
        //transfer is used when we send erc to user
        //using trnasfer here instead of transferFrom because in deposit collateral we are taking token from user
        bool success = IERC20(tokenCollateraladdress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        // _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        view
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        console.log("collateralAdjustedForThreshold %s", collateralAdjustedForThreshold / 1e18);
        return (collateralAdjustedForThreshold * PRECISION) / (totalDscMinted);
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom)
        private
        moreThanZero(amountDscToBurn)
        nonReentrant
    {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        //TODO: check this function from here. We are not asigning liquidator address a DSC token anywhere then how we can burn it??
        //TODO : why where transferring DSC token from liquidator since liquidator hasn't minted any DSC token.abi
        //If liquidator has dsc token and we burn his token wouldn't be he will be at lo
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
        // _revertIfHealthFactorIsBroken(msg.sender); //Likely this will never get reverted
    }

    function getCollateralAmountFromUser(address user, address tokenCollateraladdress) public view returns (uint256) {
        return s_collateralDeposited[user][tokenCollateraladdress];
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getPriceFeed(address collateral) public view returns (address) {
        return s_priceFeeds[collateral];
    }
}
