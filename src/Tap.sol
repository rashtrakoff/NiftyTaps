// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {IcfaV1Forwarder, ISuperToken, ISuperfluid} from "./interfaces/IcfaV1Forwarder.sol";
import {SuperAppBase} from "protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {ITap} from "./interfaces/ITap.sol";
import "forge-std/console.sol";

contract Tap is Initializable, ITap, SuperAppBase {
    using SafeCast for *;

    address public HOST;
    address public CREATOR;
    ISuperToken public STREAM_TOKEN;
    IERC721 public NFT;

    string public name;

    bool public active;

    int96 public ratePerNFT;

    IcfaV1Forwarder internal CFA_V1_FORWARDER;

    // NFT address => TokenId => Holder address.
    mapping(uint256 => address) public tokenIdHolders;

    // TODO: Explain why this mapping is necessary.
    // Holder address => TokenId => Claimed/Unclaimed.
    mapping(address => ClaimedData) private claimedStreams;

    function initialize(
        string memory _name,
        address _host,
        address _creator,
        uint96 _ratePerNFT,
        IcfaV1Forwarder _cfaV1Forwarder,
        IERC721 _nft,
        ISuperToken _streamToken
    ) external initializer {
        HOST = _host;
        CFA_V1_FORWARDER = _cfaV1Forwarder;
        STREAM_TOKEN = _streamToken;
        CREATOR = _creator;
        NFT = _nft;
        ratePerNFT = int96(_ratePerNFT);
        name = _name;

        emit TapCreated(
            _name,
            _creator,
            address(_nft),
            address(_streamToken),
            _ratePerNFT
        );
    }

    function claimStream(uint256 _tokenId) external {
        if (!active) revert TapInactive();

        IERC721 nft = NFT;
        if (nft.ownerOf(_tokenId) != msg.sender) revert NotOwnerOfNFT(_tokenId);

        address prevHolder = tokenIdHolders[_tokenId];

        // The problem this check solves is that if the tap had been exhausted or the previous holder
        // actually closed the streams then he shouldn't be able to claim the streams.
        if (prevHolder == msg.sender) revert StreamAlreadyClaimed(_tokenId);

        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;
        int96 cachedRatePerNFT = ratePerNFT;

        // If the previous holder of the `tokenId` is not the msg.sender then
        // we have to update the previous holder's stream rates and also update the
        // current holder's stream rates.

        // 1. See what the new out stream for the contract will be.
        //  - If it's greater than previous out stream rate then see if tap balance is sufficient.
        //  - If yes, then proceed.
        // 2. We have to change the stream rates of previous holder.
        //  - Get the new out stream rate by decreasing 1 stream.
        // 3. Update the stream rate for the new holder (claimant)
        //  - Get the new out stream rate by increasing 1 stream.

        int96 prevHolderOldStreamRate;
        int96 prevHolderNewStreamRate;

        // If there was a previous claimant
        // - reduce his number of streams.
        // - Calculate his new stream rate after decreasing stream rate for 1 tokenId.
        if (prevHolder != address(0)) {
            prevHolderOldStreamRate = claimedStreams[prevHolder].claimedRate;
            prevHolderNewStreamRate = _calcPrevHolderStreams(
                prevHolder,
                prevHolderOldStreamRate,
                cachedRatePerNFT
            );

            // Reduce the number of streams the prev holder has.
            --claimedStreams[prevHolder].numStreams;
        }

        int96 currHolderOldStreamRate = claimedStreams[msg.sender].claimedRate;

        // Calculate the current claimant's new stream rate by increasing it by
        // stream rate for 1 tokenId.
        int96 currHolderNewStreamRate = _calcCurrHolderStreams(
            msg.sender,
            currHolderOldStreamRate,
            cachedRatePerNFT
        );

        // Calculating difference of outgoing stream rate for the contract.
        // This value could be -ve if the new stream rates are lesser than the
        // old ones.
        int96 deltaStreamRate = (prevHolderNewStreamRate +
            currHolderNewStreamRate) -
            (prevHolderOldStreamRate + currHolderOldStreamRate);

        // Optional:
        // - If using Stroller Protocol, check if we have the required amount of funds in this contract.
        //  -- If yes, then proceed.
        //  -- Else, ask the Stroller contract for the funds to at least cover the deposit amount required for starting
        //    a new stream (if the contract doesn't already have it).

        // Check if we can adjust all the streams belonging to the previous holder
        // and the current claimant.
        // As new outgoing stream rate of the contract can be lesser than previous
        // outgoing stream rate, the `_canAdjust` function will simply return true
        // in such cases.
        if (!_canAdjustStreams(forwarder, streamToken, deltaStreamRate))
            revert StreamsAdjustmentsFailed(prevHolder, msg.sender);

        // If previous holder's old stream rate is not 0 (i.e. streams exist)
        // then adjust the previous holder's streams.
        if (prevHolderOldStreamRate != int96(0)) {
            claimedStreams[prevHolder].claimedRate = cachedRatePerNFT;

            forwarder.setFlowrate(
                streamToken,
                prevHolder,
                prevHolderNewStreamRate
            );
        }

        // Update `tokenId` holder.
        tokenIdHolders[_tokenId] = msg.sender;

        // Increase the number of streams of the claimant.
        ++claimedStreams[msg.sender].numStreams;

        if (claimedStreams[msg.sender].claimedRate != cachedRatePerNFT) {
            claimedStreams[msg.sender].claimedRate = cachedRatePerNFT;
        }

        forwarder.setFlowrate(streamToken, msg.sender, currHolderNewStreamRate);

        emit StreamClaimedById(msg.sender, _tokenId);
    }

    function reinstateStreams(address _prevHolder) external {
        // NOTE: Why do we need this function?
        // When a holder's streams are forcefully closed either by the holder himself
        // or by anyone who successfully triggered `emergencyCloseStream`, there is a chance
        // that the holder again claims streams. The subsequent `claimStream` transactions by the holder
        // will revert with the `StreamAlreadyClaimed` error as this contract doesn't know
        // if the holder has the stream corresponding to a `tokenId`. In order for the holder
        // to get back all the stream, he can use this function.
        // The `claimStream` function also modifies the `numStreams` field of a previous holder
        // of the NFT. So in the above case's event, if any new holder of the `tokenId` claims
        // the stream corresponding to that `tokenId` the previous holder's `numStreams` will
        // decrease and this method will reinstate the correct amount of streams.

        if (!active) revert TapInactive();

        // If claimed rate of the holder is not 0 then they must have ongoing
        // streams. Reinstatement only happens when the holder has no streams
        // because of `emergencyClose` or forced closure by holder himself.
        if (claimedStreams[_prevHolder].claimedRate != int96(0))
            revert StreamsAlreadyReinstated(_prevHolder);

        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;

        int96 cachedRatePerNFT = ratePerNFT;
        int96 numStreams = (claimedStreams[_prevHolder].numStreams)
            .toInt256()
            .toInt96();

        if (numStreams == 0) revert HolderStreamsNotFound(_prevHolder);

        int96 deltaStreamRate = numStreams * cachedRatePerNFT;

        // If new streams can't be started due to low tap balance,
        // this error will be thrown.
        if (!_canAdjustStreams(forwarder, streamToken, deltaStreamRate))
            revert StreamAdjustmentFailedInReinstate(_prevHolder);

        // Update the claimed rate for the holder.
        claimedStreams[_prevHolder].claimedRate = cachedRatePerNFT;

        forwarder.setFlowrate(streamToken, _prevHolder, deltaStreamRate);

        emit StreamsReinstated(
            _prevHolder,
            numStreams,
            deltaStreamRate,
            cachedRatePerNFT
        );
    }

    function topUpTap(uint256 _amount) external {
        if (CREATOR != msg.sender) revert NotTapCreator();

        ISuperToken streamToken = STREAM_TOKEN;

        if (!streamToken.transferFrom(msg.sender, address(this), _amount))
            revert TransferFailed();

        emit TapToppedUp(address(streamToken), _amount);
    }

    function drainTap(uint256 _amount) external {
        // NOTE: This method can lead to instant liquidation of streams.
        if (CREATOR != msg.sender) revert NotTapCreator();

        ISuperToken streamToken = STREAM_TOKEN;
        uint256 currTapBalance = streamToken.balanceOf(address(this));

        if (_amount == type(uint256).max) _amount = currTapBalance;
        else if (currTapBalance < _amount)
            revert TapBalanceInsufficient(currTapBalance, _amount);

        if (!streamToken.transfer(msg.sender, _amount)) revert TransferFailed();

        emit TapDrained(address(streamToken), _amount);
    }

    function closeStream(uint256 _tokenId) external {
        address prevHolder = tokenIdHolders[_tokenId];

        // If the previous holder is the null address it means stream doesn't exist.
        // NOTE: This isn't true if emergency closure was done.
        if (
            prevHolder == address(0) ||
            claimedStreams[prevHolder].numStreams == 0
        ) revert StreamNotFound(_tokenId);

        // A stream can be closed because of the following reasons:
        //  - The tap ran out or is running out of balance (out of minimum amount required).
        //  - The receiver transferred the NFT to some other address.
        //  - The creator closes it for some reason (although he could use emergency close instead).

        ISuperToken streamToken = STREAM_TOKEN;
        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        address tokenHolder = NFT.ownerOf(_tokenId);

        if (tokenHolder == msg.sender || CREATOR == msg.sender) {
            // Close the streams as these are the valid conditions.
            // Get the stream rate of the receiver of the stream (from this contract).
            //  - If it's greater than `ratePerNFT` it means we have to update the stream rate.
            //  - Else, we can close the stream rate.
            int96 prevHolderOldStreamRate = forwarder.getFlowrate(
                streamToken,
                address(this),
                prevHolder
            );
            int96 prevHolderPerIdRate = claimedStreams[prevHolder].claimedRate;
            int96 newOutStreamRate = _calcPrevHolderStreams(
                prevHolder,
                prevHolderPerIdRate,
                ratePerNFT
            );

            delete tokenIdHolders[_tokenId];
            --claimedStreams[prevHolder].numStreams;

            if (
                claimedStreams[prevHolder].numStreams == 0 &&
                claimedStreams[prevHolder].claimedRate != 0
            ) claimedStreams[prevHolder].claimedRate = 0;

            if (
                prevHolderOldStreamRate > newOutStreamRate ||
                (prevHolderOldStreamRate < newOutStreamRate &&
                    _canAdjustStreams(
                        forwarder,
                        streamToken,
                        newOutStreamRate - prevHolderOldStreamRate
                    ))
            ) {
                forwarder.setFlowrate(
                    streamToken,
                    prevHolder,
                    newOutStreamRate
                );
            } else {
                forwarder.setFlowrate(
                    streamToken,
                    prevHolder,
                    prevHolderOldStreamRate - prevHolderPerIdRate
                );
            }
        } else {
            revert WrongStreamCloseAttempt(_tokenId, msg.sender);
        }
    }

    // TODO: Can add feature to transfer buffer amount as an incentive to anon terminator.
    function emergencyCloseStreams(address _holder) external {
        // Anyone can trigger this method if tap balance is insufficient.
        // Creator can trigger this any time.

        // Check if the caller is the creator, if not check if tap balance is insufficient.
        if (msg.sender != CREATOR && !isCritical()) {
            revert NoEmergency(msg.sender);
        }

        // Change the tap status to inactive to disallow new outgoing streams.
        // NOTE: This line might not be necessary if the creator just wants
        // to close streams of a particular address due to some reason.
        if (active) active = false;

        // NOTE: `numStreams` won't change as reinstatement can only be possible
        // if `numStreams` is non-zero. Since, usual route of `claimStream` will
        // revert anyway, `numStreams` can't be made 0 here.

        delete claimedStreams[_holder].claimedRate;

        CFA_V1_FORWARDER.setFlowrate(STREAM_TOKEN, _holder, int96(0));

        emit EmergencyCloseInitiated(_holder);
    }

    function adjustCurrentStreams(address _holder) external {
        if (!active) revert TapInactive();

        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;
        int96 cachedRatePerNFT = ratePerNFT;
        int96 currHolderOldStreamRate = forwarder.getFlowrate(
            streamToken,
            address(this),
            _holder
        );

        if (currHolderOldStreamRate == int96(0))
            revert HolderStreamsNotFound(_holder);

        int96 oldClaimedRate = claimedStreams[_holder].claimedRate;

        if (oldClaimedRate == cachedRatePerNFT)
            revert SameClaimRate(cachedRatePerNFT);

        // Calculate number of streams going to the holder.
        int96 numStreams = currHolderOldStreamRate / oldClaimedRate;

        claimedStreams[_holder].claimedRate = cachedRatePerNFT;

        forwarder.setFlowrate(
            streamToken,
            _holder,
            numStreams * cachedRatePerNFT
        );

        emit StreamsAdjusted(_holder, oldClaimedRate, cachedRatePerNFT);
    }

    function changeRate(uint96 _newRatePerNFT) external {
        // NOTE: This method doesn't affect the ongoing streams out of the tap.
        // A holder (actually anyone) can adjust their outgoing streams.
        // Another problem is that if rate is decreased then the ongoing streams won't be
        // decreased automatically. The rates have to be adjusted manually.
        if (CREATOR != msg.sender) revert NotTapCreator();

        int96 oldRatePerNFT = ratePerNFT;
        int96 newRatePerNFT = int96(_newRatePerNFT);

        if (oldRatePerNFT == newRatePerNFT) revert SameTapRate(newRatePerNFT);

        ratePerNFT = int96(_newRatePerNFT);

        emit TapRateChanged(oldRatePerNFT, newRatePerNFT);
    }

    function activateTap() external {
        if (CREATOR != msg.sender) revert NotTapCreator();
        if (active == true) revert TapActive();

        active = true;

        emit TapActivated();
    }

    function deactivateTap() external {
        if (CREATOR != msg.sender) revert NotTapCreator();
        if (active == false) revert TapInactive();

        active = false;

        emit TapDeactivated();
    }

    function isCritical() public view returns (bool _status) {
        // Anyone can trigger this method to know if tap balance is insufficient.
        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;

        int96 outStreamRate = forwarder.getAccountFlowrate(
            streamToken,
            address(this)
        );

        if (outStreamRate >= 0) return false;

        uint256 currTapBalance = streamToken.balanceOf(address(this));

        // Tap should have enough balance to stream for a day at least.
        uint256 reqTapBalance = (-1 * outStreamRate * 1 days).toUint256();

        if (currTapBalance >= reqTapBalance) return false;

        return true;
    }

    function _calcCurrHolderStreams(
        address _currHolder,
        int96 _currHolderPerIdRate,
        int96 _cachedRatePerNFT
    ) internal view returns (int96 _currHolderNewStreamRate) {
        if (_currHolderPerIdRate != int96(0)) {
            _currHolderNewStreamRate =
                ((claimedStreams[_currHolder].numStreams).toInt256().toInt96() +
                    1) *
                _cachedRatePerNFT;
        } else {
            return _cachedRatePerNFT;
        }
    }

    function _calcPrevHolderStreams(
        address _prevHolder,
        int96 _prevHolderPerIdRate,
        int96 _cachedRatePerNFT
    ) internal view returns (int96 _prevHolderNewStreamRate) {
        if (_prevHolderPerIdRate != int96(0)) {
            _prevHolderNewStreamRate =
                ((claimedStreams[_prevHolder].numStreams).toInt256().toInt96() -
                    1) *
                _cachedRatePerNFT;
        } else {
            return int96(0);
        }
    }

    function _canAdjustStreams(
        IcfaV1Forwarder _forwarder,
        ISuperToken _streamToken,
        int96 _deltaStreamRate
    ) internal view returns (bool _can) {
        int96 currNetStreamRate = _forwarder.getAccountFlowrate(
            _streamToken,
            address(this)
        );

        if (currNetStreamRate < _deltaStreamRate) {
            uint256 currTapBalance = _streamToken.balanceOf(address(this));
            uint256 deltaBufferAmount = _forwarder.getBufferAmountByFlowrate(
                _streamToken,
                _deltaStreamRate
            );
            uint256 newReqTapBalance = ((-1 *
                (currNetStreamRate - _deltaStreamRate)) * 1 days).toUint256();

            if ((currTapBalance - deltaBufferAmount) < newReqTapBalance)
                return false;
        }

        return true;
    }


    /**************************************************************************
     * SuperApp callbacks
     *************************************************************************/

    // TODO: beforeAgreementCreated and afterAgreementCreated hooks to accept incoming stream from
    // the creator.

    function afterAgreementTerminated(
        ISuperToken, /*_streamToken*/
        address, /*_agreementClass*/
        bytes32, /*_agreementId*/
        bytes calldata _agreementData,
        bytes calldata, /*_cbdata*/
        bytes calldata _ctx
    ) external override returns (bytes memory _newCtx) {
        if (msg.sender != HOST) revert NotHost(msg.sender);

        _newCtx = _ctx;

        (, address receiver) = abi.decode(_agreementData, (address, address));

        delete claimedStreams[receiver].claimedRate;
    }
}
