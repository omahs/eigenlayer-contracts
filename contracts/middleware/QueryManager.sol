// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.9;

// import "../interfaces/IERC20.sol";

// interface IQueryManager {
// 	function createNewQuery(bytes calldata queryData) external;
// }

// interface IFeeManager {
// 	function payFee(address payee) external;
// 	function onResponse(bytes32 queryHash, address operator, bytes32 reponseHash, uint256 senderWeight) external;
// 	function voteWeighter() external view returns(IVoteWeighter);
// }

// interface IVoteWeighter {
// 	function weightOfDelegate(address) external returns(uint256);
// 	function weightOfDelegator(address) external returns(uint256);
// }

// interface IDelegateTerms {

// }

// abstract contract QueryManager is IQueryManager {
// 	struct Query {
// 		//hash(reponse) with the greatest cumulative weight
// 		bytes32 leadingResponse;
// 		//hash(finalized response). initialized as 0x0, updated if/when query is finalized
// 		bytes32 outcome;
// 		//sum of all cumulative weights
// 		uint256 totalCumulativeWeight;
// 		//hash(response) => cumulative weight
// 		mapping(bytes32 => uint256) cumulativeWeights;
// 		//operator => hash(response)
// 		mapping(address => bytes32) responses;
// 		//operator => weight
// 		mapping(address => uint256) operatorWeights;
// 	}

// 	//fixed duration of all new queries
// 	uint256 public queryDuration;
// 	//called when new queries are created. handles payments for queries.
// 	IFeeManager public feeManager;
// 	//called when responses are provided by operators
// 	IVoteWeighter public voteWeighter;
// 	//hash(queryData) => Query
// 	mapping(bytes32 => Query) public queries;
// 	//hash(queryData) => time query created
// 	mapping(bytes32 => uint256) public queriesCreated;

// 	event QueryCreated(bytes32 indexed queryDataHash, uint256 blockTimestamp);
// 	event ResponseReceived(address indexed submitter, bytes32 indexed queryDataHash, bytes32 indexed responseHash, uint256 weightAssigned);
// 	event NewLeadingResponse(bytes32 indexed queryDataHash, bytes32 indexed previousLeadingResponseHash, bytes32 indexed newLeadingResponseHash);
// 	event QueryFinalized(bytes32 indexed queryDataHash, bytes32 indexed outcome, uint256 totalCumulativeWeight);

// 	constructor(uint256 _queryDuration, IFeeManager _feeManager, IVoteWeighter _voteWeighter) {
// 		queryDuration = _queryDuration;
// 		feeManager = _feeManager;
// 		voteWeighter = _voteWeighter;
// 	}

// 	function createNewQuery(bytes calldata queryData) external {
// 		address msgSender = msg.sender;
// 		bytes32 queryDataHash = keccak256(queryData);
// 		//verify that query has not already been created
// 		require(queriesCreated[queryDataHash] == 0, "duplicate query");
// 		//mark query as created and emit an event
// 		queriesCreated[queryDataHash] = block.timestamp;
// 		emit QueryCreated(queryDataHash, block.timestamp);
// 		//hook to manage payment for query
// 		IFeeManager(feeManager).payFee(msgSender);
// 	}

// 	function respondToQuery(bytes32 queryHash, bytes calldata response) external {
// 		address msgSender = msg.sender;
// 		//make sure query is open and sender has not already responded to it
// 		require(block.timestamp < _queryExpiry(queryHash), "query period over");
// 		require(queries[queryHash].operatorWeights[msgSender] == 0, "duplicate response to query");
// 		//find sender's weight and the hash of their response
// 		uint256 weightToAssign = voteWeighter.weightOfDelegate(msgSender);
// 		bytes32 responseHash = keccak256(response);
// 		//update Query struct with sender's weight + response
// 		queries[queryHash].operatorWeights[msgSender] = weightToAssign;
// 		queries[queryHash].responses[msgSender] = responseHash;
// 		queries[queryHash].cumulativeWeights[responseHash] += weightToAssign;
// 		queries[queryHash].totalCumulativeWeight += weightToAssign;
// 		//emit event for response
// 		emit ResponseReceived(msgSender, queryHash, responseHash, weightToAssign);
// 		//check if leading response has changed. if so, update leadingResponse and emit an event
// 		bytes32 leadingResponseHash = queries[queryHash].leadingResponse;
// 		if (responseHash != leadingResponseHash && queries[queryHash].cumulativeWeights[responseHash] > queries[queryHash].cumulativeWeights[leadingResponseHash]) {
// 			queries[queryHash].leadingResponse = responseHash;
// 			NewLeadingResponse(queryHash, leadingResponseHash, responseHash);
// 		}
// 		//hook for updating fee manager on each response
// 		feeManager.onResponse(queryHash, msgSender, responseHash, weightToAssign);
// 	}

// 	function finalizeQuery(bytes32 queryHash) external {
// 		//make sure queryHash is valid + query period has ended
// 		require(queriesCreated[queryHash] != 0, "invalid queryHash");
// 		require(block.timestamp >= _queryExpiry(queryHash), "query period ongoing");
// 		//check that query has not already been finalized
// 		require(queries[queryHash].outcome == bytes32(0), "duplicate finalization request");
// 		//record final outcome + emit an event
// 		bytes32 outcome = queries[queryHash].leadingResponse;
// 		queries[queryHash].outcome = outcome;
// 		emit QueryFinalized(queryHash, outcome, queries[queryHash].totalCumulativeWeight);
// 	}

