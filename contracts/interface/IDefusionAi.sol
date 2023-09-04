pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IDefusionAi {
    struct TokenInfo {
        uint256 aigcType;
        address proj;
        uint256 num;
        uint256 boosts;
        uint256 timestamp;
    }

    function mint(
        address to,
        uint256 tokenId,
        TokenInfo calldata tokenInfo
    ) external returns (uint256);

    function burn(uint256 tokenId) external;

    function getTokenInfo(
        uint256 tokenId
    ) external view returns (TokenInfo calldata tokenInfo);
}
