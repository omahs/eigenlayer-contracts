// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./EigenLayrDelegationStorage.sol";
import "../permissions/Pausable.sol";
import "../investment/Slasher.sol";

// TODO: verify that limitation on undelegating from slashed operators is sufficient

/**
 * @title The primary delegation contract for EigenLayr.
 * @author Layr Labs, Inc.
 * @notice  This is the contract for delegation in EigenLayr. The main functionalities of this contract are
 * - for enabling any staker to register as a delegate and specify the delegation terms it has agreed to
 * - for enabling anyone to register as an operator
 * - for a registered staker to delegate its stake to the operator of its agreed upon delegation terms contract
 * - for a staker to undelegate its assets from EigenLayr
 * - for anyone to challenge a staker's claim to have fulfilled all its obligation before undelegation
 */
contract EigenLayrDelegation is Initializable, OwnableUpgradeable, EigenLayrDelegationStorage, Pausable {
    modifier onlyInvestmentManager() {
        require(msg.sender == address(investmentManager), "onlyInvestmentManager");
        _;
    }

    // INITIALIZING FUNCTIONS
    constructor() {
        _disableInitializers();
    }

    /// @dev Emitted when a low-level call to `delegationTerms.onDelegationReceived` fails, returning `returnData`
    event OnDelegationReceivedCallFailure(IDelegationTerms indexed delegationTerms, bytes returnData);

    /// @dev Emitted when a low-level call to `delegationTerms.onDelegationWithdrawn` fails, returning `returnData`
    event OnDelegationWithdrawnCallFailure(IDelegationTerms indexed delegationTerms, bytes returnData);

    /**
     * @notice Sets the `investMentManager` address (**currently modifiable by contract owner -- see below**),
     * sets the `undelegationFraudproofInterval` value (**currently modifiable by contract owner -- see below**),
     * and transfers ownership to `intialOwner`
     */
    function initialize(
        IInvestmentManager _investmentManager,
        IPauserRegistry _pauserRegistry,
        address initialOwner
    )
        external
        initializer
    {
        _initializePauser(_pauserRegistry);
        investmentManager = _investmentManager;
        _transferOwnership(initialOwner);
    }

    // EXTERNAL FUNCTIONS
    /**
     * @notice This will be called by an operator to register itself as a delegate that stakers can choose to delegate to.
     * @param dt is the `DelegationTerms` contract that the operator has for those who delegate to them.
     * @dev An operator can set `dt` equal to their own address (or another EOA address), in the event that they want to split payments
     * in a more 'trustful' manner.
     */
    function registerAsOperator(IDelegationTerms dt) external {
        require(
            address(delegationTerms[msg.sender]) == address(0),
            "EigenLayrDelegation.registerAsOperator: Delegate has already registered"
        );
        // store the address of the delegation contract that the operator is providing.
        delegationTerms[msg.sender] = dt;
        _delegate(msg.sender, msg.sender);
    }

    /// @notice This will be called by a staker to delegate its assets to some operator
    /// @param operator is the operator to whom staker (msg.sender) is delegating its assets
    function delegateTo(address operator) external whenNotPaused {
        _delegate(msg.sender, operator);
    }

    // delegates from `staker` to `operator`
    // requires that r, vs are a valid ECSDA signature from `staker` indicating their intention for this action
    function delegateToBySignature(address staker, address operator, uint256 expiry, bytes32 r, bytes32 vs)
        external
        whenNotPaused
    {
        require(expiry == 0 || expiry >= block.timestamp, "delegation signature expired");
        // calculate struct hash, then increment `staker`'s nonce
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, staker, operator, nonces[staker]++, expiry));
        bytes32 digestHash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        //check validity of signature
        address recoveredAddress = ECDSA.recover(digestHash, r, vs);
        require(recoveredAddress == staker, "EigenLayrDelegation.delegateToBySignature: sig not from staker");
        _delegate(staker, operator);
    }

    function undelegate(address staker) external onlyInvestmentManager {
        delegationStatus[staker] = DelegationStatus.UNDELEGATED;
    }

    //increases a stakers delegated shares to a certain strategy, usually whenever they have further deposits into EigenLayr
    function increaseDelegatedShares(address staker, IInvestmentStrategy strategy, uint256 shares)
        external
        onlyInvestmentManager
    {
        //if the staker is delegated to an operator
        if (isDelegated(staker)) {
            address operator = delegatedTo[staker];

            // add strategy shares to delegate's shares
            operatorShares[operator][strategy] += shares;

            //Calls into operator's delegationTerms contract to update weights of individual staker
            IInvestmentStrategy[] memory investorStrats = new IInvestmentStrategy[](1);
            uint256[] memory investorShares = new uint[](1);
            investorStrats[0] = strategy;
            investorShares[0] = shares;

            // call into hook in delegationTerms contract
            IDelegationTerms dt = delegationTerms[operator];
            _delegationReceivedHook(dt, staker, investorStrats, investorShares);
        }
    }

    //decreases a stakers delegated shares to a certain strategy, usually whenever they withdraw from EigenLayr
    function decreaseDelegatedShares(address staker, IInvestmentStrategy strategy, uint256 shares)
        external
        onlyInvestmentManager
    {
        //if the staker is delegated to an operator
        if (isDelegated(staker)) {
            address operator = delegatedTo[staker];

            // subtract strategy shares from delegate's shares
            operatorShares[operator][strategy] -= shares;

            //Calls into operator's delegationTerms contract to update weights of individual staker
            IInvestmentStrategy[] memory investorStrats = new IInvestmentStrategy[](1);
            uint256[] memory investorShares = new uint[](1);
            investorStrats[0] = strategy;
            investorShares[0] = shares;

            // call into hook in delegationTerms contract
            IDelegationTerms dt = delegationTerms[operator];
            _delegationWithdrawnHook(dt, staker, investorStrats, investorShares);
        }
    }

    function decreaseDelegatedShares(
        address staker,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    )
        external
        onlyInvestmentManager
    {
        if (isDelegated(staker)) {
            address operator = delegatedTo[staker];

            // subtract strategy shares from delegate's shares
            uint256 stratsLength = strategies.length;
            for (uint256 i = 0; i < stratsLength;) {
                operatorShares[operator][strategies[i]] -= shares[i];
                unchecked {
                    ++i;
                }
            }

            // call into hook in delegationTerms contract
            IDelegationTerms dt = delegationTerms[operator];
            _delegationWithdrawnHook(dt, staker, strategies, shares);
        }
    }

    function setInvestmentManager(IInvestmentManager _investmentManager) external onlyOwner {
        investmentManager = _investmentManager;
    }

    // INTERNAL FUNCTIONS

    function _delegationReceivedHook(
        IDelegationTerms dt,
        address staker,
        IInvestmentStrategy[] memory strategies,
        uint256[] memory shares
    )
        internal
    {
        // we use low-level call functionality here to ensure that an operator cannot maliciously make this function fail in order to prevent undelegation
        (bool success, bytes memory returnData) = address(dt).call{gas: LOW_LEVEL_GAS_BUDGET}(
            abi.encodeWithSelector(IDelegationTerms.onDelegationReceived.selector, staker, strategies, shares)
        );
        // if the internal call fails, we emit a special event rather than reverting
        if (!success) {
            emit OnDelegationReceivedCallFailure(dt, returnData);
        }
    }

    function _delegationWithdrawnHook(
        IDelegationTerms dt,
        address staker,
        IInvestmentStrategy[] memory strategies,
        uint256[] memory shares
    )
        internal
    {
        // we use low-level call functionality here to ensure that an operator cannot maliciously make this function fail in order to prevent undelegation
        (bool success, bytes memory returnData) = address(dt).call{gas: LOW_LEVEL_GAS_BUDGET}(
            abi.encodeWithSelector(IDelegationTerms.onDelegationWithdrawn.selector, staker, strategies, shares)
        );
        // if the internal call fails, we emit a special event rather than reverting
        if (!success) {
            emit OnDelegationWithdrawnCallFailure(dt, returnData);
        }
    }

    // internal function implementing the delegation of 'staker' to 'operator'
    function _delegate(address staker, address operator) internal {
        IDelegationTerms dt = delegationTerms[operator];
        require(
            address(dt) != address(0), "EigenLayrDelegation._delegate: operator has not yet registered as a delegate"
        );

        require(isNotDelegated(staker), "EigenLayrDelegation._delegate: staker has existing delegation");
        // checks that operator has not been frozen
        ISlasher slasher = investmentManager.slasher();
        require(!slasher.frozenStatus(operator), "EigenLayrDelegation._delegate: cannot delegate to a frozen operator");

        // record delegation relation between the staker and operator
        delegatedTo[staker] = operator;

        // record that the staker is delegated
        delegationStatus[staker] = DelegationStatus.DELEGATED;

        // retrieve list of strategies and their shares from investment manager
        (IInvestmentStrategy[] memory strategies, uint256[] memory shares) = investmentManager.getDeposits(staker);

        // add strategy shares to delegate's shares
        uint256 stratsLength = strategies.length;
        for (uint256 i = 0; i < stratsLength;) {
            // update the share amounts for each of the operator's strategies
            operatorShares[operator][strategies[i]] += shares[i];
            unchecked {
                ++i;
            }
        }

        // call into hook in delegationTerms contract
        _delegationReceivedHook(dt, staker, strategies, shares);
    }

    // VIEW FUNCTIONS

    /// @notice Checks whether a staker is currently undelegated.
    function isNotDelegated(address staker) public view returns (bool) {
        return (delegationStatus[staker] == DelegationStatus.UNDELEGATED);
    }

    /// @notice Checks whether a staker is currently delegated.
    function isDelegated(address staker) public view returns (bool) {
        return (delegationStatus[staker] == DelegationStatus.DELEGATED);
    }

    /// @notice Returns if an operator can be delegated to, i.e. it has called `registerAsOperator`.
    function isOperator(address operator) external view returns (bool) {
        return (address(delegationTerms[operator]) != address(0));
    }
}
