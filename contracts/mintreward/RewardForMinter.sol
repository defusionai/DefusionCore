pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../library/ECDSA.sol";
import "../library/EIP712.sol";

interface IMedalNFT {
    function mint(address to) external returns (uint256);
}

/**
 * @title RewardForMinter
 * @author Defusion Protocol
 */
contract RewardForMinter is EIP712, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    bool private initialized;
    address public signer;
    address public medalNFT;

    mapping(uint256 => uint256) public numClaimed;
    mapping(uint256 => bool) public isClaimed;

    event UpdateSigner(address signer);

    event EventClaim(
        uint256 nftID,
        uint256 pid,
        uint256 dummyId,
        address mintTo
    );

    constructor() EIP712("DefusionAi", "1.0.0") {}

    function initialize(
        address _owner,
        address _signer,
        address _medalNFT
    ) external {
        require(!initialized, "initialize: Already initialized!");
        _transferOwnership(_owner);
        eip712Initialize("DefusionAi", "1.0.0");
        signer = _signer;
        medalNFT = _medalNFT;
        initialized = true;
    }

    function claimHash(
        uint256 _pid,
        uint256 _dummyId,
        address _to
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "Claim(uint256 pid,uint256 dummyId,address mintTo)"
                        ),
                        _pid,
                        _dummyId,
                        _to
                    )
                )
            );
    }

    function verifySignature(
        bytes32 hash,
        bytes calldata signature
    ) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == signer;
    }

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
        emit UpdateSigner(_signer);
    }

    function claim(
        uint256 _pid,
        uint256 _dummyId,
        address _mintTo,
        bytes calldata _signature
    ) external nonReentrant returns (uint256) {
        require(!isClaimed[_dummyId], "Already Claimed!");

        require(
            verifySignature(claimHash(_pid, _dummyId, _mintTo), _signature),
            "Invalid signature"
        );
        isClaimed[_dummyId] = true;

        uint256 nftID_ = IMedalNFT(medalNFT).mint(msg.sender);

        numClaimed[_pid]++;

        emit EventClaim(nftID_, _pid, _dummyId, _mintTo);

        return nftID_;
    }
}
