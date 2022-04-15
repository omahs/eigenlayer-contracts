// SPDX-License-Identifier: UNLICENSED

//modified version of Compound's 'GovernorAlpha' contract -- see https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/GovernorAlpha.sol

/*
Copyright 2020 Compound Labs, Inc.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following 
	disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products
	derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
	BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
	THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
	(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
	HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
	ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

pragma solidity ^0.8.9;

import "../interfaces/IQueryManager.sol";
import "../interfaces/IVoteWeighter.sol";
import "../governance/Timelock.sol";

//TODO: better solutions for 'quorumVotes' and 'proposalThreshold'
contract QueryManagerGovernance {
    /// @notice The percentage of eth needed in support of a proposal required in order for a quorum
    /// to be reached for the eth and for a vote to succeed, if an eigen quorum is also reached
    uint16 public quorumEthPercentage;

    /// @notice The percentage of eigen needed in support of a proposal required in order for a quorum
    /// to be reached for the eigen and for a vote to succeed, if an eth quorum is also reached
    uint16 public quorumEigenPercentage;

    /// @notice The percentage of eth required in order for a voter to become a proposer
    uint16 proposalThresholdEthPercentage;

    /// @notice The percentage of eigen required in order for a voter to become a proposer
    uint16 public proposalThresholdEigenPercentage;

    IQueryManager public immutable QUERY_MANAGER;
    IVoteWeighter public immutable VOTE_WEIGHTER;

    /// @notice The maximum number of actions that can be included in a proposal
    function proposalMaxOperations() public pure returns (uint256) {
        return 10;
    } // 10 actions

    /// @notice The delay before voting on a proposal may take place, once proposed. stored as uint256 in number of seconds
    function votingDelay() public pure returns (uint256) {
        return 2 days;
    }

    /// @notice The duration of voting on a proposal, in seconds
    function votingPeriod() public pure returns (uint256) {
        return 7 days;
    }

    /// @notice The address of the Protocol Timelock
    Timelock public timelock;

    /// @notice The total number of proposals
    uint256 public proposalCount;

    /// @notice Address of multisig or other trusted party. Has zero extra votes, but can make proposals without meeting proposal
    ///         thresholds, and that pass by default
    ///         In other words, proposals created by the 'multsig' address require at least a quorum to reject them in order to
    ///         *not* pass, but otherwise operate like normal proposals, where the side with most votes wins
    address public multisig;

    struct Proposal {
        /// @notice Unique id for looking up a proposal
        uint256 id;
        /// @notice Creator of the proposal
        address proposer;
        /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint256 eta;
        /// @notice the ordered list of target addresses for calls to be made
        address[] targets;
        /// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint[] values;
        /// @notice The ordered list of function signatures to be called
        string[] signatures;
        /// @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        /// @notice The UTC timestamp at which voting begins: holders must delegate their votes prior to this UTC timestamp
        uint256 startTime;
        /// @notice The UTC timestamp at which voting ends: votes must be cast prior to this UTC timestamp
        uint256 endTime;
        /// @notice Current number of eth votes in favor of this proposal
        uint256 forEthVotes;
        /// @notice Current number of eth votes in opposition to this proposal
        uint256 againstEthVotes;
        /// @notice Current number of eigen votes in favor of this proposal
        uint256 forEigenVotes;
        /// @notice Current number of eigen votes in opposition to this proposal
        uint256 againstEigenVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been executed
        bool executed;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;
        /// @notice Whether or not the voter supports the proposal
        bool support;
        /// @notice The number of votes the voter had, which were cast
        uint96 eigenVotes;
        uint96 ethVotes;
    }

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    /// @notice Receipts of ballots for the entire set of voters
    mapping(uint256 => mapping(address => Receipt)) receipts;

    /// @notice The official record of all proposals ever proposed
    mapping(uint256 => Proposal) public proposals;

    /// @notice The latest proposal for each proposer
    mapping(address => uint) public latestProposalIds;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,bool support)");

    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startTime,
        uint256 endTime,
        string description
    );

    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(
        address voter,
        uint256 proposalId,
        bool support,
        uint256 eiegnVotes,
        uint256 ethVotes
    );

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint256 id, uint256 eta);

    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint256 id);

    /// @notice Emitted when the 'multisig' address has been changed
    event MultisigTransferred(address indexed previousMultisig, address indexed newMultisig);

    modifier onlyTimelock() {
        require(msg.sender == address(timelock), "onlyTimelock");
        _;
    }

    constructor(
        IQueryManager _QUERY_MANAGER,
        IVoteWeighter _VOTE_WEIGHTER,
        address _multisig,
        uint16 _quorumEthPercentage,
        uint16 _quorumEigenPercentage,
        uint16 _proposalThresholdEthPercentage,
        uint16 _proposalThresholdEigenPercentage
    ) {
        QUERY_MANAGER = _QUERY_MANAGER;
        VOTE_WEIGHTER = _VOTE_WEIGHTER;
        _setMultisig(_multisig);
        _setQuorumsAndThresholds(_quorumEthPercentage, _quorumEigenPercentage, _proposalThresholdEthPercentage, _proposalThresholdEigenPercentage);
        //TODO: figure the time out
        timelock = new Timelock(address(this), 10 days);

    }

    function propose(
        address[] memory targets,
        uint[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        bool update
    ) public returns (uint256) {
        (uint256 ethStaked, uint256 eigenStaked) = _getEthAndEigenStaked(
            msg.sender,
            update
        );
        // check percentage
        require(
            (ethStaked * 100) / QUERY_MANAGER.totalEthStaked() >=
                proposalThresholdEthPercentage ||
                (eigenStaked * 100) / QUERY_MANAGER.totalEigenStaked() >=
                proposalThresholdEigenPercentage ||
                msg.sender == multisig,
            "QueryManagerGovernance::propose: proposer votes below proposal threshold"
        );
        require(
            targets.length == values.length &&
                targets.length == signatures.length &&
                targets.length == calldatas.length,
            "QueryManagerGovernance::propose: proposal function information arity mismatch"
        );
        require(
            targets.length != 0,
            "QueryManagerGovernance::propose: must provide actions"
        );
        require(
            targets.length <= proposalMaxOperations(),
            "QueryManagerGovernance::propose: too many actions"
        );

        uint256 latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
            ProposalState proposersLatestProposalState = state(
                latestProposalId
            );
            require(
                proposersLatestProposalState != ProposalState.Active,
                "QueryManagerGovernance::propose: one live proposal per proposer, found an already active proposal"
            );
            require(
                proposersLatestProposalState != ProposalState.Pending,
                "QueryManagerGovernance::propose: one live proposal per proposer, found an already pending proposal"
            );
        }

        proposalCount++;
        Proposal memory newProposal = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            eta: 0,
            targets: targets,
            values: values,
            signatures: signatures,
            calldatas: calldatas,
            startTime: block.timestamp + votingDelay(),
            endTime: block.timestamp + votingDelay() + votingPeriod(),
            forEthVotes: 0,
            againstEthVotes: 0,
            forEigenVotes: 0,
            againstEigenVotes: 0,
            canceled: false,
            executed: false
        });

        proposals[newProposal.id] = newProposal;
        latestProposalIds[newProposal.proposer] = newProposal.id;

        emit ProposalCreated(
            newProposal.id,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            newProposal.startTime,
            newProposal.endTime,
            description
        );
        return newProposal.id;
    }

    function queue(uint256 proposalId) public {
        require(
            state(proposalId) == ProposalState.Succeeded,
            "QueryManagerGovernance::queue: proposal can only be queued if it is succeeded"
        );
        Proposal storage proposal = proposals[proposalId];
        uint256 eta = block.timestamp + timelock.delay();
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                eta
            );
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    function _queueOrRevert(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) internal {
        require(
            !timelock.queuedTransactions(
                keccak256(abi.encode(target, value, signature, data, eta))
            ),
            "QueryManagerGovernance::_queueOrRevert: proposal action already queued at eta"
        );
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    function execute(uint256 proposalId) public payable {
        require(
            state(proposalId) == ProposalState.Queued,
            "QueryManagerGovernance::execute: proposal can only be executed if it is queued"
        );
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction{value: proposal.values[i]}(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }
        emit ProposalExecuted(proposalId);
    }

    function cancel(uint256 proposalId, bool update) public {
        ProposalState stateOfProposal = state(proposalId);
        require(
            stateOfProposal != ProposalState.Executed,
            "QueryManagerGovernance::cancel: cannot cancel executed proposal"
        );

        Proposal storage proposal = proposals[proposalId];
        require(proposal.proposer != multisig, "multisig does not have to meet threshold requirements");
        (uint256 ethStaked, uint256 eigenStaked) = _getEthAndEigenStaked(
            proposal.proposer,
            update
        );
        // check percentage
        require(
            (ethStaked * 100) / QUERY_MANAGER.totalEthStaked() <
                proposalThresholdEthPercentage ||
                (eigenStaked * 100) / QUERY_MANAGER.totalEigenStaked() <
                proposalThresholdEigenPercentage,
            "QueryManagerGovernance::cancel: proposer above threshold"
        );

        proposal.canceled = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(
                proposal.targets[i],
                proposal.values[i],
                proposal.signatures[i],
                proposal.calldatas[i],
                proposal.eta
            );
        }

        emit ProposalCanceled(proposalId);
    }

    function getActions(uint256 proposalId)
        public
        view
        returns (
            address[] memory targets,
            uint[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    function getReceipt(uint256 proposalId, address voter)
        public
        view
        returns (Receipt memory)
    {
        return receipts[proposalId][voter];
    }

    function state(uint256 proposalId) public view returns (ProposalState) {
        //TODO: update this
        require(
            proposalCount >= proposalId && proposalId > 0,
            "QueryManagerGovernance::state: invalid proposal id"
        );
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.timestamp <= proposal.startTime) {
            return ProposalState.Pending;
        } else if (block.timestamp <= proposal.endTime) {
            return ProposalState.Active;
        } else if (
            proposal.forEthVotes <= proposal.againstEthVotes ||
            proposal.forEigenVotes <= proposal.againstEigenVotes ||
            (
                ((proposal.forEthVotes * 100) / QUERY_MANAGER.totalEthStaked() <
                quorumEthPercentage)
                &&
                (proposal.proposer != multisig)
            ) ||
            (
                ((proposal.forEigenVotes * 100) / QUERY_MANAGER.totalEigenStaked() <
                quorumEigenPercentage)
                &&
                (proposal.proposer != multisig)
            )
        ) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= proposal.eta + timelock.GRACE_PERIOD()) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    function castVote(uint256 proposalId, bool support, bool update) public {
        return _castVote(msg.sender, proposalId, support, update);
    }

    function castVoteBySig(
        uint256 proposalId,
        bool support,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bool update
    ) public {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, getChainId(), address(this))
        );
        bytes32 structHash = keccak256(
            abi.encode(BALLOT_TYPEHASH, proposalId, support)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        address signatory = ecrecover(digest, v, r, s);
        require(
            signatory != address(0),
            "QueryManagerGovernance::castVoteBySig: invalid signature"
        );
        return _castVote(signatory, proposalId, support, update);
    }

    function _castVote(
        address voter,
        uint256 proposalId,
        bool support,
        bool update
    ) internal {
        require(
            state(proposalId) == ProposalState.Active,
            "QueryManagerGovernance::_castVote: voting is closed"
        );
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = receipts[proposalId][voter];
        require(
            receipt.hasVoted == false,
            "QueryManagerGovernance::_castVote: voter already voted"
        );
        (uint256 ethStaked, uint256 eigenStaked) = _getEthAndEigenStaked(
            voter,
            update
        );
        //sanity check against overflow, since we convert from uint256 => uint96 below
        require(
            ethStaked < type(uint96).max &&
                eigenStaked < type(uint96).max,
            "QueryManagerGovernance::weight overflow"
        );
        uint96 ethVotes = uint96(ethStaked);
        uint96 eigenVotes = uint96(eigenStaked);

        if (support) {
            proposal.forEthVotes = proposal.forEthVotes + ethVotes;
            proposal.forEigenVotes = proposal.forEigenVotes + eigenVotes;
        } else {
            proposal.againstEthVotes = proposal.againstEthVotes + ethVotes;
            proposal.againstEigenVotes =
                proposal.againstEigenVotes +
                eigenVotes;
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.eigenVotes = eigenVotes;
        receipt.ethVotes = ethVotes;

        emit VoteCast(voter, proposalId, support, eigenVotes, ethVotes);
    }

    function setQuorumsAndThresholds(
        uint16 _quorumEthPercentage,
        uint16 _quorumEigenPercentage,
        uint16 _proposalThresholdEthPercentage,
        uint16 _proposalThresholdEigenPercentage
    ) external onlyTimelock {
        _setQuorumsAndThresholds(_quorumEthPercentage, _quorumEigenPercentage, _proposalThresholdEthPercentage, _proposalThresholdEigenPercentage);
    }

    function _setQuorumsAndThresholds(
        uint16 _quorumEthPercentage,
        uint16 _quorumEigenPercentage,
        uint16 _proposalThresholdEthPercentage,
        uint16 _proposalThresholdEigenPercentage
    ) internal {
        require(_quorumEthPercentage > 0 && _quorumEthPercentage < 100, "bad _quorumEthPercentage");
        require(_quorumEigenPercentage > 0 && _quorumEigenPercentage < 100, "bad _quorumEigenPercentage");
        require(_proposalThresholdEthPercentage > 0 && _proposalThresholdEthPercentage < 100, "bad _proposalThresholdEthPercentage");
        require(_proposalThresholdEigenPercentage > 0 && _proposalThresholdEigenPercentage < 100, "bad _proposalThresholdEigenPercentage");

        quorumEthPercentage = _quorumEthPercentage;
        quorumEigenPercentage = _quorumEigenPercentage;
        proposalThresholdEthPercentage = _proposalThresholdEthPercentage;
        proposalThresholdEigenPercentage = _proposalThresholdEigenPercentage;
    }

    function setMultisig(address _multisig) external onlyTimelock {
        _setMultisig(_multisig);
    }

    function _setMultisig(address _multisig) internal {
        emit MultisigTransferred(multisig, _multisig);
        multisig = _multisig;
    }

    function getChainId() internal view returns (uint256) {
        return block.chainid;
    }

    function _getEthAndEigenStaked(address user, bool update)
        internal
        returns (uint256, uint256)
    {
        uint256 ethStaked;
        uint256 eigenStaked;
        //if proposer wants to update their shares before proposing, calculate stake based on result of update
        //TODO: Call to only update eigen/eth. Isnt everyone gonna be eth and eigen staked
        if (update) {
            (
                uint256 newEthStaked,
                uint256 newEigenStaked
            ) = QUERY_MANAGER.updateStake(user);
            // weight the consensusLayrEth however desired
            ethStaked = newEthStaked;
            eigenStaked = newEigenStaked;
        } else {
            ethStaked = QUERY_MANAGER.ethStakedByOperator(
                user
            );
            eigenStaked = QUERY_MANAGER.eigenStakedByOperator(user);
        }
        return (ethStaked, eigenStaked);
    }
}