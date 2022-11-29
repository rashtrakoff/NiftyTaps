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
    mapping(uint256 => address) private tokenIdHolders;

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

    // TODO: Shorten the code by breaking into two or more functions.
    function claimStream(uint256 _tokenId) external {
        if (!active) revert TapInactive();

        // 1. Check if the holder has the NFT corresponding to the tap id and token id given.
        // 2. Check if the balance of the tap is at least greater than deposit amount required for opening the streams.
        // Optional:
        // - If using Stroller Protocol, check if we have the required amount of funds in this contract.
        //  - If yes, then proceed.
        //  - Else, ask the Stroller contract for the funds to at least cover the deposit amount required for starting
        //    a new stream (if don't already have it).
        // 3. Increase the numStreams value of the tap to match the outgoing streams of the tap.
        // Note: When starting a new stream, account for the deposit amount worth of tokens.

        IERC721 nft = NFT;

        address prevHolder;
        {
            address cachedPrevHolder = tokenIdHolders[_tokenId];

            // If the previous holder still receives the stream for this `tokenId` only then consider
            // him as the previous holder. In case the stream no longer exists, previous holder is
            // essentially address(0).

            if (
                cachedPrevHolder != address(0) &&
                claimedStreams[cachedPrevHolder].isClaimedId[_tokenId]
            ) {
                prevHolder = cachedPrevHolder;
            }
        }

        if (nft.ownerOf(_tokenId) != msg.sender) revert NotOwnerOfNFT(_tokenId);

        // The problem with this check is that if the tap had been exhausted or the previous holder
        // actually closed the streams then he can't claim the streams.
        if (
            prevHolder == msg.sender &&
            claimedStreams[msg.sender].isClaimedId[_tokenId]
        ) revert StreamAlreadyClaimed(_tokenId);

        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;
        int96 cachedRatePerNFT = ratePerNFT;

        // If the previous holder of the `tokenId` is not the msg.sender then
        // we have to update the previous holder's stream rates and also update the
        // current holder's stream rates.
        if (prevHolder != msg.sender) {
            // 1. See what the new out stream for the contract will be.
            //  - If it's greater than previous out stream rate then see if tap balance is sufficient.
            //  - If yes, then proceed.
            // 2. We have to change the stream rates of previous holder.
            //  - Get the new out stream rate by decreasing 1 stream.
            // 3. Update the stream rate for the new holder (claimant)
            //  - Get the new out stream rate by increasing 1 stream.

            int96 prevHolderOldStreamRate = claimedStreams[prevHolder]
                .claimedRate;
            int96 currHolderOldStreamRate = claimedStreams[msg.sender]
                .claimedRate;
            int96 prevHolderNewStreamRate = _calcPrevHolderStreams(
                forwarder,
                streamToken,
                prevHolder,
                prevHolderOldStreamRate,
                cachedRatePerNFT
            );

            // console.log("Previous holder old stream rate from claimStrema: ");
            // console.logInt(prevHolderOldStreamRate);
            // console.log("Previous holder new stream rate from claimStream: ");
            // console.logInt(prevHolderNewStreamRate);

            int96 currHolderNewStreamRate = _calcCurrHolderStreams(
                forwarder,
                streamToken,
                msg.sender,
                currHolderOldStreamRate,
                cachedRatePerNFT
            );
            // console.log("Current holder new stream rate from claimStream: ");
            // console.logInt(currHolderNewStreamRate);

            int96 deltaStreamRate = (prevHolderNewStreamRate +
                currHolderNewStreamRate) -
                (prevHolderOldStreamRate + currHolderOldStreamRate);

            if (!_canAdjustStreams(forwarder, streamToken, deltaStreamRate))
                revert StreamsAdjustmentsFailed(prevHolder, msg.sender);

            if (prevHolderOldStreamRate != int96(0)) {
                // Mark the stream against the `tokenId` as unclaimed for previous holder.
                claimedStreams[prevHolder].isClaimedId[_tokenId] = false;

                claimedStreams[prevHolder].claimedRate = cachedRatePerNFT;

                // Reduce the number of streams the prev holder has.
                --claimedStreams[prevHolder].numStreams;

                forwarder.setFlowrate(
                    streamToken,
                    prevHolder,
                    prevHolderNewStreamRate
                );
            }

            forwarder.setFlowrate(
                streamToken,
                msg.sender,
                currHolderNewStreamRate
            );

            // Update `tokenId` holder.
            tokenIdHolders[_tokenId] = msg.sender;
        } else {
            int96 prevHolderOldStreamRate = claimedStreams[msg.sender]
                .claimedRate;

            int96 prevHolderNewStreamRate = _calcCurrHolderStreams(
                forwarder,
                streamToken,
                msg.sender,
                prevHolderOldStreamRate,
                cachedRatePerNFT
            );

            forwarder.setFlowrate(
                streamToken,
                msg.sender,
                prevHolderNewStreamRate
            );
        }

        // Mark the stream against the `tokenId` as claimed.
        claimedStreams[msg.sender].isClaimedId[_tokenId] = true;
        ++claimedStreams[msg.sender].numStreams;

        if (claimedStreams[msg.sender].claimedRate != cachedRatePerNFT) {
            claimedStreams[msg.sender].claimedRate = cachedRatePerNFT;
        }

        emit StreamClaimedById(msg.sender, _tokenId);
    }

    function reinstateStreams(address _prevHolder) external {
        if (!active) revert TapInactive();

        if (claimedStreams[_prevHolder].claimedRate != 0)
            revert StreamsAlreadyReinstated(_prevHolder);

        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;

        int96 cachedRatePerNFT = ratePerNFT;
        int96 numStreams = (claimedStreams[_prevHolder].numStreams)
            .toInt256()
            .toInt96();
        int96 deltaStreamRate = numStreams * cachedRatePerNFT;

        if (_canAdjustStreams(forwarder, streamToken, deltaStreamRate))
            revert StreamsAlreadyReinstated(_prevHolder);

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
        // The following check might be unnecessary.
        // if (!tap.active) revert TapInactive(_id);

        ISuperToken streamToken = STREAM_TOKEN;

        if (!streamToken.transferFrom(msg.sender, address(this), _amount))
            revert TransferFailed();

        emit TapToppedUp(address(streamToken), _amount);
    }

    // NOTE: This method can lead to instant liquidation of streams.
    function drainTap(uint256 _amount) external {
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
        // NOTE: This isn't true if bulk closure was done WITHOUT destroying the tap.
        if (
            prevHolder == address(0) ||
            !claimedStreams[prevHolder].isClaimedId[_tokenId]
        ) revert StreamNotFound(_tokenId);

        // A stream can be closed because of the following reasons:
        //  - The tap ran out or is running out of balance (out of minimum amount required).
        //  - The receiver transferred the NFT to some other address.
        //  - The creator closes it for some reason (although he could use emergency close instead).

        ISuperToken streamToken = STREAM_TOKEN;
        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        address tokenHolder = NFT.ownerOf(_tokenId);

        if (tokenHolder == msg.sender || CREATOR == msg.sender) {
            // Close the stream first as these are valid conditions.
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
                forwarder,
                streamToken,
                prevHolder,
                prevHolderPerIdRate,
                ratePerNFT
            );

            delete tokenIdHolders[_tokenId];
            delete claimedStreams[prevHolder].isClaimedId[_tokenId];
            --claimedStreams[prevHolder].numStreams;

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

    // NOTE: Can add feature to transfer buffer amount as an incentive.
    function emergencyCloseStreams(address _holder) external {
        // Anyone can trigger this method if tap balance is insufficient.
        // Creator can trigger this any time.

        // Check if the caller is the creator, if not check if tap balance is insufficient.
        if (msg.sender != CREATOR && !isCritical()) {
            revert NoEmergency(msg.sender);
        }

        // Change the tap status to inactive to disallow new outgoing streams.
        if (active) active = false;

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

    // NOTE: This method doesn't affect the ongoing streams out of the tap.
    // The holder will have to reclaim a stream.
    // However, reclaiming in bulk could be possible.
    // Another problem is that if rate is decreased then the ongoing streams won't be
    // decreased automatically. The rates have to be adjusted manually.
    function changeRate(uint96 _newRatePerNFT) external {
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
        IcfaV1Forwarder _forwarder,
        ISuperToken _streamToken,
        address _currHolder,
        int96 _currHolderPerIdRate,
        int96 _cachedRatePerNFT
    ) internal view returns (int96 _currHolderNewStreamRate) {
        if (_currHolderPerIdRate != int96(0)) {
            // console.log("Num streams: ");
            // console.logInt(numStreams);

            _currHolderNewStreamRate =
                ((claimedStreams[_currHolder].numStreams).toInt256().toInt96() +
                    1) *
                _cachedRatePerNFT;

            // console.log("Cached rate per NFT:");
            // console.logInt(_cachedRatePerNFT);
            // console.log("Current holder new stream rate from _calcCurrHolder:");
            // console.logInt(_currHolderNewStreamRate);
        } else {
            return _cachedRatePerNFT;
        }
    }

    function _calcPrevHolderStreams(
        IcfaV1Forwarder _forwarder,
        ISuperToken _streamToken,
        address _prevHolder,
        int96 _prevHolderPerIdRate,
        int96 _cachedRatePerNFT
    ) internal view returns (int96 _prevHolderNewStreamRate) {
        // int96 prevHolderOldStreamRate = claimedStreams[_prevHolder].claimedRate;

        // console.log("Previous holder old stream rate: ");
        // console.logInt(prevHolderOldStreamRate);

        // Rate per id when last time the stream was claimed against this `tokenId`.
        // This is necessary as `ratePerNFT` can be changed by the creator any time.
        if (_prevHolderPerIdRate != int96(0)) {
            _prevHolderNewStreamRate =
                ((claimedStreams[_prevHolder].numStreams).toInt256().toInt96() -
                    1) *
                _cachedRatePerNFT;
            // console.log("Previous holder new stream rate: ");
            // console.logInt(_prevHolderNewStreamRate);
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

        // console.log("Delta stream rate: ");
        // console.logInt(_deltaStreamRate);

        if (currNetStreamRate < _deltaStreamRate) {
            uint256 currTapBalance = _streamToken.balanceOf(address(this));
            uint256 deltaBufferAmount = _forwarder.getBufferAmountByFlowrate(
                _streamToken,
                _deltaStreamRate
            );
            uint256 newReqTapBalance = ((-1 * currNetStreamRate) * 1 days)
                .toUint256();

            if ((currTapBalance - deltaBufferAmount) < newReqTapBalance)
                return false;
        }

        return true;
    }

    // TODO: Remove this method after testing is complete.
    function getClaimedData(address _user, uint256 _tokenId)
        public
        view
        returns (bool _status, int96 _claimedRate)
    {
        _status = claimedStreams[_user].isClaimedId[_tokenId];
        _claimedRate = claimedStreams[_user].claimedRate;
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

        (, address holder) = abi.decode(_agreementData, (address, address));

        console.log("Reached here");

        delete claimedStreams[holder].claimedRate;
    }
}
