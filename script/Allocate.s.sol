// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./EigenLayerParser.sol";

contract Allocate is
    Script,
    DSTest,
    EigenLayerParser
{
    //performs basic deployment before each test
    function run() external {
        // read meta data from json
        parseEigenLayerParams();

        uint256 wethAmount = eigenTotalSupply / (numStaker + numDis + 50); // save 100 portions
        vm.startBroadcast();
        // deployer allocate weth, eigen to staker
        for (uint i = 0; i < numStaker ; ++i) {
            address stakerAddr = stdJson.readAddress(configJson, string.concat(".staker[", string.concat(vm.toString(i), "].address")));
            weth.transfer(stakerAddr, wethAmount);
            eigen.transfer(stakerAddr, wethAmount);
            emit log("stakerAddr");
            emit log_address(stakerAddr);
        }
        // deployer allocate weth, eigen to disperser
        for (uint i = 0; i < numDis ; ++i) {
            address disAddr = stdJson.readAddress(configJson, string.concat(".dis[", string.concat(vm.toString(i), "].address")));    
            weth.transfer(disAddr, wethAmount);
            emit log("disAddr");
            emit log_address(disAddr);
        }

        vm.stopBroadcast();
    }
}

contract ProvisionWeth is
    Script,
    DSTest,
    EigenLayerParser
{
    uint256 wethAmount = 100000000000000000000;
    //performs basic deployment before each test
    function run() external {
        vm.startBroadcast();
        // read meta data from json
        addressJson = vm.readFile("contract.addresses");
        weth = IERC20(stdJson.readAddress(addressJson, ".weth"));
        address dlsm = stdJson.readAddress(addressJson, ".dlsm");
        // deployer allocate weth, eigen to disperser
        configJson = vm.readFile("recipient.json");
        uint256 recipientPrivKey = stdJson.readUint(configJson, string.concat(".private"));
        address recipientAddr = cheats.addr(recipientPrivKey);        
        weth.transfer(recipientAddr, wethAmount);
        payable(recipientAddr).transfer(1 ether);
        vm.stopBroadcast();
        //approve dlsm
        vm.broadcast(recipientPrivKey);
        weth.approve(dlsm, type(uint256).max);
    }
}

