pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interface/IDefusionAi.sol";
import "../interface/IPlayerBook.sol";

interface IDefusionAiFactory {
    function getPower(uint256 tokenId) external view returns (uint256);
}

interface PlayerBookExtension {
    function getPlayerInfo(
        address from
    )
        external
        view
        returns (bytes32, uint256, uint256, uint256, uint256, uint256, uint256);

    function _plyr(
        uint256 pID
    )
        external
        view
        returns (
            address addr,
            bytes32 name,
            uint8 nameCount,
            uint256 laff,
            uint256 amount,
            uint256 rreward,
            uint256 allReward,
            uint256 lv1Count,
            uint256 lv2Count
        );
}

contract DefusionAiRewardPool is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    // --- Data ---
    bool private initialized; // Flag of initialize data

    struct PlayBook {
        address playbook;
        bool shareReferal;
    }

    PlayBook public playBookStruct;

    struct Reward {
        IERC20 rewardToken;
        address nftFactory;
        address stakeNFT;
        uint256 startTime;
        uint256 duration;
        uint256 initReward;
    }
    Reward public rewardStruct;

    uint256 public rewardRate = 0;
    uint256 private _periodFinish = 0;

    uint256 _lastUpdateTime;
    uint256 _rewardPerTokenStored;
    mapping(address => uint256) _userRewardPerTokenPaid;
    mapping(address => uint256) _rewards;
    mapping(address => uint256) public haveRewards;

    uint256 public totalPower;
    uint256 public totalWeight;
    uint256 public totalBalance;
    mapping(address => uint256) public userPower;
    mapping(address => uint256) public userWeight;
    mapping(address => uint256) public userBalance;

    EnumerableSet.UintSet private allowAigcTypes;
    EnumerableSet.AddressSet private allowProjs;

    mapping(address => EnumerableSet.UintSet) private userNFTSets;

    event SetStakeParam(
        IERC20 _rewardToken,
        address _nftFactory,
        address _stakeNFT,
        uint256 _startTime,
        uint256 _initReward,
        uint256 _duration,
        uint256 _periodFinish
    );
    event UpdateAllowParam(uint256[] _aigcTypes, address[] _projs);
    event UpdateStartTime(
        uint256 indexed _startTime,
        uint256 indexed _duration
    );
    event Stake(address indexed user, uint256 nftId);
    event Withdraw(address indexed user, uint256 nftId);
    event GetRewardShareReferal(
        uint256 indexed reward,
        address indexed user,
        address aff,
        address aff_aff
    );
    event GetReward(address indexed user, uint256 reward);

    modifier updateReward(address account) {
        _rewardPerTokenStored = rewardPerToken();
        _lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            _rewards[account] = earned(account);
            _userRewardPerTokenPaid[account] = _rewardPerTokenStored;
        }
        _;
    }

    // --- Init ---
    function initialize(
        address _owner,
        address _playbook,
        bool _shareReferal,
        uint256 _allowAigcType,
        address _allowProjs
    ) public {
        require(!initialized, "initialize: Already initialized!");

        _transferOwnership(_owner);

        playBookStruct.playbook = _playbook;
        playBookStruct.shareReferal = _shareReferal;

        allowAigcTypes.add(_allowAigcType);
        allowProjs.add(_allowProjs);

        initialized = true;
    }

    function setStakeParam(
        IERC20 _rewardToken,
        address _nftFactory,
        address _stakeNFT,
        uint256 _startTime,
        uint256 _initReward,
        uint256 _duration
    ) external onlyOwner {
        rewardStruct.rewardToken = IERC20(_rewardToken);
        rewardStruct.nftFactory = _nftFactory;
        rewardStruct.stakeNFT = _stakeNFT;

        rewardStruct.duration = _duration;
        rewardStruct.initReward = _initReward;
        rewardRate = _initReward / (_duration);

        rewardStruct.startTime = _startTime;
        _lastUpdateTime = _startTime;
        _periodFinish = _startTime + (_duration);

        emit SetStakeParam(
            _rewardToken,
            _nftFactory,
            _stakeNFT,
            _startTime,
            _initReward,
            _duration,
            _periodFinish
        );
    }

    function updateAllowParam(
        uint256[] memory _aigcTypes,
        address[] memory _projs
    ) external onlyOwner {
        for (uint i = 0; i < _aigcTypes.length; i++) {
            allowAigcTypes.add(_aigcTypes[i]);
        }

        for (uint i = 0; i < _projs.length; i++) {
            allowProjs.add(_projs[i]);
        }

        emit UpdateAllowParam(_aigcTypes, _projs);
    }

    function updateStartTime(
        uint256 _startTime,
        uint256 _duration
    ) external onlyOwner {
        rewardStruct.duration = _duration;
        rewardStruct.startTime = _startTime;
        _lastUpdateTime = _startTime;
        _periodFinish = _startTime + (_duration);
        emit UpdateStartTime(_startTime, _duration);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalWeight == 0) {
            return _rewardPerTokenStored;
        }
        return
            _rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(_lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalWeight)
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            userWeight[account]
                .mul(rewardPerToken().sub(_userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(_rewards[account]);
    }

    function stake(
        uint256 nftId,
        string calldata affCode
    ) external updateReward(msg.sender) nonReentrant {
        require(block.timestamp >= rewardStruct.startTime, "not start");

        IDefusionAi.TokenInfo memory tokenInfo = IDefusionAi(
            rewardStruct.stakeNFT
        ).getTokenInfo(nftId);
        require(
            allowAigcTypes.contains(tokenInfo.aigcType),
            "Not an allowed type!"
        );
        require(
            allowProjs.contains(tokenInfo.proj),
            "Not allowed for mortgage tokens!"
        );

        EnumerableSet.UintSet storage set = userNFTSets[msg.sender];
        set.add(nftId);

        uint256 power = IDefusionAiFactory(rewardStruct.nftFactory).getPower(
            nftId
        );
        userPower[msg.sender] = userPower[msg.sender].add(power);
        totalPower = totalPower.add(power);

        if (tokenInfo.num > 0 && tokenInfo.proj != address(0)) {
            power = power * tokenInfo.num;
            userBalance[msg.sender] = userBalance[msg.sender].add(
                tokenInfo.num
            );
            totalBalance = totalBalance.add(tokenInfo.num);
        }

        userWeight[msg.sender] = userWeight[msg.sender].add(power);
        totalWeight = totalWeight.add(power);

        IERC721(rewardStruct.stakeNFT).safeTransferFrom(
            msg.sender,
            address(this),
            nftId
        );
        if (!IPlayerBook(playBookStruct.playbook).hasRefer(msg.sender)) {
            IPlayerBook(playBookStruct.playbook).bindRefer(msg.sender, affCode);
        }
        emit Stake(msg.sender, nftId);
    }

    function withdraw(
        uint256 nftId
    ) public updateReward(msg.sender) nonReentrant {
        require(nftId > 0, "the nftId error");

        EnumerableSet.UintSet storage set = userNFTSets[msg.sender];
        require(set.remove(nftId), "Not this nft owner");

        IDefusionAi.TokenInfo memory tokenInfo = IDefusionAi(
            rewardStruct.stakeNFT
        ).getTokenInfo(nftId);

        uint256 power = IDefusionAiFactory(rewardStruct.nftFactory).getPower(
            nftId
        );

        userPower[msg.sender] = userPower[msg.sender].sub(power);
        totalPower = totalPower.sub(power);

        if (tokenInfo.num > 0 && tokenInfo.proj != address(0)) {
            power = power * tokenInfo.num;
            userBalance[msg.sender] = userBalance[msg.sender].sub(
                tokenInfo.num
            );
            totalBalance = totalBalance.sub(tokenInfo.num);
        }

        userWeight[msg.sender] = userWeight[msg.sender].sub(power);
        totalWeight = totalWeight.sub(power);

        IERC721(rewardStruct.stakeNFT).safeTransferFrom(
            address(this),
            msg.sender,
            nftId
        );

        emit Withdraw(msg.sender, nftId);
    }

    function stakeNFTs(
        uint256[] memory nftIds,
        string calldata affCode
    ) external updateReward(msg.sender) nonReentrant {
        require(block.timestamp >= rewardStruct.startTime, "not start");
        for (uint i = 0; i < nftIds.length; i++) {
            uint256 nftId = nftIds[i];
            IDefusionAi.TokenInfo memory tokenInfo = IDefusionAi(
                rewardStruct.stakeNFT
            ).getTokenInfo(nftId);
            require(
                allowAigcTypes.contains(tokenInfo.aigcType),
                "Not an allowed type!"
            );
            require(
                allowProjs.contains(tokenInfo.proj),
                "Not allowed for mortgage tokens!"
            );

            EnumerableSet.UintSet storage set = userNFTSets[msg.sender];
            set.add(nftId);

            uint256 power = IDefusionAiFactory(rewardStruct.nftFactory)
                .getPower(nftId);
            userPower[msg.sender] = userPower[msg.sender].add(power);
            totalPower = totalPower.add(power);

            if (tokenInfo.num > 0 && tokenInfo.proj != address(0)) {
                power = power * tokenInfo.num;
                userBalance[msg.sender] = userBalance[msg.sender].add(
                    tokenInfo.num
                );
                totalBalance = totalBalance.add(tokenInfo.num);
            }

            userWeight[msg.sender] = userWeight[msg.sender].add(power);
            totalWeight = totalWeight.add(power);

            IERC721(rewardStruct.stakeNFT).safeTransferFrom(
                msg.sender,
                address(this),
                nftId
            );

            emit Stake(msg.sender, nftId);
        }

        if (!IPlayerBook(playBookStruct.playbook).hasRefer(msg.sender)) {
            IPlayerBook(playBookStruct.playbook).bindRefer(msg.sender, affCode);
        }
    }

    function withdrawNFTs(
        uint256[] memory nftIds
    ) public updateReward(msg.sender) nonReentrant {
        for (uint i = 0; i < nftIds.length; i++) {
            uint256 nftId = nftIds[i];
            require(nftId > 0, "the nftId error");

            EnumerableSet.UintSet storage set = userNFTSets[msg.sender];
            require(set.remove(nftId), "Not this nft owner");

            IDefusionAi.TokenInfo memory tokenInfo = IDefusionAi(
                rewardStruct.stakeNFT
            ).getTokenInfo(nftId);

            uint256 power = IDefusionAiFactory(rewardStruct.nftFactory)
                .getPower(nftId);
            userPower[msg.sender] = userPower[msg.sender].sub(power);
            totalPower = totalPower.sub(power);

            if (tokenInfo.num > 0 && tokenInfo.proj != address(0)) {
                power = power * tokenInfo.num;
                userBalance[msg.sender] = userBalance[msg.sender].sub(
                    tokenInfo.num
                );
                totalBalance = totalBalance.sub(tokenInfo.num);
            }

            userWeight[msg.sender] = userWeight[msg.sender].sub(power);
            totalWeight = totalWeight.sub(power);

            IERC721(rewardStruct.stakeNFT).safeTransferFrom(
                address(this),
                msg.sender,
                nftId
            );

            emit Withdraw(msg.sender, nftId);
        }
    }

    function getReward() external updateReward(msg.sender) nonReentrant {
        uint256 reward = earned(msg.sender);

        if (reward > 0) {
            if (playBookStruct.shareReferal) {
                uint256 earnReward = (reward * 9) / 10;
                rewardStruct.rewardToken.safeTransfer(msg.sender, earnReward);
                uint256 leftReward = reward - earnReward;
                uint256 affId;
                uint256 aff_affId;
                (, affId, aff_affId, , , , ) = PlayerBookExtension(
                    playBookStruct.playbook
                ).getPlayerInfo(msg.sender);
                address aff;
                address aff_aff;
                (aff, , , , , , , , ) = PlayerBookExtension(
                    playBookStruct.playbook
                )._plyr(affId);
                if (aff_affId == 0) {
                    aff_aff = aff;
                } else {
                    (aff_aff, , , , , , , , ) = PlayerBookExtension(
                        playBookStruct.playbook
                    )._plyr(aff_affId);
                }

                rewardStruct.rewardToken.safeTransfer(
                    aff,
                    (leftReward * 7) / 10
                );
                rewardStruct.rewardToken.safeTransfer(
                    aff_aff,
                    (leftReward * 3) / 10
                );
                emit GetRewardShareReferal(reward, msg.sender, aff, aff_aff);
            } else {
                rewardStruct.rewardToken.safeTransfer(msg.sender, reward);
                emit GetReward(msg.sender, reward);
            }
            haveRewards[msg.sender] = reward;
            _rewards[msg.sender] = 0;
        }
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, _periodFinish);
    }

    function userStakeNums(
        address user
    ) external view returns (uint256 nftAmount) {
        EnumerableSet.UintSet storage set = userNFTSets[user];
        nftAmount = set.length();
    }

    function getAllowAigcTypes() external view returns (uint256[] memory) {
        return allowAigcTypes.values();
    }

    function getAllowProjs() external view returns (address[] memory) {
        return allowProjs.values();
    }

    function userStakeNFTs(
        address user
    ) external view returns (uint256[] memory) {
        EnumerableSet.UintSet storage set = userNFTSets[user];
        return set.values();
    }

    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes memory /*data*/
    ) external pure returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }
}
