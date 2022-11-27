// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {ISuperfluid, ISuperToken} from "protocol-monorepo/packages/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

interface ITapWizard {
    event ImplementationChanged(
        address oldImplementation,
        address newImplementation
    );
    event TapCreated(
        string name,
        address creator,
        address indexed tap,
        address indexed nft,
        address indexed superToken
    );

    error ZeroAddress();
    error SameImplementationAddress();
    error TapExists(string name);
    error TransferFailed(address superToken, uint256 amount);

    /**
     * @notice This function creates a tap for a creator to distribute a particular supertoken.
     * @param name Name of the tap. Useful if creating multiple taps with the same supertoken, creator and NFT address.
     * @param nft The NFT address for which a tap is being created.
     * @param ratePerNFT Stream rate for the super token distribution.
     * @param superToken The super token to be distributed by the tap.
     * @return newTap Address of the newly created tap contract.
     */
    function createTap(
        string memory name,
        uint96 ratePerNFT,
        IERC721 nft,
        ISuperToken superToken
    ) external returns (address newTap);

    function Taps(string memory name) external returns(address tap);
}
