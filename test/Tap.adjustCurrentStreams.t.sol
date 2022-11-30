// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "./Setup.sol";

contract TapTest is Setup {
    function testAdjustStreamsByHolder() public {
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
    }

    // Tests the `adjustCurrentStreams` method for some holder.
    function testAdjustStreamsByAnon() public {
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

        // Some anon updating the streamrates of Alice.
        tap.adjustCurrentStreams(alice);

        assertEq(
            sf.cfaV1Forwarder.getFlowrate(superToken, address(tap), alice),
            int96(_convertToRate(2e11)),
            "Streams adjustment error"
        );
    }

    function testAdjustStreamsWithSameRate() public {
        Tap tap = _createTap();

        nft.mintTo(alice);
        nft.mintTo(alice);

        vm.startPrank(alice);
        tap.claimStream(1);
        tap.claimStream(2);
        
        vm.expectRevert(abi.encodeWithSelector(ITap.SameClaimRate.selector, int96(_convertToRate(1e10))));
        tap.adjustCurrentStreams(alice);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(ITap.SameClaimRate.selector, int96(_convertToRate(1e10))));
        tap.adjustCurrentStreams(alice);
    }
}
