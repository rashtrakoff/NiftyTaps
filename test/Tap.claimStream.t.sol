// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "./Setup.sol";

contract TapTest is Setup {
    function testTopUpTap() public {
        vm.startPrank(admin);

        Tap tap = Tap(
            tapWizard.createTap(
                "TEST",
                _convertToRate(1e10),
                IERC721(address(nft)),
                superToken
            )
        );

        superToken.increaseAllowance(address(tap), 1e12);
        tap.topUpTap(1e12);

        assertEq(superToken.balanceOf(address(tap)), 1e12);

        vm.stopPrank();
    }

    function testTopUpTapByAnon() public {
        Tap tap = _createTap();

        vm.startPrank(alice);
        superToken.increaseAllowance(address(tap), 1e12);

        vm.expectRevert(ITap.NotTapCreator.selector);
        tap.topUpTap(1e12);

        vm.stopPrank();
    }

    function testClaimStreamByHolder() public {
        Tap tap = _createTap();

        nft.mintTo(alice);
        assertEq(nft.balanceOf(alice), 1, "NFT not minted");
        assertEq(nft.ownerOf(1), alice, "Not the holder of token id");

        vm.prank(alice);
        tap.claimStream(1);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(1e10)),
            "No flow exists"
        );

        // Claiming a new stream with a new NFT token id.
        nft.mintTo(alice);
        assertEq(nft.balanceOf(alice), 2, "NFT not minted");
        assertEq(nft.ownerOf(2), alice, "Not the holder of token id");

        vm.prank(alice);
        tap.claimStream(2);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(2e10)),
            "No flow exists"
        );
    }

    function testRepeatedClaimStreamByHolder() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.startPrank(alice);
        tap.claimStream(1);

        vm.expectRevert(
            abi.encodeWithSelector(ITap.StreamAlreadyClaimed.selector, 1)
        );
        tap.claimStream(1);

        vm.stopPrank();
    }

    function testClaimStreamByNonHolder() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ITap.NotOwnerOfNFT.selector, 1));
        tap.claimStream(1);
    }

    function testClaimStreamByHolderAfterTransfer() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.startPrank(alice);
        tap.claimStream(1);

        nft.transferFrom(alice, bob, 1);

        vm.expectRevert(abi.encodeWithSelector(ITap.NotOwnerOfNFT.selector, 1));
        tap.claimStream(1);

        vm.stopPrank();
    }

    function testClaimStreamByNewHolderAfterTransfer() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.startPrank(alice);
        tap.claimStream(1);
        nft.transferFrom(alice, bob, 1);
        vm.stopPrank();

        vm.prank(bob);
        tap.claimStream(1);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), bob),
            int96(_convertToRate(1e10)),
            "No flow exists"
        );
        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(0),
            "Previous holder's flow exists"
        );
    }

    function testClaimStreamByHolderAfterClosureByHolder() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.startPrank(alice);
        tap.claimStream(1);
        tap.closeStream(1);
        tap.claimStream(1);
        vm.stopPrank();

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(1e10)),
            "No flow exists"
        );
    }

    function testClaimStreamByHolderAfterForceClosureByHolder() public {
        Tap tap = _createTap();

        nft.mintTo(alice);
        nft.mintTo(alice);

        vm.startPrank(alice);

        tap.claimStream(1);
        tap.claimStream(2);

        // Alice closes her stream
        sf.cfaV1Forwarder.deleteFlow(superToken, address(tap), alice, "0x");

        (bool _status, int96 _claimedRate) = tap.getClaimedData(alice, 1);
        console.log("Token id 1 status: %s", _status);
        console.log("Token id 1 claimed rate: ");
        console.logInt(_claimedRate);

        (_status, _claimedRate) = tap.getClaimedData(alice, 2);
        console.log("Token id 2 status: %s", _status);
        console.log("Token id 2 claimed rate: ");
        console.logInt(_claimedRate);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            0,
            "Flows still exist"
        );

        vm.expectRevert(abi.encodeWithSelector(ITap.StreamAlreadyClaimed.selector, 1));
        tap.claimStream(1);

        vm.expectRevert(abi.encodeWithSelector(ITap.StreamAlreadyClaimed.selector, 2));
        tap.claimStream(2);

        vm.stopPrank();
    }

    function testClaimStreamByHolderAfterClosureByCreator() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.prank(alice);
        tap.claimStream(1);

        vm.prank(admin);
        tap.closeStream(1);

        vm.prank(alice);
        tap.claimStream(1);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(1e10)),
            "No flow exists"
        );
    }

    function testClaimStreamByNewHolderAfterClosureByReceiver() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.startPrank(alice);
        tap.claimStream(1);
        tap.closeStream(1);
        nft.transferFrom(alice, bob, 1);
        vm.stopPrank();

        vm.prank(bob);
        tap.claimStream(1);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), bob),
            int96(_convertToRate(1e10)),
            "No flow exists"
        );
        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(0),
            "Previous holder's flow exists"
        );

        // Alice shouldn't be able to reclaim the stream.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ITap.NotOwnerOfNFT.selector, 1));
        tap.claimStream(1);
    }

    function testClaimStreamByNewHolderAfterClosureByCreator() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.prank(alice);
        tap.claimStream(1);

        vm.prank(admin);
        tap.closeStream(1);

        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);

        vm.prank(bob);
        tap.claimStream(1);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), bob),
            int96(_convertToRate(1e10)),
            "No flow exists"
        );
        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(0),
            "Previous holder's flow exists"
        );

        // Alice shouldn't be able to reclaim the stream.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ITap.NotOwnerOfNFT.selector, 1));
        tap.claimStream(1);
    }

    function testChangeRate() public {
        Tap tap = _createTap();

        vm.prank(admin);
        tap.changeRate(uint96(1e11));

        assertEq(tap.ratePerNFT(), int96(1e11), "Rate per NFT not changed");
    }

    function testClaimStreamByHolderAfterRateChange() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.prank(alice);
        tap.claimStream(1);

        vm.prank(admin);
        tap.changeRate(_convertToRate(1e11));

        nft.mintTo(alice);

        vm.prank(alice);
        tap.claimStream(2);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(2e11)),
            "No flow exists"
        );
    }

    function testClaimStreamByNewHolderAfterRateChange() public {
        Tap tap = _createTap();

        nft.mintTo(alice);
        vm.prank(alice);
        tap.claimStream(1);

        vm.prank(admin);
        tap.changeRate(_convertToRate(1e11));

        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);

        vm.prank(bob);
        tap.claimStream(1);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), bob),
            int96(_convertToRate(1e11)),
            "No flow exists"
        );
        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(0),
            "Previous holder's flow exists"
        );

        // If Alice tries to claim a stream, the transaction should revert.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ITap.NotOwnerOfNFT.selector, 1));
        tap.claimStream(1);

        // If Bob tries to claim an already claimed stream, the transaction should revert.
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(ITap.StreamAlreadyClaimed.selector, 1)
        );
        tap.claimStream(1);
    }

    function testClaimStreamsByHolderAfterStreamAdjustments() public {
        Tap tap = _createTap();

        nft.mintTo(alice);
        nft.mintTo(alice);

        vm.startPrank(alice);
        tap.claimStream(1);
        tap.claimStream(2);
        vm.stopPrank();

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(2e10)),
            "Wrong incoming streamrate"
        );

        vm.prank(admin);
        tap.changeRate(_convertToRate(1e11));

        vm.startPrank(alice);
        tap.adjustCurrentStreams(alice);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(2e11)),
            "Streams adjustment error"
        );

        vm.expectRevert(
            abi.encodeWithSelector(ITap.StreamAlreadyClaimed.selector, 1)
        );
        tap.claimStream(1);
        vm.expectRevert(
            abi.encodeWithSelector(ITap.StreamAlreadyClaimed.selector, 2)
        );
        tap.claimStream(2);
    }
}
