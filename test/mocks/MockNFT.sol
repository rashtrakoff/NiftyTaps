// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "solmate/tokens/ERC721.sol";
import "openzeppelin-contracts/utils/Strings.sol";

contract MockNFT is ERC721 {
    uint256 public currentTokenId;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {}

    function mintTo(address recipient) public payable returns (uint256) {
        uint256 newItemId = ++currentTokenId;
        _safeMint(recipient, newItemId);
        return newItemId;
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        return Strings.toString(id);
    }
}
