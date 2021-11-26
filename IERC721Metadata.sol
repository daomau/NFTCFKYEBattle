pragma solidity ^0.8.0;
import "./IERC721.sol";

// SPDX-License-Identifier: MIT

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
abstract contract IERC721Metadata is IERC721 {

    /**
     * @dev Returns the token collection name.
     */
    function name() external virtual view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external virtual view returns (string memory);
}