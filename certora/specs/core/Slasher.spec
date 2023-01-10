import "../../ComplexityCheck/erc20.spec"

methods {
	//// External Calls
	// external calls to EigenLayrDelegation 
    undelegate(address) => DISPATCHER(true)
    isDelegated(address) returns (bool) => DISPATCHER(true)
    delegatedTo(address) returns (address) => DISPATCHER(true)
	decreaseDelegatedShares(address,address[],uint256[]) => DISPATCHER(true)
	increaseDelegatedShares(address,address,uint256) => DISPATCHER(true)
	_delegationReceivedHook(address,address,address[],uint256[]) => NONDET
    _delegationWithdrawnHook(address,address,address[],uint256[]) => NONDET

	// external calls to Slasher
    isFrozen(address) returns (bool) => DISPATCHER(true)
	canWithdraw(address,uint32,uint256) returns (bool) => DISPATCHER(true)

	// external calls to InvestmentManager
    getDeposits(address) returns (address[],uint256[]) => DISPATCHER(true)
    slasher() returns (address) => DISPATCHER(true)
	deposit(address,uint256) returns (uint256) => DISPATCHER(true)
	withdraw(address,address,uint256) => DISPATCHER(true)

	// external calls to EigenPodManager
	withdrawBeaconChainETH(address,address,uint256) => DISPATCHER(true)
	
    // external calls to EigenPod
	withdrawBeaconChainETH(address,uint256) => DISPATCHER(true)
    
    // external calls to IDelegationTerms
    onDelegationWithdrawn(address,address[],uint256[]) => CONSTANT
    onDelegationReceived(address,address[],uint256[]) => CONSTANT
    
    // external calls to PauserRegistry
    pauser() returns (address) => DISPATCHER(true)
	unpauser() returns (address) => DISPATCHER(true)
	
    //// Harnessed Functions
    // Harnessed calls
    // Harmessed getters
	get_is_operator(address) returns (bool) envfree
	get_is_delegated(address) returns (bool) envfree
	get_node_exists(address, address) returns (bool) envfree

	//// Normal Functions
	owner() returns(address) envfree
	bondedUntil(address, address) returns (uint32) envfree
	paused(uint8) returns (bool) envfree
}

/*
TODO: sort out if `isFrozen` can also be marked as envfree -- currently this is failing with the error
could not type expression "isFrozen(staker)", message: Could not find an overloading of method isFrozen that matches
the given arguments: address. Method is not envfree; did you forget to provide the environment as the first function argument?
rule cantBeUnfrozen(method f) {
	address staker;

	bool _frozen = isFrozen(staker);
	require _frozen;

	env e; calldataarg args;
	require e.msg.sender != owner();
	f(e,args);

	bool frozen_ = isFrozen(staker);
	assert frozen_, "frozen stakers must stay frozen";
}
*/

/*
verifies that `bondedUntil[operator][contractAddress]` only changes when either:
the `operator` themselves calls `allowToSlash`
or
the `contractAddress` calls `recordLastStakeUpdateAndRevokeSlashingAbility`
*/
rule canOnlyChangeBondedUntilWithSpecificFunctions(address operator, address contractAddress) {
	uint256 valueBefore = bondedUntil(operator, contractAddress);
    // perform arbitrary function call
    method f;
    env e;
    if (f.selector == recordLastStakeUpdateAndRevokeSlashingAbility(address, uint32).selector) {
        address operator2;
		uint32 serveUntil;
        recordLastStakeUpdateAndRevokeSlashingAbility(e, operator2, serveUntil);
		uint256 valueAfter = bondedUntil(operator, contractAddress);
        if (e.msg.sender == contractAddress && operator2 == operator/* TODO: proper check */) {
			/* TODO: proper check */
            assert (true, "failure in recordLastStakeUpdateAndRevokeSlashingAbility");
        } else {
            assert (valueBefore == valueAfter, "bad permissions on recordLastStakeUpdateAndRevokeSlashingAbility?");
        }
	} else if (f.selector == optIntoSlashing(address).selector) {
		address arbitraryContract;
		optIntoSlashing(e, arbitraryContract);
		uint256 valueAfter = bondedUntil(operator, contractAddress);
		// uses that the `PAUSED_OPT_INTO_SLASHING` index is 0, as an input to the `paused` function
		if (e.msg.sender == operator && arbitraryContract == contractAddress && get_is_operator(operator) && !paused(0)) {
			// uses that `MAX_BONDED_UNTIL` is equal to max_uint32
			assert(valueAfter == max_uint32, "MAX_BONDED_UNTIL different than max_uint32?");
		} else {
            assert(valueBefore == valueAfter, "bad permissions on optIntoSlashing?");
		}
	} else {
		calldataarg arg;
		f(e, arg);
		uint256 valueAfter = bondedUntil(operator, contractAddress);
        assert(valueBefore == valueAfter, "bondedAfter value changed when it shouldn't have!");
	}
}

/* TODO: assess if this rule is salvageable. seems to have poor storage assumptions due to the way 'node existence' is defined
rule cannotAddSameContractTwice(address operator, address contractAddress) {
	bool nodeExistsBefore = get_node_exists(operator, contractAddress);
	env e;
	uint32 serveUntil;
	recordFirstStakeUpdate(e, operator, serveUntil);
	if (nodeExistsBefore) {
		bool callReverted = lastReverted;
		assert (callReverted, "recordFirstStakeUpdate didn't revert!");
	} else {
		bool nodeExistsAfter = get_node_exists(operator, contractAddress);
		if (e.msg.sender == contractAddress) {
			assert(nodeExistsAfter, "node not added correctly");
		} else {
			assert(!nodeExistsAfter, "node added incorrectly");
		}
	}
}
*/
