// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {IcfaV1Forwarder, ISuperToken} from "./interfaces/IcfaV1Forwarder.sol";
import {IERC20Mod} from "./interfaces/IERC20Mod.sol";
import {ITapWizard} from "./interfaces/ITapWizard.sol";

contract TapWizard is ITapWizard {
    using SafeCast for *;
    using SafeERC20 for IERC20Mod;

    IcfaV1Forwarder internal immutable CFA_V1_FORWARDER;

    // Status flag to denote if claims without providing `tokenIds` are allowed.
    bool public pauseBulkClaims;

    mapping(bytes32 => Tap) private Taps;

    // NFT address => TokenId => Holder address.
    mapping(address => mapping(uint256 => address)) tokenIdHolders;

    constructor(IcfaV1Forwarder _cfaV1Forwarder, bool _pauseBulkClaims) {
        if (address(_cfaV1Forwarder) == address(0)) revert ZeroAddress();

        CFA_V1_FORWARDER = _cfaV1Forwarder;
        pauseBulkClaims = _pauseBulkClaims;
    }

    function createTap(
        string memory _name,
        address _nft,
        uint96 _ratePerNFT,
        uint256 _amount,
        ISuperToken _superToken
    ) external returns (bytes32 _id) {
        _id = getTapId(_name, _nft, msg.sender);

        // If a tap already exists, don't create a new one.
        if (Taps[_id].creator == msg.sender) revert TapExists(_id);

        if (_nft == address(0) || address(_superToken) == address(0))
            revert ZeroAddress();

        // Transferring super tokens from the creator to this contract.
        _superToken.transferFrom(msg.sender, address(this), _amount);

        // Creating new Tap with the given arguments.
        Tap memory newTap;

        newTap.active = true;
        newTap.ratePerNFT = _ratePerNFT;
        newTap.lastUpdateTime = (block.timestamp).toUint64();
        newTap.creator = msg.sender;
        newTap.nft = _nft;
        newTap.name = _name;
        newTap.streamToken = _superToken;
        newTap.balance = _amount;

        Taps[_id] = newTap;

        emit TapCreated(_name, msg.sender, _nft, address(_superToken), _id);
    }

    // TODO: It could be a better to call the `ownerOf` method by asking for the `tokenId` of the NFT from the claimant
    // against which he wishes to take out a stream. Reason being that we can keep track of the previous
    // owner of the NFT with that `tokenId` and if the claimant now has that NFT then we can close the stream for the previous holder
    // and open for the new one. I believe this is better for our keeper as we don't have to close the stream of the user
    // who just transferred the NFT. We can choose to close the stream too. This is worth discussing.
    // The drawback is that a user with multiple NFTs might have to call this function multiple times.
    // Of course batching could be done but the problem of providing all the NFT ids still remains.
    // The workaround for now is that I will create another method for claims by `tokenIds`.
    function claimStream(bytes32 _id) external {
        if (pauseBulkClaims) revert BulkClaimsPaused();

        Tap storage tap = Taps[_id];

        if (!tap.active) revert TapInactive(_id);

        // 1. Check if the holder has the NFT corresponding to the tap id given.
        // 2. Check if the balance of the tap is at least greater than deposit amount required for opening the streams.
        // 3. Check if the total outgoing stream is equivalent to the calculated outgoing streams.
        //  - If yes, then no new stream can be claimed.
        //  - Else, start a new stream to match the calculated outgoing stream value for the holder.
        // Optional:
        // - If using Stroller Protocol, check if we have the required amount of funds in this contract.
        //  - If yes, then proceed.
        //  - Else, ask the Stroller contract for the funds to at least cover the deposit amount required for starting
        //    a new stream (if don't already have it).
        // 4. Increase the numStreams value of the tap to match the outgoing streams of the tap.
        // Note: When starting a new stream, account for the deposit amount worth of tokens.

        ISuperToken streamToken = tap.streamToken;
        uint96 ratePerNFT = tap.ratePerNFT;
        uint256 nftBalance = IERC721(tap.nft).balanceOf(msg.sender);
        int96 exOutStreamRate = ((nftBalance * ratePerNFT).toInt256())
            .toInt96();
        int96 acOutStreamRate = CFA_V1_FORWARDER.getFlowrate(
            tap.streamToken,
            address(this),
            msg.sender
        );

        int96 outStreamRate = exOutStreamRate - acOutStreamRate;

        if (outStreamRate < 0) revert IneligibleClaim(_id);

        // Actual outgoing stream rate for a holder must be less than or equal to expected/calculated outgoing stream rate.
        // Ideally, the out stream amount should be +ve. -ve means we are getting an incoming stream.
        // Check the value given by `getFlowrate` of CFAV1Forwarder. I think it's not possible to get a -ve value.
        assert(acOutStreamRate >= 0 && exOutStreamRate >= 0);

        uint256 depositAmount = CFA_V1_FORWARDER.getBufferAmountByFlowrate(
            streamToken,
            outStreamRate
        );

        uint256 currTapBalance = tapBalance(_id);
        // TODO: Change this condition to minAmountReq = currOutStream * 1 days.
        uint256 reqTapBalance = 2 * depositAmount;

        // OPTIONAL: If using Stroller Protocol, trigger top-up if deposit amount is insufficient for a new claim.

        if (currTapBalance < reqTapBalance)
            revert TapBalanceInsufficient(_id, currTapBalance, reqTapBalance);

        CFA_V1_FORWARDER.createFlow(
            streamToken,
            address(this),
            msg.sender,
            exOutStreamRate - acOutStreamRate,
            "0x"
        );

        tap.numStreams += uint96(outStreamRate) / ratePerNFT;

        emit StreamsClaimed(_id, msg.sender, acOutStreamRate, exOutStreamRate);
    }

    function claimStream(bytes32 _id, uint256 _tokenId) external {
        Tap storage tap = Taps[_id];

        if (!tap.active) revert TapInactive(_id);

        // 1. Check if the holder has the NFT corresponding to the tap id and token id given.
        // 2. Check if the balance of the tap is at least greater than deposit amount required for opening the streams.
        // Optional:
        // - If using Stroller Protocol, check if we have the required amount of funds in this contract.
        //  - If yes, then proceed.
        //  - Else, ask the Stroller contract for the funds to at least cover the deposit amount required for starting
        //    a new stream (if don't already have it).
        // 3. Increase the numStreams value of the tap to match the outgoing streams of the tap.
        // Note: When starting a new stream, account for the deposit amount worth of tokens.

        address nft = tap.nft;
        address prevHolder = tokenIdHolders[nft][_tokenId];
        if (IERC721(nft).ownerOf(_tokenId) != msg.sender)
            revert NotOwnerOfNFT(_id, _tokenId);
        if (prevHolder == msg.sender)
            revert StreamAlreadyClaimed(_id, _tokenId);

        ISuperToken streamToken = tap.streamToken;
        int96 ratePerNFT = int96(tap.ratePerNFT);

        uint256 depositAmount = CFA_V1_FORWARDER.getBufferAmountByFlowrate(
            streamToken,
            ratePerNFT
        );

        uint256 currTapBalance = tapBalance(_id);
        // TODO: Change this condition to minAmountReq = currOutStream * 1 days.
        uint256 reqTapBalance = 2 * depositAmount;

        // OPTIONAL: If using Stroller Protocol, trigger top-up if deposit amount is insufficient for a new claim.

        if (currTapBalance < reqTapBalance)
            revert TapBalanceInsufficient(_id, currTapBalance, reqTapBalance);

        int96 prevHolderStreamRate = CFA_V1_FORWARDER.getFlowrate(
            streamToken,
            address(this),
            prevHolder
        );

        // This check is to ensure an update to stream rate between this contract and the previous
        // holder of the NFT only takes place if the current stream rate is greater than 0.
        // This check is important in case the tap runs out of balance and all the streams corresponding
        // to this tap were closed and after top-up, someone else or the same user comes and claims
        // a stream from the tap. We are assuming that the accounting has been done correctly such
        // that the `prevHolderStreamRate` is a multiple of `ratePerNFT` and hence an update can always
        // take place if `prevHolderStreamRate` > 0.
        // NOTE: Updating a flow in this manner can create a big issue that in case the tap runs out of
        // balance but is restarted after filling up. If a holder had a stream before tap exhaustion,
        // and also has a stream from another tap then the previous holder's stream rate will be updated.
        // This is obviously a very big issue. To counter this, if a tap is exhausted, it shouldn't be
        // allowed to restart. Alternate way is to change the entire architecture of my system and create
        // a proxy contract for each tap. This is not a bad method but will take needless time.
        bool holderChanged;
        if (prevHolderStreamRate > 0) {
            CFA_V1_FORWARDER.updateFlow(
                streamToken,
                address(this),
                prevHolder,
                prevHolderStreamRate - ratePerNFT,
                "0x"
            );

            holderChanged = true;
        }

        if (!holderChanged) tap.numStreams++;
        tokenIdHolders[nft][_tokenId] = msg.sender;

        CFA_V1_FORWARDER.createFlow(
            streamToken,
            address(this),
            msg.sender,
            ratePerNFT,
            "0x"
        );

        emit StreamClaimedById(_id, msg.sender, _tokenId);
    }

    function topUpTap(bytes32 _id, uint256 _amount) external {
        Tap storage tap = Taps[_id];

        if (tap.creator != msg.sender) revert NotTapCreator(_id);
        // The following check might be unnecessary.
        // if (!tap.active) revert TapInactive(_id);

        ISuperToken streamToken = tap.streamToken;
        uint256 currTapBalance = tapBalance(_id);

        streamToken.transferFrom(msg.sender, address(this), _amount);

        tap.lastUpdateTime = (block.timestamp).toUint64();
        tap.balance = currTapBalance + _amount;

        emit TapToppedUp(_id, address(streamToken), _amount);
    }

    function drainTap(bytes32 _id, uint256 _amount) external {
        Tap storage tap = Taps[_id];

        if (tap.creator != msg.sender) revert NotTapCreator(_id);
        // The following check might be unnecessary.
        // if (!tap.active) revert TapInactive(_id);

        int96 currOutStream = int96(
            (tap.numStreams * tap.ratePerNFT).toUint96()
        );
        uint256 currTapBalance = tapBalance(_id);

        if (currTapBalance < _amount)
            revert TapBalanceInsufficient(_id, currTapBalance, _amount);

        uint256 minAmountReq = (currOutStream * 1 days).toUint256();
        uint256 remAmount = currTapBalance - _amount;

        if (minAmountReq < remAmount)
            revert TapMinAmountLimit(_id, remAmount, minAmountReq);

        ISuperToken streamToken = tap.streamToken;

        tap.balance = remAmount;
        tap.lastUpdateTime = (block.timestamp).toUint64();

        streamToken.transfer(msg.sender, _amount);

        emit TapDrained(_id, address(streamToken), _amount, remAmount);
    }

    // TODO: Method to close stream from creator/receiver.
    function closeStream(bytes32 _id, uint256 _tokenId) external {
        Tap storage tap = Taps[_id];
        address creator = tap.creator;

        if (creator == address(0)) revert TapNotFound(_id);

        address prevHolder = tokenIdHolders[tap.nft][_tokenId];

        // If the previous holder is the null address it means stream doesn't exist.
        // NOTE: This isn't true if bulk closure was done WITHOUT destroying the tap.
        if (prevHolder == address(0)) revert StreamNotFound(_id, _tokenId);

        // A stream can be closed because of the following reasons:
        //  - The tap ran out or is running out of balance (out of minimum amount required).
        //  - The receiver transferred the NFT to some other address.
        //  - The creator closes it for some reason (?)

        ISuperToken streamToken = tap.streamToken;
        uint96 ratePerNFT = tap.ratePerNFT;
        address nft = tap.nft;
        address tokenHolder = IERC721(nft).ownerOf(_tokenId);

        // TODO: If `currTapBalance` < `minAmountReq` then this method should invoke,
        // `emergencyCloseStream` and the process of tap closure should be initiated.
        if (tokenHolder == msg.sender || creator == msg.sender) {
            // Close the stream first as these are valid conditions.
            // Get the stream rate of the receiver of the stream (from this contract).
            //  - If it's greater than `ratePerNFT` it means we have to update the stream rate.
            //  - Else, we can close the stream rate.
            address prevTokenHolder = tokenIdHolders[nft][_tokenId];
            int96 userOutStreamRate = CFA_V1_FORWARDER.getFlowrate(
                streamToken,
                address(this),
                prevTokenHolder
            );

            uint256 bufferAmount = CFA_V1_FORWARDER.getBufferAmountByFlowrate(
                streamToken,
                int96(ratePerNFT)
            );

            tap.balance = tapBalance(_id) + bufferAmount;
            tap.numStreams--;
            tap.lastUpdateTime = (block.timestamp).toUint64();
            delete tokenIdHolders[nft][_tokenId];

            CFA_V1_FORWARDER.updateFlow(
                streamToken,
                address(this),
                prevTokenHolder,
                userOutStreamRate - int96(ratePerNFT),
                "0x"
            );
        } else {
            revert WrongStreamCloseAttempt(_id, _tokenId);
        }
    }

    // TODO: Method to emergency close streams (in bulk and per token id).

    // NOTE: This method doesn't affect the ongoing streams out of the tap.
    // The holder will have to reclaim a stream.
    // However, reclaiming in bulk could be possible.
    // Another problem is that if rate is decreased then the ongoing streams won't be
    // decreased automatically. The rates have to be adjusted manually.
    function changeRate(bytes32 _id, uint96 _newRatePerNFT) external {
        Tap storage tap = Taps[_id];

        if (tap.creator != msg.sender) revert NotTapCreator(_id);

        uint96 oldRatePerNFT = tap.ratePerNFT;

        if (oldRatePerNFT == _newRatePerNFT)
            revert SameTapRate(_id, _newRatePerNFT);

        tap.ratePerNFT = _newRatePerNFT;

        emit TapRateChanged(_id, oldRatePerNFT, _newRatePerNFT);
    }

    function activateTap(bytes32 _id) external {
        Tap storage tap = Taps[_id];

        if (tap.active == true) revert TapActive(_id);

        tap.active = true;

        emit TapActivated(_id);
    }

    function deactivateTap(bytes32 _id) external {
        Tap storage tap = Taps[_id];

        if (tap.active == false) revert TapInactive(_id);

        tap.active = false;

        emit TapDeactivated(_id);
    }

    function tapBalance(bytes32 _id) public view returns (uint256 _balance) {
        Tap storage tap = Taps[_id];

        // TODO: This value can be negative if our keeper fails to close all the streams
        // before the tap's balance runs out. Account for that later.
        _balance =
            tap.balance -
            (tap.numStreams *
                tap.ratePerNFT *
                (block.timestamp - tap.lastUpdateTime));
    }

    function getTapId(
        string memory _name,
        address _nft,
        address _creator
    ) public pure returns (bytes32 _id) {
        return keccak256(abi.encode(_name, _nft, _creator));
    }
}
