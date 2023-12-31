pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

interface IPlayerBook {
    function settleReward(
        address from,
        uint256 amount
    ) external returns (uint256);

    function bindRefer(
        address from,
        string calldata affCode
    ) external returns (bool);

    function hasRefer(address from) external returns (bool);
}
