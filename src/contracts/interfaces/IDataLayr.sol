// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayr {
    function initDataStore(
        uint32 dumpNumber,
        bytes32 headerHash,
        uint32 totalBytes,
        uint32 storePeriodLength,
        uint32 stakesBlockNumber,
        bytes calldata header
    ) external;

    function confirm(
        uint32 dumpNumber,
        bytes32 headerHash,
        uint256 ethStakeSigned,
        uint256 eigenStakeSigned,
        uint256 totalEthStake,
        uint256 totalEigenStake
    ) external;

    function dataStores(bytes32)
        external
        view
        returns (
            uint32 dumpNumber,
            uint32 initTime,
            uint32 storePeriodLength,
            uint32 blockNumber
        );
}
