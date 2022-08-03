// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IServiceFactory.sol";
import "../interfaces/IRepository.sol";
import "../interfaces/ISlasher.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentManager.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

import "forge-std/Test.sol";


/**
 * @notice This contract specifies details on slashing. The functionalities are:
 *          - adding contracts who have permission to perform slashing,
 *          - revoking permission for slashing from specified contracts,
 *          - calling investManager to do actual slashing.          
 */
contract Slasher is 
    Initializable,
    OwnableUpgradeable,
    ISlasher
    // ,DSTest 
{
    // the InvestmentManager contract for EigenLayr
    IInvestmentManager public investmentManager;
    // the EigenLayrDelegation contract
    IEigenLayrDelegation public delegation;
    // contract address => whether or not the contract is allowed to slash any staker (or operator) in EigenLayr
    mapping(address => bool) public globallyPermissionedContracts;
    // user => contract => if that contract can slash the user
    mapping(address => mapping(address => bool)) public optedIntoSlashing;
    // staker => if they are 'slashed' or not
    mapping(address => bool) public slashedStatus;

    event GloballyPermissionedContractAdded(address indexed contractAdded);
    event GloballyPermissionedContractRemoved(address indexed contractRemoved);
    event OptedIntoSlashing(address indexed operator, address indexed contractAddress);
    event SlashingAbilityRevoked(address indexed operator, address indexed contractAddress);
    event OperatorSlashed(address indexed slashedOperator, address indexed slashingContract);

    constructor(){
        // TODO: uncomment for production use!
        //_disableInitializers();
    }

    // EXTERNAL FUNCTIONS
    function initialize(
        IInvestmentManager _investmentManager,
        IEigenLayrDelegation _delegation,
        address _eigenLayrGovernance
    ) external initializer {
        investmentManager = _investmentManager;
        delegation = _delegation;
        _transferOwnership(_eigenLayrGovernance);
        // add EigenLayrDelegation to list of permissioned contracts
        _addGloballyPermissionedContract(address(_delegation));
    }

    /**
     * @notice used for giving permission of slashing to contracts. 
     */
    function addPermissionedContracts(address[] calldata contracts) external onlyOwner {
        for (uint256 i = 0; i < contracts.length;) {
            _addGloballyPermissionedContract(contracts[i]);
            unchecked {
                ++i;
            }
        } 
    }

    /**
     * @notice used for revoking permission of slashing from contracts. 
     */
    function removePermissionedContracts(address[] calldata contracts) external onlyOwner {
        for (uint256 i = 0; i < contracts.length;) {
            _removeGloballyPermissionedContract(contracts[i]);
            unchecked {
                ++i;
            }
        }
    }

    // give the `contractAddress` permission to slash your funds
    function allowToSlash(address contractAddress) external {
        _optIntoSlashing(msg.sender, contractAddress);        
    }

    // called by a contract to revoke its ability to slash `operator`
    function revokeSlashingAbility(address operator) external {
        _revokeSlashingAbility(operator, msg.sender);
    }

    /**
     * @notice Used for slashing a certain operator
     */
    function slashOperator(
        address toBeSlashed
    ) external {
        require(canSlash(toBeSlashed, msg.sender), "Slasher.slashOperator: msg.sender does not have permission to slash this operator");
        _slashOperator(toBeSlashed, msg.sender);
    }

    function resetSlashedStatus(address[] calldata slashedAddresses) external onlyOwner {
        for (uint256 i = 0; i < slashedAddresses.length; ) {
            slashedStatus[slashedAddresses[i]] = false;
            unchecked { ++i; }
        }
    }

    // INTERNAL FUNCTIONS
    function _optIntoSlashing(address operator, address contractAddress) internal {
        if (!optedIntoSlashing[operator][contractAddress]) {
            optedIntoSlashing[operator][contractAddress] = true;
            emit OptedIntoSlashing(operator, contractAddress);        
        }
    }

    function _revokeSlashingAbility(address operator, address contractAddress) internal {
        if (optedIntoSlashing[operator][contractAddress]) {
            optedIntoSlashing[operator][contractAddress] = false;
            emit SlashingAbilityRevoked(operator, contractAddress);        
        }
    }

    function _addGloballyPermissionedContract(address contractToAdd) internal {
        if (!globallyPermissionedContracts[contractToAdd]) {
            globallyPermissionedContracts[contractToAdd] = true;
            emit GloballyPermissionedContractAdded(contractToAdd);
        }
    }

    function _removeGloballyPermissionedContract(address contractToRemove) internal {
        if (globallyPermissionedContracts[contractToRemove]) {
            globallyPermissionedContracts[contractToRemove] = false;
            emit GloballyPermissionedContractRemoved(contractToRemove);
        }
    }

    function _slashOperator(address toBeSlashed, address slashingContract) internal {
        if (!slashedStatus[toBeSlashed]) {
            slashedStatus[toBeSlashed] = true;
            emit OperatorSlashed(toBeSlashed, slashingContract);
        }
    }

    // VIEW FUNCTIONS
    function hasBeenSlashed(address staker) external view returns (bool) {
        if (slashedStatus[staker]) {
            return true;
        } else if (delegation.isDelegated(staker)) {
            address operatorAddress = delegation.delegation(staker);
            return(slashedStatus[operatorAddress]);
        } else {
            return false;
        }
    }

    function canSlash(address toBeSlashed, address slashingContract) public view returns (bool) {
        if (globallyPermissionedContracts[slashingContract]) {
            return true;
        } else if (optedIntoSlashing[toBeSlashed][slashingContract]) {
            return true;
        } else {
            return false;
        }
    }
}
