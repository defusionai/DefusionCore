pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

interface IPlayerReward {
    struct Player {
        address addr;
        bytes32 name;
        uint8 nameCount;
        uint256 laff;
        uint256 amount;
        uint256 rreward;
        uint256 allReward;
        uint256 lv1Count;
        uint256 lv2Count;
    }

    function settleReward(
        address from,
        uint256 amount
    ) external returns (uint256, address, uint256, address);

    function _pIDxAddr(address from) external view returns (uint256);

    function _plyr(
        uint256 playerId
    ) external view returns (Player memory player);

    function _pools(address pool) external view returns (bool);
}
