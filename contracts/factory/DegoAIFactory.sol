pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface DegoAI {
    function mint(address to, uint256 tokenId) external returns (uint256);
}

contract DegoAIFactory is ReentrancyGuard {
    address private degoAi;

    event NFTMint(address indexed account, uint256 indexed tokenId);

    constructor(address degoAi_) {
        degoAi = degoAi_;
    }

    function mint(uint256 tokenId) external nonReentrant returns (uint256) {
        DegoAI(degoAi).mint(msg.sender, tokenId);
        emit NFTMint(msg.sender, tokenId);
        return tokenId;
    }
}
