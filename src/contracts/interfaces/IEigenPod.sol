// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IEigenPodManager.sol";
import "./IBeaconChainOracle.sol";

/**
 * @title Interface for solo staking pods that have their withdrawal credentials pointed to EigenLayer.
 * @author Layr Labs, Inc.
 */

interface IEigenPod {
    struct Validator {
        VALIDATOR_STATUS status;
        uint64 balance; //ethpos stake in gwei
    }

    enum VALIDATOR_STATUS {
        INACTIVE, //doesnt exist
        ACTIVE //staked on ethpos and withdrawal credentials are pointed
    }

    function initialize(IEigenPodManager _eigenPodManager, address _owner) external;
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;
    function withdrawETH(address recipient, uint256 amount) external;
}
