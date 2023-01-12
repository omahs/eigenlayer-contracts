# Solidity API

## EigenLayerDelegationStorage

This storage contract is separate from the logic to simplify the upgrade process.

### LOW_LEVEL_GAS_BUDGET

```solidity
uint256 LOW_LEVEL_GAS_BUDGET
```

Gas budget provided in calls to DelegationTerms contracts

### DOMAIN_TYPEHASH

```solidity
bytes32 DOMAIN_TYPEHASH
```

The EIP-712 typehash for the contract's domain

### DELEGATION_TYPEHASH

```solidity
bytes32 DELEGATION_TYPEHASH
```

The EIP-712 typehash for the delegation struct used by the contract

### DOMAIN_SEPARATOR

```solidity
bytes32 DOMAIN_SEPARATOR
```

EIP-712 Domain separator

### investmentManager

```solidity
contract IInvestmentManager investmentManager
```

The InvestmentManager contract for EigenLayer

### slasher

```solidity
contract ISlasher slasher
```

The Slasher contract for EigenLayer

### operatorShares

```solidity
mapping(address => mapping(contract IInvestmentStrategy => uint256)) operatorShares
```

returns the total number of shares in `strategy` that are delegated to `operator`.

### delegationTerms

```solidity
mapping(address => contract IDelegationTerms) delegationTerms
```

returns the DelegationTerms of the `operator`, which may mediate their interactions with stakers who delegate to them.

### delegatedTo

```solidity
mapping(address => address) delegatedTo
```

returns the address of the operator that `staker` is delegated to.

### nonces

```solidity
mapping(address => uint256) nonces
```

### constructor

```solidity
constructor(contract IInvestmentManager _investmentManager, contract ISlasher _slasher) internal
```
