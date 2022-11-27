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
}
