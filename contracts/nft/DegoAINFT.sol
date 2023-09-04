pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract DegoAINFT is
    AccessControl,
    ERC721Enumerable,
    Ownable,
    ReentrancyGuard
{
    using Strings for uint256;

    string private baseURI;

    uint256 private _tokenId;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    mapping(uint256 => bool) private _usedTokenIds;

    string constant ROLE_MINTER_STR = "MINTER";

    // 0xf0887ba65ee2024ea881d91b74c2450ef19e1557f03bed3ea9f16b037cbe2dc9
    bytes32 constant ROLE_MINTER = keccak256(bytes(ROLE_MINTER_STR));

    string constant ROLE_MINTER_ADMIN_STR = "MINTER_ADMIN";

    // 0x498a9dae57f391d8efcc7bb3e7440ad6a25b1261044ef1b555c5484cb9f67659
    bytes32 constant ROLE_MINTER_ADMIN =
        keccak256(bytes(ROLE_MINTER_ADMIN_STR));

    event AINFTMint(address indexed account, uint256 indexed tokenId);

    event URIPrefix(string indexed baseURI);

    event SetMinterAdmin(bytes32 role, bytes32 adminRole, address admin);

    event RevokeMinterAdmin(bytes32 role, bytes32 adminRole, address admin);

    event SetTokenURI(uint256 indexed tokenId, string uri);

    constructor() ERC721("AIDEGO", "AIDEGO") {
        baseURI = "https://api.dego.finance/api/v1/uri/aigc/zksync/";
        _setRoleAdmin(ROLE_MINTER, ROLE_MINTER_ADMIN);
        _setupRole(ROLE_MINTER_ADMIN, msg.sender);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function setMinterAdmin(address minterAdmin) external onlyOwner {
        _setupRole(ROLE_MINTER_ADMIN, minterAdmin);
        emit SetMinterAdmin(ROLE_MINTER, ROLE_MINTER_ADMIN, minterAdmin);
    }

    function revokeMinterAdmin(address minterAdmin) external onlyOwner {
        _revokeRole(ROLE_MINTER_ADMIN, minterAdmin);
        emit RevokeMinterAdmin(ROLE_MINTER, ROLE_MINTER_ADMIN, minterAdmin);
    }

    function usedTokenId(uint256 tokenId) public view returns (bool) {
        return _usedTokenIds[tokenId];
    }

    function mint(
        address to,
        uint256 tokenId
    ) external nonReentrant returns (uint256) {
        require(
            hasRole(ROLE_MINTER, msg.sender),
            "DEGO: Caller is not a minter"
        );
        _mint(to, tokenId);

        _usedTokenIds[tokenId] = true;

        emit AINFTMint(to, tokenId);

        return tokenId;
    }

    function burn(uint256 _id) external {
        require(
            _isApprovedOrOwner(_msgSender(), _id),
            "ERC721: burn caller is not owner nor approved"
        );
        _burn(_id);

        // Clear metadata (if any)
        if (bytes(_tokenURIs[_id]).length != 0) {
            delete _tokenURIs[_id];
        }
    }

    function updateURIPrefix(string memory baseURI_) external onlyOwner {
        baseURI = baseURI_;
        emit URIPrefix(baseURI);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function updateTokenURI(
        uint256 tokenId,
        string memory _uri
    ) public onlyOwner {
        _setTokenURI(tokenId, _uri);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) internal virtual {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI set of nonexistent token"
        );
        _tokenURIs[tokenId] = _tokenURI;
        emit SetTokenURI(tokenId, _tokenURI);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_exists(tokenId), "DEGO: URI query for nonexistent token");
        string memory baseURI_ = _baseURI();
        // return string(abi.encodePacked(baseURI_, tokenId.toString()));

        string memory _tokenURI = _tokenURIs[tokenId];

        // If there is no base URI, return the token URI.
        if (bytes(baseURI_).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return _tokenURI;
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(baseURI_, tokenId.toString()));
    }
}
