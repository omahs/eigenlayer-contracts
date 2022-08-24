// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../contracts/libraries/BytesLib.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";



import "../test/Delegation.t.sol";



contract Payments is Delegator {
    using BytesLib for bytes;
    using Math for uint;




    constructor() {
    }


    function testRewardPayouts(
            uint256 ethAmount, 
            uint256 eigenAmount
        ) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        //G2 coordinates for aggregate PKs for 15 signers
        apks.push(
            uint256(
                20820493588973199354272631301248587752629863429201347184003644368113679196121
            )
        );
        apks.push(
            uint256(
                18507428821816114421698399069438744284866101909563082454551586195885282320634
            )
        );
        apks.push(
            uint256(
                1263326262781780932600377484793962587101562728383804037421955407439695092960
            )
        );
        apks.push(
            uint256(
                3512517006108887301063578607317108977425754510174956792003926207778790018672
            )
        );

        //15 signers' associated sigma
        sigmas.push(
            uint256(
                17495938995352312074042671866638379644300283276197341589218393173802359623203
            )
        );
        sigmas.push(
            uint256(
                9126369385140686627953696969589239917670210184443620227590862230088267251657
            )
        );

        address operator = signers[0];
        _testInitiateDelegation(operator, eigenAmount, ethAmount);
        _payRewards(operator);
        
    }



    //internal helpers
    function _payRewards(address operator) internal {
        uint120 amountRewards = 10;

        //Operator submits claim to rewards

        _testCommitPayment(operator, amountRewards);


        

        //initiate challenge
        _testInitPaymentChallenge(operator, 5, 3);

    }


    //Operator submits claim or commit for a payment amount
    function _testCommitPayment(address operator, uint120 _amountRewards)
        internal
    {
        uint32 numberOfSigners = 15;
        _testRegisterSigners(numberOfSigners, false);

        uint32 blockNumber;
        // scoped block helps fix 'stack too deep' errors
        {
            uint256 initTime = 1000000001;
            IDataLayrServiceManager.DataStoreSearchData
                memory searchData = _testInitDataStore(initTime, address(this));
            uint32 numberOfNonSigners = 0;

            blockNumber = uint32(block.number);
            uint32 dataStoreId = dlsm.taskNumber() - 1;
            _testCommitDataStore(
                keccak256(abi.encodePacked(searchData.metadata.globalDataStoreId, searchData.metadata.headerHash, searchData.duration, initTime, uint32(0))),
                numberOfNonSigners,
                apks,
                sigmas,
                searchData.metadata.blockNumber,
                dataStoreId,
                searchData
            );
            // bytes32 sighash = dlsm.getDataStoreIdSignatureHash(dlsm.taskNumber() - 1);
            // assertTrue(sighash != bytes32(0), "Data store not committed");
        }
        cheats.stopPrank();

        uint8 duration = 2;

        // // try initing another dataStore, so currentDataStoreId > fromDataStoreId
        // _testInitDataStore();
        bytes memory header = hex"0102030405060708091011121314151617181921";
        uint32 totalBytes = 1e6;
        // uint32 storePeriodLength = 600;

        //weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);
        dataLayrPaymentManager.depositFutureFees(storer, 1e11);
        blockNumber = 1;
        dlsm.initDataStore(storer, address(this), header, duration, totalBytes, blockNumber);
        cheats.stopPrank();

        cheats.startPrank(operator);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        // uint256 fromDataStoreId = IQuorumRegistryWithBomb(address(dlsm.repository().voteWeigher())).getFromDataStoreIdForOperator(operator);
        uint32 newCurrentDataStoreId = dlsm.taskNumber() - 1;
        dataLayrPaymentManager.commitPayment(
            newCurrentDataStoreId,
            _amountRewards
        );
        cheats.stopPrank();
        //assertTrue(weth.balanceOf(address(dt)) == currBalance + amountRewards, "rewards not transferred to delegation terms contract");
    }

        //initiates the payment challenge from the challenger, with split that the challenger thinks is correct
    function _testInitPaymentChallenge(
        address operator,
        uint120 amount1,
        uint120 amount2
    ) internal {
        cheats.startPrank(_challenger);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        //challenger initiates challenge
        dataLayrPaymentManager.challengePaymentInit(operator, amount1, amount2);

        // DataLayrPaymentManager.PaymentChallenge memory _paymentChallengeStruct = dataLayrPaymentManager.operatorToPaymentChallenge(operator);
        cheats.stopPrank();
    }

}
