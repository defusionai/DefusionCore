pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "./DefusionAiFactory.sol";

interface PlayerBookExtension {
    function getPlayerInfo(
        address from
    )
        external
        view
        returns (bytes32, uint256, uint256, uint256, uint256, uint256, uint256);
}

contract DefusionAiFactoryV2 is DefusionAiFactory {
    using SafeERC20 for IERC20;

    mapping(uint256 => uint256) public tokenIdBoosts;
    event eveMintBoosts(uint256 indexed _tokenId, uint256 indexed boosts);

    function mint(
        uint256 _tokenId,
        uint256 _airdropAmount,
        address _mintTo,
        uint256 dummyNum,
        uint256 aigcType,
        bytes calldata _signature,
        address proj,
        uint256 num,
        string calldata affCode
    ) external override nonReentrant {
        require(_mintTo == msg.sender, "_mintTo is not equal sender");
        require(
            verifySignature(
                claimHash(
                    _tokenId,
                    _airdropAmount,
                    _mintTo,
                    dummyNum,
                    aigcType
                ),
                _signature
            ),
            "Invalid signature"
        );
        uint256 stakeNum = 0;
        if (proj != address(0)) {
            uint256 balanceBefore = IERC20(proj).balanceOf(address(this));
            IERC20(proj).safeTransferFrom(_mintTo, address(this), num);
            uint256 balanceEnd = IERC20(proj).balanceOf(address(this));
            stakeNum = balanceEnd - balanceBefore;
        }

        IDefusionAi(defusionAi).mint(
            _mintTo,
            _tokenId,
            IDefusionAi.TokenInfo(
                aigcType,
                proj,
                stakeNum,
                dummyNum,
                block.timestamp
            )
        );

        if (!IPlayerBook(playbook).hasRefer(_mintTo)) {
            IPlayerBook(playbook).bindRefer(_mintTo, affCode);
        }

        if (airdrop) {
            IAIGC(aigc).mint(_mintTo, _airdropAmount);
            if (_airdropAmount > 0) {
                uint256 tenPercentV = _airdropAmount;
                uint256 referralV = (tenPercentV * referralRate) / 100;
                uint256 referralFee = IPlayerBook(playbook).settleReward(
                    _mintTo,
                    referralV
                );
                IAIGC(aigc).mint(playbook, referralFee);
            }
        }
        emit eveMint(
            _tokenId,
            _airdropAmount,
            _mintTo,
            aigcType,
            proj,
            stakeNum,
            dummyNum,
            block.timestamp
        );

        uint256 tokenId_ = _tokenId;
        uint256 lv1Count;
        uint256 lv2Count;
        (, , , , , lv1Count, lv2Count) = PlayerBookExtension(playbook)
            .getPlayerInfo(_mintTo);

        uint256 boost = lv1Count * 7 + lv2Count * 3;
        if (boost >= 100) {
            boost = 100;
        }

        tokenIdBoosts[tokenId_] = boost;
    }

    function getPower(uint256 tokenId) external view returns (uint256) {
        IDefusionAi.TokenInfo memory tokenInfo = IDefusionAi(defusionAi)
            .getTokenInfo(tokenId);
        uint256 baseValue = tokenInfo.boosts;
        uint256 boosts = tokenIdBoosts[tokenId];
        return (((baseValue % 10) + 1) * (100 + boosts));
    }
}
