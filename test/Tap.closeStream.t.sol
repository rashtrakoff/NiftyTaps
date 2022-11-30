// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "./Setup.sol";

contract TapTest is Setup {
    function testCloseStreamByCreator() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.prank(alice);
        tap.claimStream(1);

        vm.prank(admin);
        tap.closeStream(1);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(0),
            "Previous holder's flow exists"
        );
    }

    function testCloseStreamByReceiver() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.startPrank(alice);
        tap.claimStream(1);
        tap.closeStream(1);
        vm.stopPrank();

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(0),
            "Previous holder's flow exists"
        );
    }

    function testEmergencyCloseStreamsByCreator() public {
        Tap tap = _createTap();

        // Mint 5 NFTs to Alice.
        vm.startPrank(alice);
        for (uint8 i = 1; i <= 5; ++i) {
            nft.mintTo(alice);
            tap.claimStream(i);
        }
        vm.stopPrank();

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(5e10)),
            "Alice's flowrate is wrong"
        );

        vm.prank(admin);
        tap.emergencyCloseStreams(alice);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(0),
            "Alice's flows still exist"
        );

        assertFalse(tap.active(), "Tap still active");
    }

    function testEmergencyCloseStreamsByAnonTrue() public {
        Tap tap = _createTap();

        // Mint 5 NFTs to Alice.
        vm.startPrank(alice);
        for (uint8 i = 1; i <= 5; ++i) {
            nft.mintTo(alice);
            tap.claimStream(i);
        }
        vm.stopPrank();

        // Skip ahead by 19 months 27 days.
        // I arrived at this figure by manual calculation.
        skip(3600 * 24 * 30 * 19 + 3600 * 24 * 27 + 3600 * 4);

        assertTrue(tap.isCritical(), "Tap is not critical");

        tap.emergencyCloseStreams(alice);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(0),
            "Alice's flows still exist"
        );

        assertFalse(tap.active(), "Tap still active");
    }

    function testEmergencyCloseStreamsByAnonFalse() public {
        Tap tap = _createTap();

        // Mint 5 NFTs to Alice.
        vm.startPrank(alice);
        for (uint8 i = 1; i <= 5; ++i) {
            nft.mintTo(alice);
            tap.claimStream(i);
        }
        vm.stopPrank();

        // Skip ahead by 19 months.
        skip(3600 * 24 * 30 * 19);

        assertFalse(tap.isCritical(), "Tap is not critical");

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ITap.NoEmergency.selector, bob));
        tap.emergencyCloseStreams(alice);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(5e10)),
            "Alice's flows don't exist"
        );

        assertTrue(tap.active(), "Tap inactive");
    }
}
