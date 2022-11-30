// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "./Setup.sol";

contract TapTest is Setup {
    function testReinstateStreamsByPrevHolderAfterForceClose() public {
        Tap tap = _createTap();

        vm.startPrank(alice);
        for (uint8 i = 1; i <= 5; ++i) {
            nft.mintTo(alice);
            tap.claimStream(i);
        }

        sf.cfaV1Forwarder.deleteFlow(superToken, address(tap), alice, "0x");

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            0,
            "Flows still exist"
        );

        console.log("Alice's address: %s", alice);
        tap.reinstateStreams(alice);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(5e10)),
            "No flow exists"
        );

        vm.stopPrank();
    }

    function testReinstateStreamsByHolderAfterTransferAndForceClose() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.startPrank(alice);
        for (uint8 i = 1; i <= 5; ++i) {
            nft.mintTo(alice);
            tap.claimStream(i);
        }

        sf.cfaV1Forwarder.deleteFlow(superToken, address(tap), alice, "0x");

        nft.transferFrom(alice, bob, 1);
        nft.transferFrom(alice, bob, 2);

        vm.stopPrank();

        vm.startPrank(bob);
        tap.claimStream(1);
        tap.claimStream(2);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), bob),
            int96(_convertToRate(2e10)),
            "Incoming flow rate is wrong"
        );

        vm.stopPrank();

        vm.prank(alice);
        tap.reinstateStreams(alice);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(3e10)),
            "Incoming flow rate after reinstatement is wrong"
        );
    }

    function testReinstateStreamsByNewHolderAfterTransfer() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.startPrank(alice);
        tap.claimStream(1);
        nft.transferFrom(alice, bob, 1);
        vm.stopPrank();

        // We are checking if anyone can manipulate the method to start illegal streams to Bob
        // or Alice.
        vm.expectRevert(abi.encodeWithSelector(ITap.HolderStreamsNotFound.selector, bob));
        tap.reinstateStreams(bob);
        vm.expectRevert(abi.encodeWithSelector(ITap.StreamsAlreadyReinstated.selector, alice));
        tap.reinstateStreams(alice);
    }

    function testReinstateStreamsByHolderWhenCriticial() public {
        Tap tap = _createTap();

        // Mint 5 NFTs to Alice.
        vm.startPrank(alice);
        for (uint8 i = 1; i <= 5; ++i) {
            nft.mintTo(alice);
            tap.claimStream(i);
        }

        // Skip ahead by 19 months 27 days & 4 hours.
        // I arrived at this figure by manual calculation.
        skip(3600 * 24 * 30 * 19 + 3600 * 24 * 27 + 3600 * 4);

        assertTrue(tap.isCritical(), "Tap is not critical");
        
        sf.cfaV1Forwarder.deleteFlow(superToken, address(tap), alice, "0x");

        vm.expectRevert(abi.encodeWithSelector(ITap.StreamAdjustmentFailedInReinstate.selector, alice));
        tap.reinstateStreams(alice);

        vm.stopPrank();
    }
}
