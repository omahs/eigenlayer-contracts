// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IFeeManager.sol";
import "./IVoteWeighter.sol";

interface IQueryManager {
    function timelock() external view returns (address);

    function operatorCounts() external view returns(uint256);

    function consensusLayerEthToEth() external view returns (uint256);

    function totalEigenStaked() external view returns (uint128);

    function createNewQuery(bytes calldata queryData) external;

    function getQueryDuration() external view returns (uint256);

    function getQueryCreationTime(bytes32) external view returns (uint256);

    function getOperatorType(address) external view returns (uint8);

    function numRegistrants() external view returns (uint256);

    function voteWeighter() external view returns (IVoteWeighter);

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
}