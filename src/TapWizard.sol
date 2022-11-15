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
        newTap.lastUpdateTime = uint64(block.timestamp);
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
        Tap storage tap = Taps[_id];

        // 1. Check if the holder has the NFT corresponding to the tap id given.
        // 2. Check if the total outgoing stream is equivalent to the calculated outgoing streams.
        //  - If yes, then no new stream can be claimed.
        //  - Else, start a new stream to match the calculated outgoing stream value for the holder.
        // Optional:
        // - If using Stroller Protocol, check if we have the required amount of funds in this contract.
        //  - If yes, then proceed.
        //  - Else, ask the Stroller contract for the funds to at least cover the deposit amount required for starting
        //    a new stream (if don't already have it).
        // 3. Increase the numStreams value of the tap to match the outgoing streams of the tap.
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

        // Actual outgoing stream rate for a holder must be less than or equal to expected/calculated outgoing stream rate.
        // Ideally, the out stream amount should be +ve. -ve means we are getting an incoming stream.
        // Check the value given by `getFlowrate` of CFAV1Forwarder. I think it's not possible to get a -ve value.
        assert(
            acOutStreamRate >= 0 && exOutStreamRate >= 0 && outStreamRate >= 0
        );

        CFA_V1_FORWARDER.createFlow(
            streamToken,
            address(this),
            msg.sender,
            exOutStreamRate - acOutStreamRate,
            "0x"
        );

        tap.numStreams += uint96(outStreamRate) / ratePerNFT;
    }

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

        // Note: This value can be negative if our keeper fails to close all the streams
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
