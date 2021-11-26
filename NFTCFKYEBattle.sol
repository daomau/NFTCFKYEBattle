pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "./Context.sol";
import "./Ownable.sol";
import "./ERC165.sol";
import "./IERC721Enumerable.sol";
import "./IERC721Metadata.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./EnumerableSet.sol";
import "./EnumerableMap.sol";
import "./Strings.sol";
import "./IERC721Receiver.sol";

/**
 * @title Fairies contract
 * @dev Extends ERC721 Non-Fungible Token Standard basic implementation
 */
contract NFTCFKYEBattle is Context, Ownable, ERC165, IERC721Enumerable, IERC721Metadata {
    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using Strings for uint256;

    string public PROVENANCE_HASH = "";
    uint256 public constant MAX_NFT_SUPPLY = 2401;
    uint256 public nftPrice = 1500000000;
    uint public constant maxNftPushcase = 20;
    bool public saleIsActive = false;

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    // which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
    bytes4 private constant _TRC721_RECEIVED = 0x5175f878;

    // Mapping from holder address to their (enumerable) set of owned tokens
    mapping(address => EnumerableSet.UintSet) private _holderTokens;

    // Enumerable mapping from token ids to their owners
    EnumerableMap.UintToAddressMap private _tokenOwners;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from token ID to name
    mapping(uint256 => string) private _tokenName;

    // Mapping if certain name string has already been reserved
    mapping(string => bool) private _nameReserved;

    // Mapping from token ID to whether minted before reveal
    mapping(uint256 => bool) private _mintedBeforeReveal;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * Actual tokens store
     */
    uint256[MAX_NFT_SUPPLY] internal indices;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;
    
    /*
     *     bytes4(keccak256('balanceOf(address)')) == 0x70a08231
     *     bytes4(keccak256('ownerOf(uint256)')) == 0x6352211e
     *     bytes4(keccak256('approve(address,uint256)')) == 0x095ea7b3
     *     bytes4(keccak256('getApproved(uint256)')) == 0x081812fc
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c5
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     => 0x70a08231 ^ 0x6352211e ^ 0x095ea7b3 ^ 0x081812fc ^
     *        0xa22cb465 ^ 0xe985e9c5 ^ 0x23b872dd ^ 0x42842e0e ^ 0xb88d4fde == 0x80ac58cd
     */
    bytes4 private constant _INTERFACE_ID_TRC721 = 0x80ac58cd;

    /*
     *     bytes4(keccak256('name()')) == 0x06fdde03
     *     bytes4(keccak256('symbol()')) == 0x95d89b41
     *
     *     => 0x06fdde03 ^ 0x95d89b41 == 0x93254542
     */
    bytes4 private constant _INTERFACE_ID_TRC721_METADATA = 0x5b5e139f;

    /*
     *     bytes4(keccak256('totalSupply()')) == 0x18160ddd
     *     bytes4(keccak256('tokenOfOwnerByIndex(address,uint256)')) == 0x2f745c59
     *     bytes4(keccak256('tokenByIndex(uint256)')) == 0x4f6ccce7
     *
     *     => 0x18160ddd ^ 0x2f745c59 ^ 0x4f6ccce7 == 0x780e9d63
     */
    bytes4 private constant _INTERFACE_ID_TRC721_ENUMERABLE = 0x780e9d63;

    // Events
    event NameChange(uint256 indexed nftIndex, string newName);
    event UserRegistered(uint256 indexed userId, uint256 indexed refererId, address wallet);
    
    uint256 private nonce = 0;
    
    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;
    
    struct PoolUser {
        uint    poolId;
        uint    referer;
        uint    mintedCount;
        bool    isExists;
    }
    
    mapping(address => PoolUser) public users;
    uint256 public poolSize;
    mapping(uint => address payable) public userWallets;
    uint256 private refererReward = 10;

    address private _uriSetterAddress;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory nftName, string memory nftSymbol, uint256 price, address uriSetter) {
        _name = nftName;
        _symbol = nftSymbol;
        nftPrice = price;
        _uriSetterAddress = uriSetter;

        // register the supported interfaces to conform to TRC721 via ERC165
        _registerInterface(_INTERFACE_ID_TRC721);
        _registerInterface(_INTERFACE_ID_TRC721_METADATA);
        _registerInterface(_INTERFACE_ID_TRC721_ENUMERABLE);
    }
    
    bool private reentrancyLock = false;

    modifier ownerOrUriSetter() {
        require(_msgSender() == _uriSetterAddress || _msgSender() == owner(), "cannot set URI");
        _;
    }

    /* Prevent a contract function from being reentrant-called. */
    modifier reentrancyGuard {
        if (reentrancyLock) {
            revert();
        }
        reentrancyLock = true;
        _;
        reentrancyLock = false;
    }
    
    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public override view returns (uint256) {
        require(
            owner != address(0),
            "TRC721: balance query for the zero address"
        );

        return _holderTokens[owner].length();
    }

    /*     
    * Set provenance once it's calculated
    */
    function setProvenanceHash(string memory provenanceHash) public onlyOwner {
        PROVENANCE_HASH = provenanceHash;
    }

    /*
    * Pause sale if active, make active if paused
    */
    function flipSaleState() public onlyOwner {
        saleIsActive = !saleIsActive;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public override view returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public override view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) override
        public
        view
        returns (uint256)
    {
        return _holderTokens[owner].at(index);
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        // _tokenOwners are indexed by tokenIds, so .length() returns the number of tokenIds
        return _tokenOwners.length();
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index) public override view returns (uint256) {
        (uint256 tokenId, ) = _tokenOwners.at(index);
        return tokenId;
    }

    /**
     * @dev Gets current Nft Price
     */
    function getNFTPrice() public view returns (uint256) {
        require(totalSupply() < MAX_NFT_SUPPLY, "Sale has already ended");
        return nftPrice;
    }
    
    
    /**
     * @dev Returns the URI for a given token ID. May return an empty string.
     *
     * If the token's URI is non-empty and a base URI was set (via
     * {_setBaseURI}), it will be added to the token ID's URI as a prefix.
     *
     * Reverts if the token ID does not exist.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "TRC721Metadata: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];

        // Even if there is a base URI, it is only appended to non-empty token-specific URIs
        require(bytes(_tokenURI).length > 0, "Token URI not set");

        return _tokenURI;
    }

    function setTokenURI(uint256 tokenId, string memory uri) public ownerOrUriSetter {
        _setTokenURI(tokenId, uri);
    }
    
    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }

        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }

        bytes memory bstr = new bytes(len);
        uint k = len - 1;
        while (_i != 0) {
            bstr[k--] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
        }

        return string(bstr);
    }

    /**
     * @dev Internal function to set the token URI for a given token.
     *
     * Reverts if the token ID does not exist.
     *
     * TIP: if all token IDs share a prefix (e.g. if your URIs look like
     * `http://api.myproject.com/token/<id>`), use {_setBaseURI} to store
     * it and save gas.
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal {
        require(_exists(tokenId), "TRC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }
        
    function getUserPoolId(address owner) external view returns(uint) {
        require(users[owner].isExists, "User not exists");
        return users[owner].poolId;
    }
    
    function getPoolAddress(uint index) external view returns(address) {
        require(index <= poolSize && index > 0, "Invalid index");
        return userWallets[index];
    }

    /**
     * @dev Mints Nft
     */
    function mintNFT(uint256 numberOfNfts, uint256 refererUserId) public payable {
        require(saleIsActive, "sale is not start");
        require(totalSupply() < MAX_NFT_SUPPLY, "Sale has already ended");
        require(numberOfNfts > 0, "numberOfNfts cannot be 0");
        require(
            numberOfNfts <= maxNftPushcase,
            "You may not buy more than 20 NFTs at once"
        );
        require(
            totalSupply().add(numberOfNfts) <= MAX_NFT_SUPPLY,
            "Exceeds MAX_NFT_SUPPLY"
        );
        require(
            nftPrice.mul(numberOfNfts) == msg.value,
            "Trx value sent is not correct"
        );

        if (refererUserId > 0) {
            require(users[userWallets[refererUserId]].isExists, "referal is not exists");
        }
        
        uint256 price = msg.value;
        if (users[msg.sender].isExists) {
            users[msg.sender].mintedCount += numberOfNfts;
        } else {
            PoolUser memory newUser;
            poolSize++;
            newUser = PoolUser({
                poolId: poolSize,
                isExists: true,
                referer: refererUserId,
                mintedCount: numberOfNfts
            });
            
            users[msg.sender] = newUser;
            userWallets[poolSize] = payable(msg.sender);

            emit UserRegistered(poolSize, refererUserId, msg.sender);
        }
        
        for (uint256 i = 0; i < numberOfNfts; i++) {
            uint256 mintIndex = randomIndex();
            _safeMint(msg.sender, mintIndex);
        }


        if (users[msg.sender].referer > 0 && users[userWallets[users[msg.sender].referer]].isExists) {
            uint256 refReward = price.mul(refererReward).div(100);
            (bool success, ) = userWallets[users[msg.sender].referer].call{value:refReward}("");
            require(
                success,
                "Address: unable to send value, recipient may have reverted"
            );
        }
    }
    
    function reserveTokens(uint256 count) public onlyOwner {
        require(!saleIsActive, "Sale activated");
        
        for (uint256 i = 0; i < count; i++) {
            uint256 mintIndex = randomIndex();
            _safeMint(msg.sender, mintIndex);
        }
    }

    /**
     * @dev Withdraw ether from this contract (Callable by owner)
     */
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    /**
     * Get random index
     */
    function randomIndex() internal returns (uint256) {
        uint256 totalSize = MAX_NFT_SUPPLY - totalSupply();
        uint256 index = uint256(
            keccak256(
                abi.encodePacked(
                    nonce,
                    msg.sender,
                    block.difficulty,
                    block.timestamp
                )
            )
        ) % totalSize;
        uint256 value = 0;
        if (indices[index] != 0) {
            value = indices[index];
        } else {
            value = index;
        }

        // Move last value to selected position
        if (indices[totalSize - 1] == 0) {
            // Array position not initialized, so use position
            indices[index] = totalSize - 1;
        } else {
            // Array position holds a value so use that
            indices[index] = indices[totalSize - 1];
        }
        nonce++;
        // Don't allow a zero index, start counting at 1
        return value.add(1);
    }
    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public override {
        address owner = ownerOf(tokenId);
        require(to != owner, "TRC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public override view returns (address) {
        require(
            _exists(tokenId),
            "TRC721: approved query for nonexistent token"
        );

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public override {
        require(operator != _msgSender(), "TRC721: approve to caller");

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) override
        public
        view
        returns (bool)
    {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        //solhint-disable-next-line max-line-length
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "TRC721: transfer caller is not owner nor approved"
        );

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "TRC721: transfer caller is not owner nor approved"
        );
        _safeTransfer(from, to, tokenId, _data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `_data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal {
        _transfer(from, to, tokenId);
        require(
            _checkOnTRC721Received(from, to, tokenId, _data),
            "TRC721: transfer to non TRC721Receiver implementer"
        );
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _tokenOwners.contains(tokenId);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        returns (bool)
    {
        require(
            _exists(tokenId),
            "TRC721: operator query for nonexistent token"
        );
        address owner = ownerOf(tokenId);
        return (spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender));
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     d*
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal {
        require(totalSupply() < MAX_NFT_SUPPLY);
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal {
        _mint(to, tokenId);
        require(totalSupply() < MAX_NFT_SUPPLY);
        require(
            _checkOnTRC721Received(address(0), to, tokenId, _data),
            "TRC721: transfer to non TRC721Receiver implementer"
        );
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "TRC721: mint to the zero address");
        require(!_exists(tokenId), "TRC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal {
        address owner = ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _holderTokens[owner].remove(tokenId);

        _tokenOwners.remove(tokenId);
        
        // Clear metadata (if any)
        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }

        emit Transfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal {
        require(
            ownerOf(tokenId) == from,
            "TRC721: transfer of token that is not own"
        );
        require(to != address(0), "TRC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _holderTokens[from].remove(tokenId);
        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnTRC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal returns (bool) {
        if (!to.isContractAddr()) {
            return true;
        }
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = to.call(
            abi.encodeWithSelector(
                IERC721Receiver(to).onTRC721Received.selector,
                _msgSender(),
                from,
                tokenId,
                _data
            )
        );
        if (!success) {
            if (returndata.length > 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert("TRC721: transfer to non TRC721Receiver implementer");
            }
        } else {
            bytes4 retval = abi.decode(returndata, (bytes4));
            return (retval == _TRC721_RECEIVED);
        }
    }

    function _approve(address to, uint256 tokenId) private {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
    
     /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public override view returns (address) {
        return
            _tokenOwners.get(
                tokenId,
                "TRC721: owner query for nonexistent token"
            );
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal {}
}
