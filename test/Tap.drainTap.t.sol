// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "./Setup.sol";

contract TapTest is Setup {
    function testDrainTapPartiallyByCreator() public {
        Tap tap = _createTap();

        uint256 creatorBalanceBefore = superToken.balanceOf(admin);

        vm.prank(admin);
        tap.drainTap(1e11);

        assertEq(
            superToken.balanceOf(address(tap)),
            1e12 - 1e11,
            "Tap's balance is wrong"
        );
        assertEq(
            superToken.balanceOf(admin) - creatorBalanceBefore,
            1e11,
            "Creator's balance is wrong"
        );
    }

    function testDrainTapCompletelyByCreator() public {
        Tap tap = _createTap();

        uint256 creatorBalanceBefore = superToken.balanceOf(admin);

        vm.prank(admin);
        tap.drainTap(type(uint256).max);

        assertEq(
            superToken.balanceOf(address(tap)),
            0,
            "Tap's balance is wrong"
        );
        assertEq(
            superToken.balanceOf(admin) - creatorBalanceBefore,
            1e12,
            "Creator's balance is wrong"
        );
    }

    function testDrainTapByAnon() public {
        Tap tap = _createTap();

        vm.startPrank(bob);
        vm.expectRevert(ITap.NotTapCreator.selector);
        tap.drainTap(type(uint256).max);

        vm.expectRevert(ITap.NotTapCreator.selector);
        tap.drainTap(1e11);
    }

    function testDrainTapByCreatorWhenStreamsExist() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.prank(alice);
        tap.claimStream(1);

        uint256 creatorBalanceBefore = superToken.balanceOf(admin);
        uint256 duration = 3600 * 24 * 30;

        // Skipping by a month.
        skip(duration);

        uint256 tapBalanceAfter = superToken.balanceOf(address(tap));

        vm.prank(admin);
        tap.drainTap(type(uint256).max);

        assertEq(
            superToken.balanceOf(address(tap)),
            0,
            "Tap doesn't have min required amount"
        );
        assertEq(
            superToken.balanceOf(admin),
            creatorBalanceBefore + tapBalanceAfter,
            "Creator balance not correct"
        );
    }

    function testDrainTapByAnonWhenStreamsExist() public {
        Tap tap = _createTap();

        nft.mintTo(alice);

        vm.prank(alice);
        tap.claimStream(1);

        uint256 duration = 3600 * 24 * 30;

        // Skipping by a month.
        skip(duration);

        vm.prank(bob);
        vm.expectRevert(ITap.NotTapCreator.selector);
        tap.drainTap(type(uint256).max);
    }
}
