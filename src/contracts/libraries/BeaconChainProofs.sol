// SPDX-License-Identifier: UNLICENCED

pragma solidity ^0.8.9;

import "./Merkle.sol";
import "./BytesLib.sol";

//TODO: Validate this entire library

//Utility library for parsing and PHASE0 beacon chain block headers
//SSZ Spec: https://github.com/ethereum/consensus-specs/blob/dev/ssz/simple-serialize.md#merkleization
//BeaconBlockHeader Spec: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#beaconblockheader
//BeaconState Spec: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#beaconstate
library BeaconChainProofs {
    using BytesLib for bytes;
    uint256 public constant NUM_BEACON_BLOCK_HEADER_FIELDS = 5;
    uint256 public constant BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT = 3;

    uint256 public constant NUM_BEACON_STATE_FIELDS = 21;
    uint256 public constant BEACON_STATE_FIELD_TREE_HEIGHT = 5;

    uint256 public constant NUM_ETH1_DATA_FIELDS = 3;
    uint256 public constant ETH1_DATA_FIELD_TREE_HEIGHT = 2;

    uint256 public constant NUM_VALIDATOR_FIELDS = 8;
    uint256 public constant VALIDATOR_FIELD_TREE_HEIGHT = 3;

    uint256 public constant VALIDATOR_TREE_HEIGHT = 40;

    //in beacon block header
    uint256 public constant STATE_ROOT_INDEX = 3;
    uint256 public constant PROPOSER_INDEX_INDEX = 1;
    //in beacon state
    uint256 public constant ETH_1_ROOT_INDEX = 8;
    uint256 public constant VALIDATOR_TREE_ROOT_INDEX = 11;

    //TODO: Merklization can be optimized by supplying zero hashes. later on tho
    function computePhase0BeaconBlockHeaderRoot(bytes32[NUM_BEACON_BLOCK_HEADER_FIELDS] calldata blockHeaderFields) internal pure returns(bytes32) {
        bytes32[] memory paddedHeaderFields = new bytes32[](2**BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT);
        
        for (uint i = 0; i < NUM_BEACON_BLOCK_HEADER_FIELDS; i++) {
            paddedHeaderFields[i] = blockHeaderFields[i];
        }

        return Merkle.merkleizeSha256(BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT, paddedHeaderFields);
    }

    function computePhase0BeaconStateRoot(bytes32[NUM_BEACON_STATE_FIELDS] calldata beaconStateFields) internal pure returns(bytes32) {
        bytes32[] memory paddedBeaconStateFields = new bytes32[](2**BEACON_STATE_FIELD_TREE_HEIGHT);
        
        for (uint i = 0; i < NUM_BEACON_STATE_FIELDS; i++) {
            paddedBeaconStateFields[i] = beaconStateFields[i];
        }
        
        return Merkle.merkleizeSha256(BEACON_STATE_FIELD_TREE_HEIGHT, paddedBeaconStateFields);
    }

    function computePhase0ValidatorRoot(bytes32[NUM_VALIDATOR_FIELDS] calldata validatorFields) internal pure returns(bytes32) {  
        bytes32[] memory paddedValidatorFields = new bytes32[](2**VALIDATOR_FIELD_TREE_HEIGHT);
        
        for (uint i = 0; i < NUM_VALIDATOR_FIELDS; i++) {
            paddedValidatorFields[i] = validatorFields[i];
        }

        return Merkle.merkleizeSha256(VALIDATOR_FIELD_TREE_HEIGHT, paddedValidatorFields);
    }

    function computePhase0Eth1DataRoot(bytes32[NUM_ETH1_DATA_FIELDS] calldata eth1DataFields) internal pure returns(bytes32) {  
        bytes32[] memory paddedEth1DataFields = new bytes32[](2**ETH1_DATA_FIELD_TREE_HEIGHT);
        
        for (uint i = 0; i < ETH1_DATA_FIELD_TREE_HEIGHT; i++) {
            paddedEth1DataFields[i] = eth1DataFields[i];
        }

        return Merkle.merkleizeSha256(ETH1_DATA_FIELD_TREE_HEIGHT, paddedEth1DataFields);
    }

    function verifyValidatorFields(
        bytes32 beaconStateRoot, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) internal pure {
        //offset 32 bytes for validatorTreeRoot
        uint256 pointer;
        bool valid;
        //verify that the validatorTreeRoot is within the top level beacon state tree
        bytes32 validatorTreeRoot = proofs.toBytes32(0);
        valid = Merkle.checkMembershipSha256(
            validatorTreeRoot,
            BeaconChainProofs.VALIDATOR_TREE_ROOT_INDEX,
            beaconStateRoot,
            proofs.slice(pointer, 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT)
        );
        require(valid, "EigenPod.proveCorrectWithdrawalCredentials: Invalid validator tree root from beacon state proof");
        //offset the length of the beacon state proof
        pointer += 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT;
        // verify the proof of the validator metadata root against the merkle root of the entire validator tree
        //https://github.com/prysmaticlabs/prysm/blob/de8e50d8b6bcca923c38418e80291ca4c329848b/beacon-chain/state/stateutil/validator_root.go#L26
        bytes32 validatorRoot = proofs.toBytes32(pointer);
        //offset another 4 bytes for the length of the validatorIndex
        pointer += 32;
        //verify that the validatorRoot is within the validator tree
        valid = Merkle.checkMembershipSha256(
            validatorRoot,
            proofs.toUint32(pointer), //validatorIndex
            validatorTreeRoot,
            proofs.slice(pointer, 32 * BeaconChainProofs.VALIDATOR_TREE_HEIGHT)
        );
        //offset another 4 bytes for the length of the validatorIndex
        pointer += 4;
        require(valid, "EigenPod.proveCorrectWithdrawalCredentials: Invalid validator root from validator tree root proof");
        //make sure that the provided validatorFields are consistent with the proven leaf
        require(validatorRoot == Merkle.merkleizeSha256(BeaconChainProofs.VALIDATOR_FIELD_TREE_HEIGHT, validatorFields), "EigenPod.proveCorrectWithdrawalCredentials: Invalid validator fields");
    }
}