// //SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "../contracts/interfaces/IEigenPod.sol";
import "../contracts/interfaces/IBLSPublicKeyCompendium.sol";
import "../contracts/middleware/BLSPublicKeyCompendium.sol";
import "../contracts/pods/EigenPodPaymentEscrow.sol";
import "./utils/BeaconChainUtils.sol";
import "./utils/ProofParsing.sol";
import "./EigenLayerDeployer.t.sol";
import "./mocks/MiddlewareRegistryMock.sol";
import "./mocks/ServiceManagerMock.sol";
import "../contracts/libraries/BeaconChainProofs.sol";
import "./mocks/BeaconChainOracleMock.sol";


contract EigenPodTests is BeaconChainProofUtils, ProofParsing, EigenPodPausingConstants {
    using BytesLib for bytes;

    uint256 internal constant GWEI_TO_WEI = 1e9;

    bytes pubkey = hex"88347ed1c492eedc97fc8c506a35d44d81f27a0c7a1c661b35913cfd15256c0cccbd34a83341f505c7de2983292f2cab";
    uint40 validatorIndex0 = 0;
    uint40 validatorIndex1 = 1;
    //hash tree root of list of validators
    bytes32 validatorTreeRoot;

    //hash tree root of individual validator container
    bytes32 validatorRoot;

    address podOwner = address(42000094993494);

    Vm cheats = Vm(HEVM_ADDRESS);
    EigenLayerDelegation public delegation;
    IInvestmentManager public investmentManager;
    Slasher public slasher;
    PauserRegistry public pauserReg;

    ProxyAdmin public eigenLayerProxyAdmin;
    IBLSPublicKeyCompendium public blsPkCompendium;
    IEigenPodManager public eigenPodManager;
    IEigenPod public podImplementation;
    IEigenPodPaymentEscrow public eigenPodPaymentEscrow;
    IETHPOSDeposit public ethPOSDeposit;
    IBeacon public eigenPodBeacon;
    IBeaconChainOracleMock public beaconChainOracle;
    MiddlewareRegistryMock public generalReg1;
    ServiceManagerMock public generalServiceManager1;
    address[] public slashingContracts;
    address pauser = address(69);
    address unpauser = address(489);
    address podManagerAddress = 0x212224D2F2d262cd093eE13240ca4873fcCBbA3C;
    address podAddress = address(123);
    uint256 stakeAmount = 32e18;
    mapping (address => bool) fuzzedAddressMapping;
    bytes signature;
    bytes32 depositDataRoot;

    bytes32[] withdrawalFields;
    bytes32[] validatorFields;

    event EigenPodStaked(bytes pubkey);
    event PaymentCreated(address podOwner, address recipient, uint256 amount, uint256 index);




    modifier fuzzedAddress(address addr) virtual {
        cheats.assume(fuzzedAddressMapping[addr] == false);
        _;
    }


    uint32 PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS = 7 days / 12 seconds;
    uint256 REQUIRED_BALANCE_WEI = 31 ether;

    //performs basic deployment before each test
    function setUp() public {
        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayerProxyAdmin = new ProxyAdmin();

        // deploy pauser registry
        pauserReg = new PauserRegistry(pauser, unpauser);

        blsPkCompendium = new BLSPublicKeyCompendium();

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        EmptyContract emptyContract = new EmptyContract();
        delegation = EigenLayerDelegation(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        investmentManager = InvestmentManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        slasher = Slasher(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        eigenPodPaymentEscrow = EigenPodPaymentEscrow(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );

        ethPOSDeposit = new ETHPOSDepositMock();
        podImplementation = new EigenPod(
                ethPOSDeposit, 
                eigenPodPaymentEscrow,
                IEigenPodManager(podManagerAddress),
                REQUIRED_BALANCE_WEI
        );
        eigenPodBeacon = new UpgradeableBeacon(address(podImplementation));

        // this contract is deployed later to keep its address the same (for these tests)
        eigenPodManager = EigenPodManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        EigenLayerDelegation delegationImplementation = new EigenLayerDelegation(investmentManager, slasher);
        InvestmentManager investmentManagerImplementation = new InvestmentManager(delegation, IEigenPodManager(podManagerAddress), slasher);
        Slasher slasherImplementation = new Slasher(investmentManager, delegation);
        EigenPodManager eigenPodManagerImplementation = new EigenPodManager(ethPOSDeposit, eigenPodBeacon, investmentManager, slasher);

        //ensuring that the address of eigenpodmanager doesn't change
        bytes memory code = address(eigenPodManager).code;
        cheats.etch(podManagerAddress, code);
        eigenPodManager = IEigenPodManager(podManagerAddress);

        beaconChainOracle = new BeaconChainOracleMock();
        EigenPodPaymentEscrow eigenPodPaymentEscrowImplementation = new EigenPodPaymentEscrow(IEigenPodManager(podManagerAddress));

        address initialOwner = address(this);
        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegation))),
            address(delegationImplementation),
            abi.encodeWithSelector(EigenLayerDelegation.initialize.selector, pauserReg, initialOwner)
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(investmentManager))),
            address(investmentManagerImplementation),
            abi.encodeWithSelector(InvestmentManager.initialize.selector, pauserReg, initialOwner, 0)
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(Slasher.initialize.selector, pauserReg, initialOwner)
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(EigenPodManager.initialize.selector, beaconChainOracle, initialOwner, pauserReg, 0)
        );
        uint256 initPausedStatus = 0;
        uint256 withdrawalDelayBlocks = PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS;
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodPaymentEscrow))),
            address(eigenPodPaymentEscrowImplementation),
            abi.encodeWithSelector(EigenPodPaymentEscrow.initialize.selector, initialOwner, pauserReg, initPausedStatus, withdrawalDelayBlocks)
        );
        generalServiceManager1 = new ServiceManagerMock(slasher);

        generalReg1 = new MiddlewareRegistryMock(
             generalServiceManager1,
             investmentManager
        );

        cheats.deal(address(podOwner), 5*stakeAmount);     

        fuzzedAddressMapping[address(0)] = true;
        fuzzedAddressMapping[address(eigenLayerProxyAdmin)] = true;
        fuzzedAddressMapping[address(investmentManager)] = true;
        fuzzedAddressMapping[address(eigenPodManager)] = true;
        fuzzedAddressMapping[address(delegation)] = true;
        fuzzedAddressMapping[address(slasher)] = true;
        fuzzedAddressMapping[address(generalServiceManager1)] = true;
        fuzzedAddressMapping[address(generalReg1)] = true;
    }

    function testStaking() public {
        cheats.startPrank(podOwner);
        cheats.expectEmit(true, false, false, false);
        emit EigenPodStaked(pubkey);
        eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
        cheats.stopPrank();
    }

    function testWithdrawFromPod() public {
        cheats.startPrank(podOwner);
        eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        IEigenPod pod = eigenPodManager.getPod(podOwner);
        uint256 balance = address(pod).balance;
        cheats.deal(address(pod), stakeAmount);

        cheats.startPrank(podOwner);
        cheats.expectEmit(true, false, false, false);
        emit PaymentCreated(podOwner, podOwner, balance, eigenPodPaymentEscrow.userPaymentsLength(podOwner));
        pod.withdrawBeforeRestaking();
        cheats.stopPrank();
        require(address(pod).balance == 0, "Pod balance should be 0");
    }

    function testAttemptedWithdrawalAfterVerifyingWithdrawalCredentials() public {
        testDeployAndVerifyNewEigenPod();
        IEigenPod pod = eigenPodManager.getPod(podOwner);
        cheats.startPrank(podOwner);
        cheats.expectRevert(bytes("EigenPod.hasNeverRestaked: restaking is enabled"));
        IEigenPod(pod).withdrawBeforeRestaking();
        cheats.stopPrank();
    }

    function testProof() public {
        BeaconChainProofs.WithdrawalProofs memory proofs = _getWithdrawalProof();
        withdrawalFields = getWithdrawalFields();   
        validatorFields = getValidatorFields();

        Relayer relay = new Relayer();

        bytes32 beaconStateRoot = getBeaconStateRoot();
        relay.verifyBlockNumberAndWithdrawalFields(beaconStateRoot, proofs, withdrawalFields);

    }

    function testFullWithdrawalFlow() public {
        //this call is to ensure that validatorContainerFields and validatorMerkleProof in BeaconChainUtils get set
        setJSON("./src/test/test-data/withdrawalCredentialAndBalanceProof_61336.json");
        _testDeployAndVerifyNewEigenPod(podOwner, signature, depositDataRoot);
        IEigenPod newPod = eigenPodManager.getPod(podOwner);


        setJSON("./src/test/test-data/fullWithdrawalProof.json");
        BeaconChainProofs.WithdrawalProofs memory withdrawalProofs = _getWithdrawalProof();
        withdrawalFields = getWithdrawalFields();   
        validatorFields = getValidatorFields();
        bytes32 newBeaconStateRoot = getBeaconStateRoot();
        BeaconChainOracleMock(address(beaconChainOracle)).setBeaconChainStateRoot(newBeaconStateRoot);

        uint64 restakedExecutionLayerGweiBefore = newPod.restakedExecutionLayerGwei();
        uint64 withdrawalAmountGwei = Endian.fromLittleEndianUint64(withdrawalFields[BeaconChainProofs.WITHDRAWAL_VALIDATOR_AMOUNT_INDEX]);
        uint64 leftOverBalanceWEI = uint64(withdrawalAmountGwei - newPod.REQUIRED_BALANCE_GWEI()) * uint64(GWEI_TO_WEI);
        cheats.deal(address(newPod), leftOverBalanceWEI);
        
        uint256 escrowContractBalanceBefore = address(eigenPodPaymentEscrow).balance;
        newPod.verifyAndProcessWithdrawal(withdrawalProofs, validatorFields, withdrawalFields, 0, 0);
        require(newPod.restakedExecutionLayerGwei() -  restakedExecutionLayerGweiBefore == newPod.REQUIRED_BALANCE_GWEI(), "restakedExecutionLayerGwei has not been incremented correctly");
        require(address(eigenPodPaymentEscrow).balance - escrowContractBalanceBefore == leftOverBalanceWEI, "Escrow pod payment balance hasn't ben updated correctly");

        cheats.roll(block.number + PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS + 1);
        uint podOwnerBalanceBefore = address(podOwner).balance;
        eigenPodPaymentEscrow.claimPayments(podOwner, 1);
        require(address(podOwner).balance - podOwnerBalanceBefore == leftOverBalanceWEI, "Pod owner balance hasn't been updated correctly");
    }

    function testPartialWithdrawalFlow() public {
        //this call is to ensure that validatorContainerFields and validatorMerkleProof in BeaconChainUtils get set
        setJSON("./src/test/test-data/withdrawalCredentialAndBalanceProof_61068.json");
        _testDeployAndVerifyNewEigenPod(podOwner, signature, depositDataRoot);
        IEigenPod newPod = eigenPodManager.getPod(podOwner);


        setJSON("./src/test/test-data/partialWithdrawalProof.json");
        BeaconChainProofs.WithdrawalProofs memory withdrawalProofs = _getWithdrawalProof();
        withdrawalFields = getWithdrawalFields();   
        validatorFields = getValidatorFields();
        bytes32 newBeaconStateRoot = getBeaconStateRoot();
        BeaconChainOracleMock(address(beaconChainOracle)).setBeaconChainStateRoot(newBeaconStateRoot);

        uint64 withdrawalAmountGwei = Endian.fromLittleEndianUint64(withdrawalFields[BeaconChainProofs.WITHDRAWAL_VALIDATOR_AMOUNT_INDEX]);
        uint64 slot = Endian.fromLittleEndianUint64(withdrawalProofs.slotRoot);
        cheats.deal(address(newPod), stakeAmount);    

        uint256 escrowContractBalanceBefore = address(eigenPodPaymentEscrow).balance;
        newPod.verifyAndProcessWithdrawal(withdrawalProofs, validatorFields, withdrawalFields, 0, 0);
        uint40 validatorIndex = uint40(getValidatorIndex());
        require(newPod.provenPartialWithdrawal(validatorIndex, slot), "provenPartialWithdrawal should be true");
        withdrawalAmountGwei = uint64(withdrawalAmountGwei*GWEI_TO_WEI);
        require(address(eigenPodPaymentEscrow).balance - escrowContractBalanceBefore == withdrawalAmountGwei, "Escrow pod payment balance hasn't been updated correctly");

        cheats.roll(block.number + PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS + 1);
        uint podOwnerBalanceBefore = address(podOwner).balance;
        eigenPodPaymentEscrow.claimPayments(podOwner, 1);
        require(address(podOwner).balance - podOwnerBalanceBefore == withdrawalAmountGwei, "Pod owner balance hasn't been updated correctly");
    }



    function testDeployAndVerifyNewEigenPod() public returns(IEigenPod){
        setJSON("./src/test/test-data/withdrawalCredentialAndBalanceProof_61068.json");
        return _testDeployAndVerifyNewEigenPod(podOwner, signature, depositDataRoot);
    }

    // //test freezing operator after a beacon chain slashing event
    // function testUpdateSlashedBeaconBalance() public {
    //     //make initial deposit
    //     IEigenPod eigenPod = testDeployAndVerifyNewEigenPod();

    //     //get updated proof, set beaconchain state root
    //     _proveOvercommittedStake(eigenPod, validatorIndex0);
        
    //     uint256 beaconChainETHShares = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());

    //     require(beaconChainETHShares == 0, "investmentManager shares not updated correctly");
    // }

    // //test deploying an eigen pod with mismatched withdrawal credentials between the proof and the actual pod's address
    // function testDeployNewEigenPodWithWrongWithdrawalCreds(address wrongWithdrawalAddress) public {
    //     IEigenPod newPod;
    //     newPod = eigenPodManager.getPod(podOwner);
    //     // make sure that wrongWithdrawalAddress is not set to actual pod address
    //     cheats.assume(wrongWithdrawalAddress != address(newPod));
        
    //     (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) =
    //         getInitialDepositProof(validatorIndex0);
    //     BeaconChainOracleMock(address(beaconChainOracle)).setBeaconChainStateRoot(beaconStateRoot);


    //     cheats.startPrank(podOwner);
    //     eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
    //     cheats.stopPrank();

    //     validatorContainerFields[1] = abi.encodePacked(bytes1(uint8(1)), bytes11(0), wrongWithdrawalAddress).toBytes32(0);

    //     bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);
    //     cheats.expectRevert(bytes("EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod"));
    //     uint64 blockNumber = 1;
    //     newPod.verifyCorrectWithdrawalCredentials(blockNumber, validatorIndex0, proofs, validatorContainerFields);
    // }

    // //test that when withdrawal credentials are verified more than once, it reverts
    // function testDeployNewEigenPodWithActiveValidator() public {
    //     (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) =
    //         getInitialDepositProof(validatorIndex0);
    //     BeaconChainOracleMock(address(beaconChainOracle)).setBeaconChainStateRoot(beaconStateRoot);        

    //     cheats.startPrank(podOwner);
    //     eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
    //     cheats.stopPrank();

    //     IEigenPod newPod = eigenPodManager.getPod(podOwner);

    //     // bytes32 validatorIndexBytes = bytes32(uint256(validatorIndex0));
    //     bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);
    //     uint64 blockNumber = 1;
    //     newPod.verifyCorrectWithdrawalCredentials(blockNumber, validatorIndex0, proofs, validatorContainerFields);

    //     cheats.expectRevert(bytes("EigenPod.verifyCorrectWithdrawalCredentials: Validator must be inactive to prove withdrawal credentials"));
    //     newPod.verifyCorrectWithdrawalCredentials(blockNumber, validatorIndex0, proofs, validatorContainerFields);
    // }

    // function getBeaconChainETHShares(address staker) internal view returns(uint256) {
    //     return investmentManager.investorStratShares(staker, investmentManager.beaconChainETHStrategy());
    // }

    // // TEST CASES:

    // // 3. Single withdrawal credential
    // // Test: Owner proves an withdrawal credential.
    // // Expected Behaviour: beaconChainETH shares should increment by REQUIRED_BALANCE_WEI
    // //                     validator status should be marked as ACTIVE

    // function testProveSingleWithdrawalCredential(IEigenPod pod, uint40 validatorIndex) internal {
    //     // get beaconChainETH shares
    //     uint256 beaconChainETHBefore = getBeaconChainETHShares(pod.podOwner());

    //     // pointed withdrawal credential

    //     uint256 beaconChainETHAfter = getBeaconChainETHShares(pod.podOwner());
    //     assertTrue(beaconChainETHAfter - beaconChainETHBefore == pod.REQUIRED_BALANCE_WEI());
    //     assertTrue(pod.validatorStatus(validatorIndex) == IEigenPod.VALIDATOR_STATUS.ACTIVE);
    // }

    // // 5. Prove overcommitted balance
    // // Setup: Run (3). 
    // // Test: Watcher proves an overcommitted balance for validator from (3).
    // // Expected Behaviour: beaconChainETH shares should decrement by REQUIRED_BALANCE_WEI
    // //                     validator status should be marked as OVERCOMMITTED

    // function testProveOverCommittedBalance(IEigenPod pod, uint40 validatorIndex) internal {
    //     //IEigenPod pod = testDeployAndVerifyNewEigenPod(signature, depositDataRoot);
    //     // get beaconChainETH shares
    //     uint256 beaconChainETHBefore = getBeaconChainETHShares(pod.podOwner());

    //     // prove overcommitted balance
    //     _proveOvercommittedStake(pod, validatorIndex);

    //     assertTrue(beaconChainETHBefore - getBeaconChainETHShares(pod.podOwner()) == pod.REQUIRED_BALANCE_WEI(), "BeaconChainETHShares not updated");
    //     assertTrue(pod.validatorStatus(validatorIndex) == IEigenPod.VALIDATOR_STATUS.OVERCOMMITTED, "validator status not set correctly");
    // }

    // function testDeployingEigenPodRevertsWhenPaused() external {
    //     // pause the contract
    //     cheats.startPrank(eigenPodManager.pauserRegistry().pauser());
    //     eigenPodManager.pause(2 ** PAUSED_NEW_EIGENPODS);
    //     cheats.stopPrank();

    //     cheats.startPrank(podOwner);
    //     cheats.expectRevert(bytes("Pausable: index is paused"));
    //     eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
    //     cheats.stopPrank();
    // }

    // function testWithdrawRestakedBeaconChainETHRevertsWhenPaused() external {
    //     // pause the contract
    //     cheats.startPrank(eigenPodManager.pauserRegistry().pauser());
    //     eigenPodManager.pause(2 ** PAUSED_WITHDRAW_RESTAKED_ETH);
    //     cheats.stopPrank();

    //     address recipient = address(this);
    //     uint256 amount = 1e18;
    //     cheats.startPrank(address(eigenPodManager.investmentManager()));
    //     cheats.expectRevert(bytes("Pausable: index is paused"));
    //     eigenPodManager.withdrawRestakedBeaconChainETH(podOwner, recipient, amount);
    //     cheats.stopPrank();
    // }

    // function testVerifyCorrectWithdrawalCredentialsRevertsWhenPaused() external {
    //     uint40 validatorIndex = validatorIndex1;
    //     IEigenPod pod = testDeployAndVerifyNewEigenPod();

    //     _testVerifyNewValidator(pod, validatorIndex);

    //     (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) =
    //         getInitialDepositProof(validatorIndex);
    //     bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);

    //     // pause the contract
    //     cheats.startPrank(eigenPodManager.pauserRegistry().pauser());
    //     eigenPodManager.pause(2 ** PAUSED_EIGENPODS_VERIFY_CREDENTIALS);
    //     cheats.stopPrank();

    //     cheats.expectRevert(bytes("EigenPod.onlyWhenNotPaused: index is paused in EigenPodManager"));
    //     uint64 blockNumber = 1;
    //     emit log("hheh");
    //     pod.verifyCorrectWithdrawalCredentials(blockNumber, validatorIndex, proofs, validatorContainerFields);
    // }

    // function testVerifyOvercommittedStakeRevertsWhenPaused() external {
    //     uint40 validatorIndex = validatorIndex0;
    //     IEigenPod pod = testDeployAndVerifyNewEigenPod();

    //     (
    //         beaconStateRoot, 
    //         beaconStateMerkleProofForValidators, 
    //         validatorContainerFields, 
    //         validatorMerkleProof, 
    //         validatorTreeRoot, 
    //         validatorRoot
    //     ) = getSlashedDepositProof(validatorIndex);

    //     BeaconChainOracleMock(address(beaconChainOracle)).setBeaconChainStateRoot(beaconStateRoot);
        
    //     // bytes32 validatorIndexBytes = bytes32(uint256(validatorIndex));
    //     bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);

    //     // pause the contract
    //     cheats.startPrank(eigenPodManager.pauserRegistry().pauser());
    //     eigenPodManager.pause(2 ** PAUSED_EIGENPODS_VERIFY_OVERCOMMITTED);
    //     cheats.stopPrank();

    //     cheats.expectRevert(bytes("EigenPod.onlyWhenNotPaused: index is paused in EigenPodManager"));
    //     uint64 blockNumber = 0;
    //     pod.verifyOvercommittedStake(blockNumber, validatorIndex, proofs, validatorContainerFields, 0);
    // }



    // simply tries to register 'sender' as a delegate, setting their 'DelegationTerms' contract in EigenLayerDelegation to 'dt'
    // verifies that the storage of EigenLayerDelegation contract is updated appropriately
    function _testRegisterAsOperator(address sender, IDelegationTerms dt) internal {
        cheats.startPrank(sender);

        delegation.registerAsOperator(dt);
        assertTrue(delegation.isOperator(sender), "testRegisterAsOperator: sender is not a delegate");

        assertTrue(
            delegation.delegationTerms(sender) == dt, "_testRegisterAsOperator: delegationTerms not set appropriately"
        );

        assertTrue(delegation.isDelegated(sender), "_testRegisterAsOperator: sender not marked as actively delegated");
        cheats.stopPrank();
    }

    function _testDelegateToOperator(address sender, address operator) internal {
        //delegator-specific information
        (IInvestmentStrategy[] memory delegateStrategies, uint256[] memory delegateShares) =
            investmentManager.getDeposits(sender);

        uint256 numStrats = delegateShares.length;
        assertTrue(numStrats > 0, "_testDelegateToOperator: delegating from address with no investments");
        uint256[] memory inititalSharesInStrats = new uint256[](numStrats);
        for (uint256 i = 0; i < numStrats; ++i) {
            inititalSharesInStrats[i] = delegation.operatorShares(operator, delegateStrategies[i]);
        }

        cheats.startPrank(sender);
        delegation.delegateTo(operator);
        cheats.stopPrank();

        assertTrue(
            delegation.delegatedTo(sender) == operator,
            "_testDelegateToOperator: delegated address not set appropriately"
        );
        assertTrue(
            delegation.isDelegated(sender),
            "_testDelegateToOperator: delegated status not set appropriately"
        );

        for (uint256 i = 0; i < numStrats; ++i) {
            uint256 operatorSharesBefore = inititalSharesInStrats[i];
            uint256 operatorSharesAfter = delegation.operatorShares(operator, delegateStrategies[i]);
            assertTrue(
                operatorSharesAfter == (operatorSharesBefore + delegateShares[i]),
                "_testDelegateToOperator: delegatedShares not increased correctly"
            );
        }
    }
    function _testDelegation(address operator, address staker)
        internal
    {   
        if (!delegation.isOperator(operator)) {
            _testRegisterAsOperator(operator, IDelegationTerms(operator));
        }

        //making additional deposits to the investment strategies
        assertTrue(delegation.isNotDelegated(staker) == true, "testDelegation: staker is not delegate");
        _testDelegateToOperator(staker, operator);
        assertTrue(delegation.isDelegated(staker) == true, "testDelegation: staker is not delegate");

        IInvestmentStrategy[] memory updatedStrategies;
        uint256[] memory updatedShares;
        (updatedStrategies, updatedShares) =
            investmentManager.getDeposits(staker);
    }

    function _testDeployAndVerifyNewEigenPod(address _podOwner, bytes memory _signature, bytes32 _depositDataRoot)
        internal returns (IEigenPod)
    {
        // (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) =
        //     getInitialDepositProof(validatorIndex);

        BeaconChainProofs.WithdrawalCredentialAndBalanceProofs memory proofs = _getWithdrawalCredentialAndBalanceProof();
        validatorFields = getValidatorFields();
        bytes32 newBeaconStateRoot = getBeaconStateRoot();
        uint40 validatorIndex = uint40(getValidatorIndex());
        BeaconChainOracleMock(address(beaconChainOracle)).setBeaconChainStateRoot(newBeaconStateRoot);


        cheats.startPrank(_podOwner);
        eigenPodManager.stake{value: stakeAmount}(pubkey, _signature, _depositDataRoot);
        cheats.stopPrank();

        IEigenPod newPod;
        newPod = eigenPodManager.getPod(_podOwner);

        uint64 blockNumber = 1;
        newPod.verifyCorrectWithdrawalCredentials(blockNumber, validatorIndex, proofs, validatorFields);


        IInvestmentStrategy beaconChainETHStrategy = investmentManager.beaconChainETHStrategy();

        uint256 beaconChainETHShares = investmentManager.investorStratShares(_podOwner, beaconChainETHStrategy);
        require(beaconChainETHShares == REQUIRED_BALANCE_WEI, "investmentManager shares not updated correctly");
        return newPod;
    }

    // function _testVerifyNewValidator(IEigenPod pod, uint40 validatorIndex) internal {
    //     (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) =
    //         getInitialDepositProof(validatorIndex);
    //     bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);

    //     uint64 blockNumber = 1;
    //     pod.verifyCorrectWithdrawalCredentials(blockNumber, validatorIndex, proofs, validatorContainerFields);
    // }

    // function _proveOvercommittedStake(IEigenPod pod, uint40 validatorIndex) internal {
        
    //     (
    //         beaconStateRoot, 
    //         beaconStateMerkleProofForValidators, 
    //         validatorContainerFields, 
    //         validatorMerkleProof, 
    //         validatorTreeRoot, 
    //         validatorRoot
    //     ) = getSlashedDepositProof(validatorIndex);

    //     BeaconChainOracleMock(address(beaconChainOracle)).setBeaconChainStateRoot(beaconStateRoot);
        
    //     // bytes32 validatorIndexBytes = bytes32(uint256(validatorIndex));
    //     bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);
    //     uint64 blockNumber = 0;

    //     pod.verifyOvercommittedStake(blockNumber, validatorIndex, proofs, validatorContainerFields, 0);
    // }

    function _testQueueWithdrawal(
        address depositor,
        uint256[] memory strategyIndexes,
        IInvestmentStrategy[] memory strategyArray,
        uint256[] memory shareAmounts,
        bool undelegateIfPossible
    )
        internal
        returns (bytes32)
    {
        cheats.startPrank(depositor);

        //make a call with depositor aka podOwner also as withdrawer.
        bytes32 withdrawalRoot = investmentManager.queueWithdrawal(
            strategyIndexes,
            strategyArray,
            shareAmounts,
            depositor,
            // TODO: make this an input
            undelegateIfPossible
        );

        cheats.stopPrank();
        return withdrawalRoot;
    }

    function _getLatestPaymentAmount(address recipient) internal view returns (uint256) {
        return eigenPodPaymentEscrow.userPaymentByIndex(recipient, eigenPodPaymentEscrow.userPaymentsLength(recipient) - 1).amount;
    }

    function _getWithdrawalCredentialAndBalanceProof() internal returns (BeaconChainProofs.WithdrawalCredentialAndBalanceProofs memory){

        bytes32 balanceRoot = getBalanceRoot();
        BeaconChainProofs.WithdrawalCredentialAndBalanceProofs memory proofs = BeaconChainProofs.WithdrawalCredentialAndBalanceProofs(
            abi.encodePacked(getWithdrawalCredentialProof()),
            abi.encodePacked(getValidatorBalanceProof()),
            balanceRoot
        );

        return proofs;
    }

    /// @notice this function just generates a valid proof so that we can test other functionalities of the withdrawal flow
    function _getWithdrawalProof() internal returns(BeaconChainProofs.WithdrawalProofs memory) {
        //make initial deposit
        cheats.startPrank(podOwner);
        eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        
        {
            bytes32 beaconStateRoot = getBeaconStateRoot();
            //set beaconStateRoot
            beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
            bytes32 blockHeaderRoot = getBlockHeaderRoot();
            bytes32 blockBodyRoot = getBlockBodyRoot();
            slotRoot = getSlotRoot();
            blockNumberRoot = getBlockNumberRoot();
            executionPayloadRoot = getExecutionPayloadRoot();

            uint256 validatorIndex = getValidatorIndex(); 
                    emit log_named_uint("INT TEST validatorIndex", uint8(validatorIndex));


            uint256 withdrawalIndex = getWithdrawalIndex();
            uint256 blockHeaderRootIndex = getBlockHeaderRootIndex();


            BeaconChainProofs.WithdrawalProofs memory proofs = BeaconChainProofs.WithdrawalProofs(
                abi.encodePacked(getBlockHeaderProof()),
                abi.encodePacked(getWithdrawalProof()),
                abi.encodePacked(getSlotProof()),
                abi.encodePacked(getValidatorProof()),
                abi.encodePacked(getExecutionPayloadProof()),
                abi.encodePacked(getBlockNumberProof()),
                uint64(blockHeaderRootIndex),
                uint64(withdrawalIndex),
                uint40(validatorIndex),
                blockHeaderRoot,
                blockBodyRoot,
                slotRoot,
                blockNumberRoot,
                executionPayloadRoot
            );
            return proofs;
        }
    }

 }


 contract Relayer is Test {
    function verifyBlockNumberAndWithdrawalFields(
        bytes32 beaconStateRoot,
        BeaconChainProofs.WithdrawalProofs calldata proofs,
        bytes32[] calldata withdrawalFields
    ) public view {
        BeaconChainProofs.verifyBlockNumberAndWithdrawalFields(beaconStateRoot, proofs, withdrawalFields);
    }
 }