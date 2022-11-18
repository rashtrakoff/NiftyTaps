// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import {ISuperfluid, ISuperToken} from "protocol-monorepo/packages/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

interface ITapWizard {
    /**
        @dev A struct representing the details of a tap (super token streams).
        @param active Boolean for tap status.
        @param ratePerNFT Stream rate per super token to drip out for every NFT a holder has.
        @param balance Balance of the super token when a deposit was made.
        @param creator The creator of the tap.
        @param streamToken The token the tap wants to stream.
    */
    struct Tap {
        bool active;
        uint96 ratePerNFT;
        uint64 lastUpdateTime;
        address creator;
        address nft;
        uint256 balance;
        uint256 numStreams;
        string name;
        ISuperToken streamToken;
    }

    event TapCreated(
        string name,
        address creator,
        address indexed nft,
        address indexed superToken,
        bytes32 indexed id
    );
    event TapActivated(bytes32 indexed id);
    event TapDeactivated(bytes32 indexed id);
    event TapRateChanged(
        bytes32 indexed id,
        uint96 oldRatePerNFT,
        uint96 newRatePerNFT
    );
    event TapToppedUp(
        bytes32 indexed id,
        address indexed superToken,
        uint256 amount
    );
    event StreamsClaimed(
        bytes32 indexed id,
        address indexed claimant,
        int96 oldStreamRate,
        int96 newStreamRate
    );
    event StreamClaimedById(
        bytes32 indexed id,
        address indexed claimant,
        uint256 tokenId
    );
    event TapDrained(
        bytes32 indexed id,
        address indexed streamToken,
        uint256 drainAmount,
        uint256 remainingAmount
    );

    error ZeroAddress();
    error BulkClaimsPaused();
    error TapExists(bytes32 id);
    error TapNotFound(bytes32 id);
    error TapActive(bytes32 id);
    error TapInactive(bytes32 id);
    error NotTapCreator(bytes32 id);
    error SameTapRate(bytes32 id, uint96 ratePerNFT);
    error IneligibleClaim(bytes32 id);
    error NotOwnerOfNFT(bytes32 id, uint256 tokenId);
    error StreamAlreadyClaimed(bytes32 id, uint256 tokenId);
    error StreamNotFound(bytes32 id, uint256 tokenId);
    error WrongStreamCloseAttempt(bytes32 id, uint256 tokenId);
    error TapMinAmountLimit(
        bytes32 id,
        uint256 remainingAmount,
        uint256 minAmountRequried
    );
    error TapBalanceInsufficient(
        bytes32 id,
        uint256 currTapBalance,
        uint256 reqTapBalance
    );

    /**
     * @notice This function creates a tap for a creator to distribute a particular supertoken.
     * @param name Name of the tap. Useful if creating multiple taps with the same supertoken, creator and NFT address.
     * @param nft The NFT address for which a tap is being created.
     * @param ratePerNFT Stream rate for the super token distribution.
     * @param amount Amount of super token used to top-up the tap balance.
     * @param superToken The super token to be distributed by the tap.
     */
    function createTap(
        string memory name,
        address nft,
        uint96 ratePerNFT,
        uint256 amount,
        ISuperToken superToken
    ) external returns (bytes32 id);

    /**
     * @notice Gives the tap id for a particular name, NFT address and a creator address.
     * @dev Uses keccak256 and abi.encode on the arguments.
     * @param name Name of the tap. Has to be unique per creator and NFT.
     * @param nft Address of the NFT.
     * @param creator Tap creator's address.
     */
    function getTapId(
        string memory name,
        address nft,
        address creator
    ) external pure returns (bytes32 id);

    function activateTap(bytes32 id) external;

    function deactivateTap(bytes32 id) external;

    function changeRate(bytes32 id, uint96 newRatePerNFT) external;
}
