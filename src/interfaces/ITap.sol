// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {ISuperfluid, ISuperToken} from "protocol-monorepo/packages/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IcfaV1Forwarder} from "./IcfaV1Forwarder.sol";

interface ITap {
    // TODO: Explore bitpacking as a solution using int104 or uint96.
    struct ClaimedData {
        int96 claimedRate;
        // TokenId => claimed/unclaimed
        mapping(uint256 => bool) isClaimedId;
    }

    event TapCreated(
        string name,
        address creator,
        address indexed nft,
        address indexed superToken,
        uint96 ratePerNFT
    );
    event TapActivated();
    event TapDeactivated();
    event TapRateChanged(int96 oldRatePerNFT, int96 newRatePerNFT);
    event TapToppedUp(address indexed superToken, uint256 amount);
    event StreamsClaimed(
        address indexed claimant,
        int96 oldStreamRate,
        int96 newStreamRate
    );
    event StreamClaimedById(address indexed claimant, uint256 tokenId);
    event EmergencyCloseInitiated(address indexed holder);
    event TapDrained(
        address indexed streamToken,
        uint256 drainAmount,
        uint256 remainingAmount
    );

    error ZeroAddress();
    error TransferFailed();
    error BulkClaimsPaused();
    error TapExists();
    error TapNotFound();
    error TapActive();
    error TapInactive();
    error NotTapCreator();
    error IneligibleClaim();
    error NotHost(address terminator);
    error SameTapRate(int96 ratePerNFT);
    error NotOwnerOfNFT(uint256 tokenId);
    error StreamAlreadyClaimed(uint256 tokenId);
    error StreamNotFound(uint256 tokenId);
    error HolderStreamsNotFound(address holder);
    error WrongStreamCloseAttempt(uint256 tokenId, address terminator);
    error StreamsAdjustmentsFailed(address prevHolder, address currHolder);
    error NoEmergency(
        address terminator,
        address holder,
        uint256 currTapBalance,
        uint256 minReqTapBalance
    );
    error TapMinAmountLimit(uint256 remainingAmount, uint256 minAmountRequried);
    error TapBalanceInsufficient(uint256 currTapBalance, uint256 reqTapBalance);

    function initialize(
        string memory name,
        address host,
        address creator,
        uint96 ratePerNFT,
        IcfaV1Forwarder cfaV1Forwarder,
        IERC721 nft,
        ISuperToken streamToken
    ) external;

    function topUpTap(uint256 amount) external;
}
