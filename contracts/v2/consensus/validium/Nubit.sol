// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

import "../../interfaces/IPolygonDataCommitteeErrors.sol";
import "../../interfaces/IDataAvailabilityProtocol.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/*
 * Contract responsible managing the data committee that will verify that the data sent for a validium is singed by a committee
 * It is advised to give the owner of the contract to a timelock contract once the data committee is set
 */
contract Nubit is
IDataAvailabilityProtocol,
IPolygonDataCommitteeErrors,
OwnableUpgradeable
{
    /**
     * @notice Struct which will store all the data of the committee members
     * @param url string that represents the URL of the member to be used to access the data
     * @param addr address of the member that will be used to sign
     */
    struct Member {
        string url;
        address addr;
    }

    // Name of the data availability protocol
    string internal constant _PROTOCOL_NAME = "Nubit";

    // Size of a signature in bytes
    uint256 internal constant _SIGNATURE_SIZE = 65;

    // Size of an address in bytes
    uint256 internal constant _ADDR_SIZE = 20;

    // Specifies the required amount of signatures from members in the data availability committee
    uint256 public requiredAmountOfSignatures;

    // Hash of the addresses of the committee
    bytes32 public committeeHash;

    // Register of the members of the committee
    Member[] public members;

    /**
     * @dev Emitted when the committee is updated
     * @param committeeHash hash of the addresses of the committee members
     */
    event CommitteeUpdated(bytes32 committeeHash);

    /**
     * Disable initalizers on the implementation following the best practices
     */
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        // Initialize OZ contracts
        __Ownable_init_unchained();
    }

    /**
     * @notice Allows the admin to setup the members of the committee. Note that:
     * The system will require N / M signatures where N => _requiredAmountOfSignatures and M => urls.length
     * There must be the same amount of urls than addressess encoded in the addrsBytes
     * A member is represented by the url and the address contained in urls[i] and addrsBytes[i*_ADDR_SIZE : i*_ADDR_SIZE + _ADDR_SIZE]
     * @param _requiredAmountOfSignatures Required amount of signatures
     * @param urls List of urls of the members of the committee
     * @param addrsBytes Byte array that contains the addressess of the members of the committee
     */
    function setupCommittee(
        uint256 _requiredAmountOfSignatures,
        string[] calldata urls,
        bytes calldata addrsBytes
    ) external onlyOwner {
        uint256 membersLength = urls.length;
        if (membersLength < _requiredAmountOfSignatures) {
            revert TooManyRequiredSignatures();
        }
        if (addrsBytes.length != membersLength * _ADDR_SIZE) {
            revert UnexpectedAddrsBytesLength();
        }

        // delete previous member array
        delete members;

        address lastAddr;
        for (uint256 i = 0; i < membersLength; i++) {
            uint256 currentAddresStartingByte = i * _ADDR_SIZE;
            address currentMemberAddr = address(
                bytes20(
                    addrsBytes[currentAddresStartingByte:currentAddresStartingByte +
                    _ADDR_SIZE]
                )
            );

            // Check url is not empty
            if (bytes(urls[i]).length == 0) {
                revert EmptyURLNotAllowed();
            }

            // Addresses must be setup in incremental order, in order to easily check duplicated address
            if (lastAddr >= currentMemberAddr) {
                revert WrongAddrOrder();
            }
            members.push(Member({url: urls[i], addr: currentMemberAddr}));

            lastAddr = currentMemberAddr;
        }

        committeeHash = keccak256(addrsBytes);
        requiredAmountOfSignatures = _requiredAmountOfSignatures;
        emit CommitteeUpdated(committeeHash);
    }

    /**
     * @notice Verifies that the given signedHash has been signed by requiredAmountOfSignatures committee members
     * @param signedHash Hash that must have been signed by requiredAmountOfSignatures of committee members
     * @param signaturesAndAddrs Byte array containing the signatures and all the addresses of the committee in ascending order
     * [signature 0, ..., signature requiredAmountOfSignatures -1, address 0, ... address N]
     * note that each ECDSA signatures are used, therefore each one must be 65 bytes
     */
    function verifyMessage(
        bytes32 signedHash,
        bytes calldata signaturesAndAddrs
    ) external view {
        bytes32 msg_hash;
        bytes memory _signature;
        assembly {
            let ptr := add(signaturesAndAddrs.offset, 32)
            let len := calldataload(signaturesAndAddrs.offset)
            msg_hash := calldataload(ptr)
            _signature := mload(0x40)
            calldatacopy(add(_signature, 32), add(ptr, 32), sub(len, 32))
        }

        uint256 membersLength = members.length;
        address _signer = ECDSA.recover(msg_hash, _signature);
        bool rev=true;
        for (uint256 i = 0; i < membersLength; i++) {
            if (members[i].addr == _signer)
                rev=false;
        }
        if (rev)
            revert("InvalidSig");
    }

    /**
     * @notice Return the amount of committee members
     */
    function getAmountOfMembers() public view returns (uint256) {
        return members.length;
    }

    /**
     * @notice Return the protocol name
     */
    function getProcotolName() external pure override returns (string memory) {
        return _PROTOCOL_NAME;
    }
}
