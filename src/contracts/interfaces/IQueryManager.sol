// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IFeeManager.sol";
import "./IvoteWeigher.sol";
import "../interfaces/ITimelock_Managed.sol";

interface IQueryManager is ITimelock_Managed {
    // struct for storing the amount of Eigen and ETH that has been staked
    struct Stake {
        uint128 eigenStaked;
        uint128 ethStaked;
    }

    function operatorCounts() external view returns(uint256);

    function getOpertorCount() external view returns(uint32);

    function getOpertorCountOfType(uint8) external view returns(uint32);

    function consensusLayerEthToEth() external view returns (uint256);

    function totalEigenStaked() external view returns (uint128);

    function createNewQuery(bytes calldata) external;

    function getQueryDuration() external view returns (uint256);

    function getQueryCreationTime(bytes32) external view returns (uint256);

    function getOperatorType(address) external view returns (uint8);

    function numRegistrants() external view returns (uint256);

    function voteWeigher() external view returns (IvoteWeigher);

    function feeManager() external view returns (IFeeManager);

    function updateStake(address)
        external
        returns (
            uint128,
            uint128
        );

    function eigenStakedByOperator(address) external view returns (uint128);

    function ethStakedByOperator(address) external view returns (uint128);

    function totalEthStaked() external view returns (uint128);

    function ethAndEigenStakedForOperator(address)
        external
        view returns (uint128, uint128);

    function operatorStakes(address) external view returns (uint128, uint128);

    function totalStake() external view returns (uint128, uint128);

    function register(bytes calldata data) external;

    function deregister(bytes calldata data) external;
}
