// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {ISuperfluid, ISuperToken} from "protocol-monorepo/packages/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IcfaV1Forwarder} from "./IcfaV1Forwarder.sol";

interface ITap {
    // NOTE: Is there a requirement for a `dirty` variable to indicate that
    // all the claimed streams of a receiver were cancelled because of `emergencyCloseStreams`
    // or the holders themselves closing all the streams forcefully?
    struct ClaimedData {
        int96 claimedRate;
        uint256 numStreams;
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
    event StreamsAdjusted(address indexed holder, int96 oldRatePerNFT, int96 newRatePerNFT);
    event StreamsReinstated(address indexed holder, int96 numStreams, int96 newOutStreamRate, int96 ratePerNFT);
    event EmergencyCloseInitiated(address indexed holder);
    event TapDrained(
        address indexed streamToken,
        uint256 drainAmount
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
    error SameClaimRate(int96 ratePerNFT);
    error NotOwnerOfNFT(uint256 tokenId);
    error StreamAlreadyClaimed(uint256 tokenId);
    error StreamNotFound(uint256 tokenId);
    error HolderStreamsNotFound(address holder);
    error WrongStreamCloseAttempt(uint256 tokenId, address terminator);
    error StreamsAdjustmentsFailed(address prevHolder, address currHolder);
    error StreamAdjustmentFailedInReinstate(address prevHolder);
    error StreamsAlreadyReinstated(address prevHolder);
    error NoEmergency(
        address terminator
    );
    error TapMinAmountLimit(uint256 remainingAmount, uint256 minAmountRequried);
    error TapBalanceInsufficient(uint256 currTapBalance, uint256 reqTapBalance);
    
    function tokenIdHolders(uint256 tokenId) external returns(address holder);
    function initialize(
        string memory name,
        address host,
        address creator,
        uint96 ratePerNFT,
        IcfaV1Forwarder cfaV1Forwarder,
        IERC721 nft,
        ISuperToken streamToken
    ) external;

    function claimStream(uint256 tokenId) external;
    function reinstateStreams(address prevHolder) external;
    function topUpTap(uint256 amount) external;
    function drainTap(uint256 amount) external;
    function closeStream(uint256 tokenId) external;
    function emergencyCloseStreams(address holder) external;
    function adjustCurrentStreams(address holder) external;
    function changeRate(uint96 newRatePerNFT) external;
    function activateTap() external;
    function deactivateTap() external;
    function isCritical() external view returns (bool status);
}
