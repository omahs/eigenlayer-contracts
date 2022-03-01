// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/MiddlewareInterfaces.sol";
import "../../interfaces/CoreInterfaces.sol";
import "../../interfaces/InvestmentInterfaces.sol";
import "../../interfaces/ProofOfStakingInterfaces.sol";
import "../QueryManager.sol";


contract ProofOfStakingRegVW is IVoteWeighter, IRegistrationManager, IProofOfStakingRegVW {
    IEigenLayrDelegation public delegation;
    IInvestmentManager public investmentManager;
    IQueryManager public queryManager;
    IProofOfStakingServiceManager public posServiceManager;
    //consensus layer ETH counts for 'consensusLayerPercent'/100 when compared to ETH deposited in the system itself
    uint256 public consensusLayerPercent = 10;
    uint256 public totalEth;
    mapping(address => uint256) etherForOperator;
    
    constructor(IInvestmentManager _investmentManager){
        investmentManager = _investmentManager;
    }

    function setQueryManager(IQueryManager _queryManager) public {
        require(
            address(queryManager) == address(0),
            "Query Manager already set"
        );
        queryManager = _queryManager;
    }

    function setPosServiceManager(IProofOfStakingServiceManager _posServiceManager) public {
        require(address(_posServiceManager) == address(0) || msg.sender == address(queryManager), "Already set");
        posServiceManager = _posServiceManager;
    }

    function weightOfOperator(address user) external returns(uint256) {
        uint256 weight = (investmentManager.getConsensusLayerEth(user) * consensusLayerPercent) / 100;
        IInvestmentStrategy[] memory investorStrats = investmentManager.getStrategies(user);
        uint256[] memory investorShares = investmentManager.getStrategyShares(user);
        for (uint256 i = 0; i < investorStrats.length; i++) {
            weight += investorStrats[i].underlyingEthValueOfShares(investorShares[i]);
        }
        return weight;
    }

    function weightOfOperatorView(address user) external view returns(uint256) {
        uint256 weight = (investmentManager.getConsensusLayerEth(user) * consensusLayerPercent) / 100;
        IInvestmentStrategy[] memory investorStrats = investmentManager.getStrategies(user);
        uint256[] memory investorShares = investmentManager.getStrategyShares(user);
        for (uint256 i = 0; i < investorStrats.length; i++) {
            weight += investorStrats[i].underlyingEthValueOfSharesView(investorShares[i]);
        }
        return weight;
    }

    function operatorPermitted(address operator, bytes calldata data) external returns(bool) {
        require(etherForOperator[operator] == 0, "Operator is already registered");
        uint256 delegatedEther = delegation.getUnderlyingEthDelegated(operator);
        etherForOperator[operator] = delegatedEther;
        posServiceManager.setLastFeesForOperator(operator);
        totalEth += delegatedEther;
        return true;
    }

	function operatorPermittedToLeave(address operator, bytes calldata data) external returns(bool) {
        require(etherForOperator[operator] > 0, "Operator is not registered");
        totalEth -= etherForOperator[operator];
        etherForOperator[operator] = 0;
        return true;
    }

    function getEtherForOperator(address operator) external view returns (uint256) {
        return etherForOperator[operator];
    }
    
}