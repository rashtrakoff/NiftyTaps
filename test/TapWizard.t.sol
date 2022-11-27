// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "./Setup.sol";

contract TapWizardTest is Setup {
    function testTapCreation() public {
        // console.log("Deployment successful!");
        MockNFT nft = new MockNFT("Test", "MNFT");

        vm.prank(admin);
        address newTap = tapWizard.createTap(
            "Test",
            _convertToRate(1e19),
            IERC721(address(nft)),
            superToken
        );

        assertTrue(newTap != address(0), "New tap's address is null");

        address tapAddr = tapWizard.Taps("Test");

        assertEq(newTap, tapAddr, "Tap address queried by name not found");
    }

    function testSameNameTapCreation() public {
        MockNFT nft = new MockNFT("Test", "MNFT");

        vm.prank(admin);
        tapWizard.createTap(
            "Test",
            _convertToRate(1e19),
            IERC721(address(nft)),
            superToken
        );

        vm.expectRevert(abi.encodeWithSelector(ITapWizard.TapExists.selector, "Test"));

        tapWizard.createTap(
            "Test",
            _convertToRate(1e19),
            IERC721(address(nft)),
            superToken
        );
    }
}
