// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * Modified IERC20 interface.
 * @dev This interface is used to access decimals of an ERC20 token.
 */
interface IERC20Mod is IERC20 {
    function decimals() external view returns (uint8);
}