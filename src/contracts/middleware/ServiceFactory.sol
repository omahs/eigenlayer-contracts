// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IServiceFactory.sol";
import "./QueryManager.sol";

/**
 * @notice This factory contract is used for launching new query manager contracts.
 */


contract ServiceFactory is IServiceFactory {
    mapping(IQueryManager => bool) public isQueryManager;
    IInvestmentManager immutable investmentManager;

    constructor(IInvestmentManager _investmentManager) {
        investmentManager = _investmentManager;
    }


    /**
     *  @notice Used for creating new query manager contracts with given specifications.
     */
    /**
     * @param queryDuration is the duration for which each query in that query manager would 
     *        remain open for accepting response from operators,
     * @param consensusLayerEthToEth TBA,
     * @param feeManager is the contract for managing fees,
     * @param voteWeigher is the contract for determining how much vote to be assigned to
     *        the response from an operator for the purpose of computing the outcome of the query, 
     * @param registrationManager is the address of the contract that manages registration of operators
     *        with the middleware of the query manager that is being created,  
     * @param timelock is the contract for doing timelock capabilities. 
     */ 
    function createNewQueryManager(
        uint256 queryDuration,
        uint256 consensusLayerEthToEth,
        IFeeManager feeManager,
        IVoteWeighter voteWeigher,
        address registrationManager,
        address timelock,
        IEigenLayrDelegation delegation
    ) external {
        // register a new query manager
        IQueryManager newQueryManager = new QueryManager(voteWeigher);
        QueryManager(payable(address(newQueryManager))).initialize(
            queryDuration,
            consensusLayerEthToEth,
            feeManager,
            registrationManager,
            timelock,
            delegation,
            investmentManager
        );

        // set the existence bit on the query manager to true
        isQueryManager[newQueryManager] = true;
    }


    /// @notice used for checking if the query manager exists  
    function queryManagerExists(IQueryManager queryManager)
        external
        view
        returns (bool)
    {
        return isQueryManager[queryManager];
    }
}
