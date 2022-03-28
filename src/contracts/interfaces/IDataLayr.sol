// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayr {
    function initDataStore(
        uint64 dumpNumber,
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength,
        address submitter
    ) external;

    function confirm(
        uint256 dumpNumber,
        bytes32 ferkleRoot,
        address submitter,
        uint128 ethStakeSigned,
        uint128 eigenStakeSigned
    ) external;
}