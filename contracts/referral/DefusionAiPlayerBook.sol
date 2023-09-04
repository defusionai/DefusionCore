pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../library/NameFilter.sol";
import "../interface/IPlayerBook.sol";

contract DefusionAiPlayerBook is IPlayerBook, Ownable {
    using NameFilter for string;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // --- Data ---
    bool private initialized; // Flag of initialize data

    // register pools
    mapping(address => bool) public _pools;

    // (addr => pID) returns player id by address
    mapping(address => uint256) public _pIDxAddr;
    // (name => pID) returns player id by name
    mapping(bytes32 => uint256) public _pIDxName;
    // (pID => data) player data
    mapping(uint256 => Player) public _plyr;
    // (pID => name => bool) list of names a player owns.  (used so you can change your display name amoungst any name you own)
    mapping(uint256 => mapping(bytes32 => bool)) public _plyrNames;

    // the  of refrerrals
    uint256 public _totalReferReward;
    // the fee of register
    uint256 public _totalRegisterFee;
    // total number of players
    uint256 public _pID;
    // total register name count
    uint256 public _totalRegisterCount = 0;

    // the direct refer's reward rate
    uint256 public _refer1RewardRate = 700; //7%
    // the second direct refer's reward rate
    uint256 public _refer2RewardRate = 300; //3%

    uint256 public _feeRate; // 0.07%
    // base rate
    uint256 public _baseRate = 10000;

    bytes32 public _defaulRefer =
        0x61696465676f0000000000000000000000000000000000000000000000000000;

    uint256 public _freeAmount;

    address public _teamWallet = address(0);

    IERC20 public _aigc;

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

    event eveClaim(uint256 pID, address addr, uint256 reward);
    event eveBindRefer(
        uint256 pID,
        address addr,
        bytes32 name,
        uint256 affID,
        address affAddr,
        bytes32 affName
    );
    event eveDefaultPlayer(uint256 pID, address addr, bytes32 name);
    event eveNewName(
        uint256 pID,
        address addr,
        bytes32 name,
        uint256 affID,
        address affAddr,
        bytes32 affName
    );
    event eveSettle(
        uint256 pID,
        uint256 affID,
        uint256 aff_affID,
        uint256 affReward,
        uint256 aff_affReward,
        uint256 amount
    );
    event eveAddPool(address addr);
    event eveRemovePool(address addr);
    event eveSetRewardRate(
        uint256 refer1Rate,
        uint256 refer2Rate,
        uint256 feeRate
    );
    event GovernanceTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event TransferReferrer(uint256 pID, address newReferrer);
    event eveWithdrawFee(uint256 registerFee);

    // --- Init ---
    function initialize(address owner, address teamWallet) public {
        require(!initialized, "initialize: Already initialized!");
        _transferOwnership(owner);
        _pID = 0;
        _totalReferReward = 0;
        _totalRegisterCount = 0;
        _refer1RewardRate = 700; //7%
        _refer2RewardRate = 300; //3%
        _feeRate = 7;
        _baseRate = 10000;
        _freeAmount = 101;
        _defaulRefer = 0x6465667573696f6e616900000000000000000000000000000000000000000000;
        _teamWallet = teamWallet;
        addDefaultPlayer(_teamWallet, _defaulRefer);
        initialized = true;
    }

    /**
     * check address
     */
    modifier validAddress(address addr) {
        require(addr != address(0x0));
        _;
    }

    /**
     * check pool
     */
    modifier isRegisteredPool() {
        require(_pools[msg.sender], "invalid pool address!");
        _;
    }

    /**
     * registe a pool
     */
    function addPool(address poolAddr) public onlyOwner {
        require(!_pools[poolAddr], "derp, that pool already been registered");

        _pools[poolAddr] = true;

        emit eveAddPool(poolAddr);
    }

    /**
     * remove a pool
     */
    function removePool(address poolAddr) public onlyOwner {
        require(_pools[poolAddr], "derp, that pool must be registered");

        _pools[poolAddr] = false;

        emit eveRemovePool(poolAddr);
    }

    /**
     * resolve the refer's reward from a player
     */
    function settleReward(
        address from,
        uint256 amount
    ) external override isRegisteredPool validAddress(from) returns (uint256) {
        // set up our tx event data and determine if player is new or not
        // _determinePID(from);
        // uint256 pID = _pIDxAddr[from];
        uint256 pID = _determinePID(from);
        uint256 affID = _plyr[pID].laff;

        if (affID <= 0) {
            affID = _pIDxName[_defaulRefer];
            _plyr[pID].laff = affID;
        }

        uint256 fee = 0;

        // father
        uint256 affReward = (amount.mul(_refer1RewardRate)).div(_baseRate);
        _plyr[affID].rreward = _plyr[affID].rreward.add(affReward);
        _totalReferReward = _totalReferReward.add(affReward);
        fee = fee.add(affReward);

        // grandfather
        uint256 aff_affID = _plyr[affID].laff;
        uint256 aff_affReward = amount.mul(_refer2RewardRate).div(_baseRate);
        if (aff_affID <= 0) {
            aff_affID = _pIDxName[_defaulRefer];
        }
        _plyr[aff_affID].rreward = _plyr[aff_affID].rreward.add(aff_affReward);
        _totalReferReward = _totalReferReward.add(aff_affReward);

        _plyr[pID].amount = _plyr[pID].amount.add(amount);

        fee = fee.add(aff_affReward);

        emit eveSettle(pID, affID, aff_affID, affReward, aff_affReward, amount);

        return fee;
    }

    /**
     * claim all of the refer reward.
     */
    function claim() public {
        address addr = msg.sender;
        uint256 pid = _pIDxAddr[addr];
        uint256 reward = _plyr[pid].rreward;

        require(reward > 0, "only have reward");

        //reset
        _plyr[pid].allReward = _plyr[pid].allReward.add(reward);
        _plyr[pid].rreward = 0;

        //get reward
        _aigc.safeTransfer(addr, reward);

        // fire event
        emit eveClaim(_pIDxAddr[addr], addr, reward);
    }

    /**
     * check name string
     */
    function checkIfNameValid(
        string memory nameStr
    ) public view returns (bool) {
        bytes32 name = nameStr.nameFilter();
        if (_pIDxName[name] == 0) return (true);
        else return (false);
    }

    /**
     * @dev add a default player
     */
    function addDefaultPlayer(address addr, bytes32 name) private {
        _pID++;

        _plyr[_pID].addr = addr;
        _plyr[_pID].name = name;
        _plyr[_pID].nameCount = 1;
        _pIDxAddr[addr] = _pID;
        _pIDxName[name] = _pID;
        _plyrNames[_pID][name] = true;

        //fire event
        emit eveDefaultPlayer(_pID, addr, name);
    }

    /**
     * @dev set refer reward rate
     */
    function setReferRewardRate(
        uint256 refer1Rate,
        uint256 refer2Rate,
        uint256 feeRate
    ) public onlyOwner {
        _refer1RewardRate = refer1Rate;
        _refer2RewardRate = refer2Rate;
        _feeRate = feeRate;
        emit eveSetRewardRate(refer1Rate, refer2Rate, feeRate);
    }

    /**
     * @dev set aigc contract address
     */
    function setAigcContract(address aigc) public onlyOwner {
        _aigc = IERC20(aigc);
    }

    /**
     * @dev set teamWallet address
     */
    function setTeamWallet(address payable teamWallet) public onlyOwner {
        _teamWallet = teamWallet;
    }

    /**
     * @dev registers a name.  UI will always display the last name you registered.
     * but you will still own all previously registered names to use as affiliate
     * links.
     * - must pay a registration fee.
     * - name must be unique
     * - names will be converted to lowercase
     * - cannot be only numbers
     * - cannot start with 0x
     * - name must be at least 1 char
     * - max length of 32 characters long
     * - allowed characters: a-z, 0-9
     * -functionhash- 0x921dec21 (using ID for affiliate)
     * -functionhash- 0x3ddd4698 (using address for affiliate)
     * -functionhash- 0x685ffd83 (using name for affiliate)
     * @param nameString players desired name
     * @param affCode affiliate name of who refered you
     * (this might cost a lot of gas)
     */

    function registerNameXName(
        string memory nameString,
        string memory affCode
    ) external {
        uint256 registrationFee = this.getRegistrationFee();
        if (registrationFee > 0) {
            _aigc.safeTransferFrom(
                msg.sender,
                address(this),
                this.getRegistrationFee()
            );
            _totalRegisterFee += registrationFee;
        }

        // filter name + condition checks
        bytes32 name = NameFilter.nameFilter(nameString);
        // if names already has been used
        require(_pIDxName[name] == 0, "sorry that names already taken");

        // set up address
        address addr = msg.sender;
        // set up our tx event data and determine if player is new or not

        // _determinePID(addr);
        // // fetch player id
        // uint256 pID = _pIDxAddr[addr];
        uint256 pID = _determinePID(addr);
        // if names already has been used
        require(
            _plyrNames[pID][name] == false,
            "sorry that names already taken"
        );

        // add name to player profile, registry, and name book
        _plyrNames[pID][name] = true;
        _pIDxName[name] = pID;
        _plyr[pID].name = name;
        _plyr[pID].nameCount++;

        _totalRegisterCount++;

        //try bind a refer
        if (_plyr[pID].laff == 0) {
            bytes memory tempCode = bytes(affCode);
            bytes32 affName = 0x0;
            if (tempCode.length >= 0) {
                assembly {
                    affName := mload(add(tempCode, 32))
                }
            }

            _bindRefer(addr, affName);
        }
        uint256 affID = _plyr[pID].laff;

        // fire event
        emit eveNewName(
            pID,
            addr,
            name,
            affID,
            _plyr[affID].addr,
            _plyr[affID].name
        );
    }

    /**
     * @dev bind a refer,if affcode invalid, use default refer
     */
    function bindRefer(
        address from,
        string calldata affCode
    ) external override isRegisteredPool returns (bool) {
        bytes memory tempCode = bytes(affCode);
        bytes32 affName = 0x0;
        if (tempCode.length >= 0) {
            assembly {
                affName := mload(add(tempCode, 32))
            }
        }

        return _bindRefer(from, affName);
    }

    /**
     * @dev bind a refer,if affcode invalid, use default refer
     */
    function _bindRefer(
        address from,
        bytes32 name
    ) private validAddress(msg.sender) validAddress(from) returns (bool) {
        // set up our tx event data and determine if player is new or not
        // _determinePID(from);

        // // fetch player id
        // uint256 pID = _pIDxAddr[from];
        uint256 pID = _determinePID(from);
        if (_plyr[pID].laff != 0) {
            return false;
        }

        if (_pIDxName[name] == 0) {
            //unregister name
            name = _defaulRefer;
        }

        uint256 affID = _pIDxName[name];
        if (affID == pID) {
            affID = _pIDxName[_defaulRefer];
        }

        _plyr[pID].laff = affID;

        //lvcount
        _plyr[affID].lv1Count++;
        uint256 aff_affID = _plyr[affID].laff;
        if (aff_affID != 0) {
            _plyr[aff_affID].lv2Count++;
        }

        // fire event
        emit eveBindRefer(
            pID,
            from,
            name,
            affID,
            _plyr[affID].addr,
            _plyr[affID].name
        );

        return true;
    }

    function _determinePID(address addr) private returns (uint256) {
        if (_pIDxAddr[addr] == 0) {
            _pID++;
            _pIDxAddr[addr] = _pID;
            _plyr[_pID].addr = addr;
            return _pID;
        } else {
            return _pIDxAddr[addr];
        }
    }

    function hasRefer(
        address from
    ) external override isRegisteredPool returns (bool) {
        uint256 pID = _determinePID(from);
        return (_plyr[pID].laff > 0);
    }

    function getPlayerInfo(
        address from
    )
        external
        view
        returns (bytes32, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        uint256 pID = _pIDxAddr[from];
        if (_pID == 0) {
            return (0, 0, 0, 0, 0, 0, 0);
        }
        return (
            _plyr[pID].name,
            _plyr[pID].laff,
            _plyr[_plyr[pID].laff].laff,
            _plyr[pID].rreward,
            _plyr[pID].allReward,
            _plyr[pID].lv1Count,
            _plyr[pID].lv2Count
        );
    }

    function getRegistrationFee() external view returns (uint256) {
        if (_pID <= _freeAmount) {
            return 0;
        } else {
            return _aigc.totalSupply().mul(_feeRate).div(_baseRate);
        }
    }

    function withdrawRegisterFee() external onlyOwner {
        _aigc.safeTransfer(_teamWallet, _totalRegisterFee);
        emit eveWithdrawFee(_totalRegisterFee);
    }

    function transferReferrer(address newReferrer) external {
        uint256 pID = _pIDxAddr[msg.sender];
        require(pID != 0, "not register");
        require(_plyr[pID].name != bytes32(0), "No registered name!");
        _plyr[pID].addr = newReferrer;
        uint256 newPID = _pIDxAddr[newReferrer];
        require(newPID == 0, "newReferrer is bound!!");
        _pIDxAddr[newReferrer] = pID;
        _pIDxAddr[msg.sender] = 0;
        emit TransferReferrer(pID, newReferrer);
    }
}
