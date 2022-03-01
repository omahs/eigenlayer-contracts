// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/MiddlewareInterfaces.sol";
import "../../interfaces/ProofOfStakingInterfaces.sol";
import "../../interfaces/CoreInterfaces.sol";
import "../../interfaces/IDataLayr.sol";
import "../QueryManager.sol";

contract ProofOfStakingServiceManager is IFeeManager, IProofOfStakingServiceManager {
    IVoteWeighter public voteWeighter;
    IProofOfStakingRegVW public posRegVW;
    IEigenLayrDelegation public eigenLayrDelegation;
    IERC20 public token;
    uint256 public fee;
    IQueryManager public queryManager;
    uint256 public totalFees;
    mapping(address => uint256) public operatorToLastFees;

    constructor(
        IEigenLayrDelegation _eigenLayrDelegation,
        IVoteWeighter _voteWeighter,
        IERC20 _token,
        IProofOfStakingRegVW _posRegVW
    ) {
        eigenLayrDelegation = _eigenLayrDelegation;
        voteWeighter = _voteWeighter;
        token = _token;
        posRegVW = _posRegVW;
    }

    function setQueryManager(IQueryManager _queryManager) public {
        require(
            address(queryManager) == address(0),
            "Query Manager already set"
        );
        queryManager = _queryManager;
    }

    function setFee(uint256 _fee) public {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        fee = _fee;
    }

    function payFee(address payer) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        totalFees += fee;
        token.transferFrom(payer, address(this), fee);
    }

    function redeemPayment() external {
        uint256 payment = posRegVW.getEtherForOperator(msg.sender) * (totalFees - operatorToLastFees[msg.sender]) / posRegVW.totalEth();
        operatorToLastFees[msg.sender] = totalFees;
        token.transfer(msg.sender, payment);
    }

    function getLastFees(address operator) external view returns (uint256) {
        return operatorToLastFees[operator];
    }

    function setLastFeesForOperator(address operator) external {
        require(msg.sender == address(posRegVW), "POSRegVW can onlse set last fees");
        operatorToLastFees[operator] = totalFees;
    }

    function onResponse(
        bytes32 queryHash,
        address operator,
        bytes32 reponseHash,
        uint256 senderWeight
    ) external {}
}
