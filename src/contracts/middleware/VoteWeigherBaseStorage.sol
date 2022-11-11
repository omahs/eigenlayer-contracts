// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IVoteWeigher.sol";

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

/**
 * @title Storage variables for the `VoteWeigherBase` contract.
 * @author Layr Labs, Inc.
 * @notice This storage contract is separate from the logic to simplify the upgrade process.
 */
abstract contract VoteWeigherBaseStorage is Initializable, IVoteWeigher {
    /**
     * @notice In weighing a particular investment strategy, the amount of underlying asset for that strategy is
     * multiplied by its multiplier, then divided by WEIGHTING_DIVISOR
     */
    struct StrategyAndWeightingMultiplier {
        IInvestmentStrategy strategy;
        uint96 multiplier;
    }

    /// @notice Constant used as a divisor in calculating weights.
    uint256 internal constant WEIGHTING_DIVISOR = 1e18;
    /// @notice Maximum length of dynamic arrays in the `strategiesConsideredAndMultipliers` mapping.
    uint8 internal constant MAX_WEIGHING_FUNCTION_LENGTH = 32;
    /// @notice Constant used as a divisor in dealing with BIPS amounts.
    uint256 internal constant MAX_BIPS = 10000;

    /// @notice The address of the Delegation contract for EigenLayr.
    IEigenLayrDelegation public immutable delegation;
    
    /// @notice The address of the InvestmentManager contract for EigenLayr.
    IInvestmentManager public immutable investmentManager;

    /// @notice The ServiceManager contract for this middleware, where tasks are created / initiated.
    IServiceManager public immutable serviceManager;

    /// @notice Number of quorums that are being used by the middleware.
    uint256 public immutable NUMBER_OF_QUORUMS;

    /**
     * @notice mapping from quorum number to the list of strategies considered and their
     * corresponding multipliers for that specific quorum
     */
    mapping(uint256 => StrategyAndWeightingMultiplier[]) public strategiesConsideredAndMultipliers;

    /**
     * @notice This defines the earnings split between different quorums. Mapping is quorumNumber => BIPS which the quorum earns, out of the total earnings.
     * @dev The sum of all entries, i.e. sum(quorumBips[0] through quorumBips[NUMBER_OF_QUORUMS - 1]) should *always* be 10,000!
     */
    mapping(uint256 => uint256) public quorumBips;

    constructor(
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        IServiceManager _serviceManager,
        uint8 _NUMBER_OF_QUORUMS
    ) {
        // sanity check that the VoteWeigher is being initialized with at least 1 quorum
        require(_NUMBER_OF_QUORUMS != 0, "VoteWeigherBaseStorage.constructor: _NUMBER_OF_QUORUMS == 0");
        delegation = _delegation;
        investmentManager = _investmentManager;
        serviceManager = _serviceManager;
        NUMBER_OF_QUORUMS = _NUMBER_OF_QUORUMS;
        // disable initializers so that the implementation contract cannot be initialized
        _disableInitializers();
    }
}
