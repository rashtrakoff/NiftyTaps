// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {IcfaV1Forwarder, ISuperToken, ISuperfluid} from "./interfaces/IcfaV1Forwarder.sol";
import {SuperAppBase} from "protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {ITap} from "./interfaces/ITap.sol";

// TODO: Change createFlow, updateFlow, and deleteFlow to setStreamRate.
 
contract Tap is Initializable, ITap, SuperAppBase {
    using SafeCast for *;
    using SafeERC20 for IERC20;

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
            prevHolder = (cachedPrevHolder != address(0) &&
                claimedStreams[msg.sender].isClaimedId[_tokenId])
                ? cachedPrevHolder
                : address(0);
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
        int96 currOutStreamRate = forwarder.getAccountFlowrate(
            streamToken,
            address(this)
        );

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
            int96 currHolderNewStreamRate = _calcCurrHolderStreams(
                forwarder,
                streamToken,
                msg.sender,
                currHolderOldStreamRate,
                cachedRatePerNFT
            );
            int96 newOutStreamRate = prevHolderNewStreamRate +
                currHolderNewStreamRate;

            if (
                !_canAdjustStreams(
                    forwarder,
                    streamToken,
                    currOutStreamRate,
                    newOutStreamRate
                )
            ) revert StreamsAdjustmentsFailed(prevHolder, msg.sender);

            // NOTE: Update flow method may not actually terminate a stream.
            if (prevHolderOldStreamRate != int96(0)) {
                forwarder.updateFlow(
                    streamToken,
                    address(this),
                    prevHolder,
                    prevHolderNewStreamRate,
                    "0x"
                );

                claimedStreams[prevHolder].claimedRate = cachedRatePerNFT;

                // Mark the stream against the `tokenId` as unclaimed for previous holder.
                claimedStreams[prevHolder].isClaimedId[_tokenId] = false;
            }

            if (currHolderOldStreamRate == int96(0)) {
                forwarder.createFlow(
                    streamToken,
                    address(this),
                    msg.sender,
                    currHolderNewStreamRate,
                    "0x"
                );
            } else {
                forwarder.updateFlow(
                    streamToken,
                    address(this),
                    msg.sender,
                    currHolderNewStreamRate,
                    "0x"
                );
            }

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

            if (prevHolderOldStreamRate == int96(0)) {
                forwarder.createFlow(
                    streamToken,
                    address(this),
                    msg.sender,
                    prevHolderNewStreamRate,
                    "0x"
                );
            } else {
                forwarder.updateFlow(
                    streamToken,
                    address(this),
                    msg.sender,
                    prevHolderNewStreamRate,
                    "0x"
                );
            }
        }

        // Mark the stream against the `tokenId` as claimed.
        claimedStreams[msg.sender].isClaimedId[_tokenId] = true;

        if (claimedStreams[msg.sender].claimedRate != cachedRatePerNFT)
            claimedStreams[msg.sender].claimedRate = cachedRatePerNFT;

        emit StreamClaimedById(msg.sender, _tokenId);
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

    function drainTap(uint256 _amount) external {
        if (CREATOR != msg.sender) revert NotTapCreator();
        // The following check might be unnecessary.
        // if (!tap.active) revert TapInactive(_id);

        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;
        int96 currOutStream = forwarder.getAccountFlowrate(
            streamToken,
            address(this)
        );
        uint256 currTapBalance = streamToken.balanceOf(address(this));

        if (currTapBalance < _amount)
            revert TapBalanceInsufficient(currTapBalance, _amount);

        uint256 minAmountReq = (currOutStream * 1 days).toUint256();
        uint256 remAmount = currTapBalance - _amount;

        if (minAmountReq < remAmount)
            revert TapMinAmountLimit(remAmount, minAmountReq);

        if (!streamToken.transfer(msg.sender, _amount)) revert TransferFailed();

        emit TapDrained(address(streamToken), _amount, remAmount);
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

            // NOTE: Update flow method might not terminate the flow.
            forwarder.updateFlow(
                streamToken,
                address(this),
                prevHolder,
                (
                    _canAdjustStreams(
                        forwarder,
                        streamToken,
                        prevHolderOldStreamRate,
                        newOutStreamRate
                    )
                )
                    ? newOutStreamRate
                    : prevHolderOldStreamRate - prevHolderPerIdRate,
                "0x"
            );
        } else {
            revert WrongStreamCloseAttempt(_tokenId, msg.sender);
        }
    }

    // TODO: Method to emergency close streams (in bulk).
    function emergencyCloseStreams(address _holder) external {
        // Anyone can trigger this method if tap balance is insufficient.
        // Creator can trigger this any time.
        IcfaV1Forwarder forwarder = CFA_V1_FORWARDER;
        ISuperToken streamToken = STREAM_TOKEN;

        // Check if the caller is the creator, if not check if tap balance is insufficient.
        if (msg.sender != CREATOR) {
            int96 outStreamRate = forwarder.getAccountFlowrate(
                streamToken,
                address(this)
            );
            uint256 currTapBalance = streamToken.balanceOf(address(this));
            uint256 reqTapBalance = (outStreamRate * 1 days).toUint256();

            if (currTapBalance >= reqTapBalance)
                revert NoEmergency(
                    msg.sender,
                    _holder,
                    currTapBalance,
                    reqTapBalance
                );
        }

        forwarder.deleteFlow(streamToken, address(this), _holder, "0x");

        emit EmergencyCloseInitiated(_holder);
    }

    // TODO: Method to adjust the current streams of a holder.

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

    function _calcCurrHolderStreams(
        IcfaV1Forwarder _forwarder,
        ISuperToken _streamToken,
        address _currHolder,
        int96 _currHolderPerIdRate,
        int96 _cachedRatePerNFT
    ) internal view returns (int96 _currHolderNewStreamRate) {
        if (_currHolderPerIdRate != int96(0)) {
            int96 currHolderOldStreamRate = _forwarder.getFlowrate(
                _streamToken,
                address(this),
                _currHolder
            );
            int96 numStreams = currHolderOldStreamRate / _currHolderPerIdRate;
            _currHolderNewStreamRate = (numStreams + 1) * _cachedRatePerNFT;
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
        int96 prevHolderOldStreamRate = claimedStreams[_prevHolder].claimedRate;

        // Rate per id when last time the stream was claimed against this `tokenId`.
        // This is necessary as `ratePerNFT` can be changed by the creator any time.

        if (_prevHolderPerIdRate != int96(0)) {
            prevHolderOldStreamRate = _forwarder.getFlowrate(
                _streamToken,
                address(this),
                _prevHolder
            );
            int96 numStreams = prevHolderOldStreamRate / _prevHolderPerIdRate;
            _prevHolderNewStreamRate = (numStreams - 1) * _cachedRatePerNFT;
        } else {
            return int96(0);
        }
    }

    function _canAdjustStreams(
        IcfaV1Forwarder _forwarder,
        ISuperToken _streamToken,
        int96 _prevOutStreamRate,
        int96 _newOutStreamRate
    ) internal view returns (bool _can) {
        if (_prevOutStreamRate < _newOutStreamRate) {
            uint256 currTapBalance = _streamToken.balanceOf(address(this));
            uint256 prevBufferAmount = _forwarder.getBufferAmountByFlowrate(
                _streamToken,
                _prevOutStreamRate
            );
            uint256 newBufferAmount = _forwarder.getBufferAmountByFlowrate(
                _streamToken,
                _newOutStreamRate
            );
            uint256 newReqTapBalance = (_newOutStreamRate * 1 days).toUint256();

            uint256 bufferDelta = newBufferAmount - prevBufferAmount;
            if ((currTapBalance - bufferDelta) > newReqTapBalance) return false;
        }

        return true;
    }

    /**************************************************************************
     * SuperApp callbacks
     *************************************************************************/

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

        (address holder, ) = abi.decode(_agreementData, (address, address));

        delete claimedStreams[holder];
    }
}
