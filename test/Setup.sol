// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import {CFAv1Forwarder} from "protocol-monorepo/packages/ethereum-contracts/contracts/utils/CFAv1Forwarder.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";
import {MockNFT} from "./mocks/MockNFT.sol";
import "./helpers/FoundrySuperfluidTester.sol";
import "../src/Tap.sol";
import "../src/TapWizard.sol";

abstract contract Setup is FoundrySuperfluidTester {
    using CFAv1Library for CFAv1Library.InitData;

    event TapCreated(
        string name,
        address creator,
        address indexed tap,
        address indexed nft,
        address indexed superToken
    );

    TapWizard tapWizard;
    Tap tapImplementation;
    MockNFT nft;

    address constant deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;

    constructor() FoundrySuperfluidTester(3) {}

    function setUp() public override {
        // Deploy new tap implementation contract.
        tapImplementation = new Tap();

        // Deploy tap wizard.
        tapWizard = new TapWizard(
            IcfaV1Forwarder(address(sf.cfaV1Forwarder)),
            sf.host,
            address(tapImplementation)
        );

        nft = new MockNFT("Test", "MNFT");

        // Creates a mock token and a supertoken and fills the mock wallets.
        FoundrySuperfluidTester.setUp();

        // Filling the deployer's wallet with mock tokens and supertokens.
        fillWallet(deployer);
    }
    
    function _createTap() internal returns (Tap _tap) {
        vm.startPrank(admin);
        _tap = Tap(
            tapWizard.createTap(
                "TEST",
                _convertToRate(1e10),
                IERC721(address(nft)),
                superToken
            )
        );
        _tap.activateTap();
        superToken.increaseAllowance(address(_tap), 1e12);
        _tap.topUpTap(1e12);
        vm.stopPrank();
    }

    function _convertToRate(uint256 _rate)
        internal
        pure
        returns (uint96 _flowRate)
    {
        _flowRate = uint96(_rate / 2592000);
    }
}
