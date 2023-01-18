// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../contracts/libraries/BN254.sol";
import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

contract Owners is Test {
    string internal ownersConfigJson;
    address[] addresses;

    constructor() {
        ownersConfigJson = vm.readFile("./src/test/test-data/owners.json");
    }

    function ownerPrefix(uint256 index) public returns(string memory) {
        return string.concat(".operators[", string.concat(vm.toString(index), "]."));
    }

    function getNumOperators() public returns(uint256) {
        return stdJson.readUint(ownersConfigJson, ".numOwners");
    }

    function getOwnerAddress(uint256 index) public returns(address) {
        return stdJson.readAddress(ownersConfigJson, string.concat(ownerPrefix(index), "Address"));
    }

    function getOwnerAddresses() public returns(address[] memory) {
        for (uint256 i = 0; i < getNumOperators(); i++) {
            addresses.push(getOwnerAddress(i));
        }
        return addresses;    
    }
}
