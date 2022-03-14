// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/**
 * @title DataLayr
 * @dev L1 contracts that handles DataLayr Node registration
 *
 */

interface IDataLayr {
    function initDataStore(
        uint64 dumpNumber,
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength,
        address submitter,
        uint24 quorum
    ) external payable;

    function confirm(
        uint64 dumpNumber,
        bytes32 ferkleRoot,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint8[] calldata vs
    ) external payable;
}

interface IDataLayrVoteWeigher {
    function setLatestTime(uint32) external;

    function getOperatorFromDumpNumber(address) external view returns (uint48);
}

interface IDataLayrServiceManager {
    function dumpNumber() external returns (uint48);

    function getDumpNumberFee(uint48) external returns (uint256);

    function getDumpNumberSignatureHash(uint48) external returns (bytes32);

    function resolvePaymentChallenge(address, bool) external;

    function paymentFraudProofInterval() external returns (uint256);

    function paymentFraudProofCollateral() external returns (uint256);

    function getPaymentCollateral(address) external returns (uint256);
}