// 	function _queryExpiry(bytes32 queryHash) internal view returns(uint256) {
// 		return queriesCreated[queryHash] + queryDuration;
// 	}
// }

// abstract contract FeeManager is IFeeManager {
// 	//constant scaling factor
// 	uint256 constant internal SCALING_FACTOR = 2**64;
// 	//sum of all operatorWeights
// 	uint256 public totalWeight;
// 	//token used for payments
// 	IERC20 public paymentToken;
// 	//fixed payment amount per query
// 	uint256 public paymentAmount;
// 	//allows splitting of payments amongst operators
// 	uint256 public cumulativePaymentPerWeight;

// //TODO: set this somewhere
// 	IQueryManager public queryManager;
// 	//operator => weight
// 	mapping(address => uint256) public operatorWeights;
// 	//operator => paymentDebt -- see 'pendingPayment' function for logic
// 	mapping(address => uint256) public operatorPaymentDebts;

// 	constructor(IERC20 _paymentToken, uint256 _paymentAmount) {
// 		paymentToken = _paymentToken;
// 		paymentAmount = _paymentAmount;
// 	}

// 	function pendingPayment(address operator) public view returns(uint256) {
// 		return ((cumulativePaymentPerWeight * operatorWeights[operator]) / SCALING_FACTOR) - operatorPaymentDebts;
// 	}

// 	function payFee(address payee) external {
// //TODO: PERMISSION!!!
// 		//take payment from payee
// 		paymentToken.transferFrom(payee, address(this), paymentAmount);
// 		//effectively split payment amongst all operators
// 		cumulativePaymentPerWeight += (paymentAmount * SCALING_FACTOR) / totalWeight;
// 	}

// 	function onResponse(bytes32, address operator, bytes32, uint256 senderWeight) external {
// //TODO: PERMISSION!!!
// //TODO: check if operator is valid?
// 		_updateOperatorWeight(operator, senderWeight);
// 	}

// 	function forceOperatorWeightUpdate(address operator) external {
// 		uint256 newWeight = queryManager.voteWeighter().weightOfDelegate(operator);
// 		_updateOperatorWeight(operator, newWeight);
// 	}

// 	function _updateOperatorWeight(address operator, uint256 newWeight) internal {
// 		uint256 oldWeight = operatorWeights[operator];
// 		//find pending payment for operator
// 		uint256 toSend = pendingPayment(operator);
// 		//update operator weight and total weight
// 		if (newWeight > oldWeight) {
// 			totalWeight += (newWeight - oldWeight);
// 			operatorWeights[operator] = newWeight;
// 		} else if (newWeight < oldWeight) {
// 			totalWeight -= (oldWeight - newWeight);
// 			operatorWeights[operator] = newWeight;
// 		}
// 		//ensure that operator is entitled to future payments, but not past payments (pendingPayment for operator should now be zero!)
// 		operatorPaymentDebts = (cumulativePaymentPerWeight * newWeight) / SCALING_FACTOR;
// //TODO: update this logic to use operator's DelegateTerms instead
// 		//transfer the pending tokens to the operator
// 		if (toSend > 0) {
// 			paymentToken.transfer(operator, toSend);			
// 		}
// 	}
// }

// abstract contract DelegateTerms is IDelegateTerms {
// 	uint16 internal constant MAX_BIPS = 10000;
// 	//variable to keep track of amount of earnings kept by operator (in BIPs, i.e. parts in 10,000)
// 	uint256 public operatorFeeBips;
// 	//sum of weights of all delegates
// 	uint256 public totalWeight;
// 	//token used for payments
// 	IERC20 public paymentToken;

// //TODO: set this somewhere
// 	IQueryManager public queryManager;
// 	//mapping delegator => weight
// 	mapping(address => uint256) delegatorWeights;

// 	constructor(IERC20 _paymentToken) {
// 		paymentToken = _paymentToken;
// 	}

// 	function updateDelegatorWeight(address delegator) external {
// 		uint256 newWeight = queryManager.voteWeighter().weightOfDelegator(delegator);
// 		_updateDelegatorWeight(delegator, newWeight);
// 	}

// 	function _updateDelegatorWeight(address delegator, uint256 newWeight) internal {
// 		uint256 oldWeight = delegatorWeights[delegator];
// 		//find pending payment for delegator
// 		uint256 toSend = pendingPayment(delegator);
// 		//update delegator weight and total weight
// 		if (newWeight > oldWeight) {
// 			totalWeight += (newWeight - oldWeight);
// 			delegatorWeights[delegator] = newWeight;
// 		} else if (newWeight < oldWeight) {
// 			totalWeight -= (oldWeight - newWeight);
// 			delegatorWeights[delegator] = newWeight;
// 		}
// 		//ensure that delegator is entitled to future payments, but not past payments (pendingPayment for delegator should now be zero!)
// 		delegatorPaymentDebts = (cumulativePaymentPerWeight * newWeight) / SCALING_FACTOR;
// 		//transfer the pending tokens to the delegator
// 		if (toSend > 0) {
// 			paymentToken.transfer(delegator, toSend);			
// 		}
// 	}
// }