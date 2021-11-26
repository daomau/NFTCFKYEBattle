pragma solidity ^0.8.0;
import "./IERC721.sol";

// SPDX-License-Identifier: MIT

/**
 * @title TRC-721 Non-Fungible Token Standard, optional enumeration extension
 */
abstract contract IERC721Enumerable is IERC721 {
    function totalSupply() public virtual view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) public virtual view returns (uint256 tokenId);

    function tokenByIndex(uint256 index) public virtual view returns (uint256);
}