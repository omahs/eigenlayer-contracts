# Solidity API

## InvestmentStrategyWrapper

Simple, basic, "do-nothing" InvestmentStrategy that holds a single underlying token and returns it on withdrawals.
Assumes shares are always 1-to-1 with the underlyingToken.

_Unlike `InvestmentStrategyBase`, this contract is *not* designed to be inherited from._

### investmentManager

```solidity
contract IInvestmentManager investmentManager
```

EigenLayer's InvestmentManager contract

### underlyingToken

```solidity
contract IERC20 underlyingToken
```

The underyling token for shares in this InvestmentStrategy

### totalShares

```solidity
uint256 totalShares
```

The total number of extant shares in thie InvestmentStrategy

### onlyInvestmentManager

```solidity
modifier onlyInvestmentManager()
```

### constructor

```solidity
constructor(contract IInvestmentManager _investmentManager, contract IERC20 _underlyingToken) public
```

### deposit

```solidity
function deposit(contract IERC20 token, uint256 amount) external virtual returns (uint256)
```

Used to deposit tokens into this InvestmentStrategy

_This function is only callable by the investmentManager contract. It is invoked inside of the investmentManager's
`depositIntoStrategy` function, and individual share balances are recorded in the investmentManager as well._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | contract IERC20 | is the ERC20 token being deposited |
| amount | uint256 | is the amount of token being deposited |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | newShares is the number of new shares issued at the current exchange ratio. |

### withdraw

```solidity
function withdraw(address depositor, contract IERC20 token, uint256 amountShares) external virtual
```

Used to withdraw tokens from this InvestmentStrategy, to the `depositor`'s address

_This function is only callable by the investmentManager contract. It is invoked inside of the investmentManager's
other functions, and individual share balances are recorded in the investmentManager as well._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address |  |
| token | contract IERC20 | is the ERC20 token being transferred out |
| amountShares | uint256 | is the amount of shares being withdrawn |

### explanation

```solidity
function explanation() external pure virtual returns (string)
```

Currently returns a brief string explaining the strategy's goal & purpose, but for more complex
strategies, may be a link to metadata that explains in more detail.

### sharesToUnderlyingView

```solidity
function sharesToUnderlyingView(uint256 amountShares) public view virtual returns (uint256)
```

Used to convert a number of shares to the equivalent amount of underlying tokens for this strategy.
In contrast to `sharesToUnderlying`, this function guarantees no state modifications

_Implementation for these functions in particular may vary signifcantly for different strategies_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountShares | uint256 | is the amount of shares to calculate its conversion into the underlying token |

### sharesToUnderlying

```solidity
function sharesToUnderlying(uint256 amountShares) public view virtual returns (uint256)
```

Used to convert a number of shares to the equivalent amount of underlying tokens for this strategy.
In contrast to `sharesToUnderlyingView`, this function **may** make state modifications

_Implementation for these functions in particular may vary signifcantly for different strategies_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountShares | uint256 | is the amount of shares to calculate its conversion into the underlying token |

### underlyingToSharesView

```solidity
function underlyingToSharesView(uint256 amountUnderlying) external view virtual returns (uint256)
```

Used to convert an amount of underlying tokens to the equivalent amount of shares in this strategy.
In contrast to `underlyingToShares`, this function guarantees no state modifications

_Implementation for these functions in particular may vary signifcantly for different strategies_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountUnderlying | uint256 | is the amount of `underlyingToken` to calculate its conversion into strategy shares |

### underlyingToShares

```solidity
function underlyingToShares(uint256 amountUnderlying) external view virtual returns (uint256)
```

Used to convert an amount of underlying tokens to the equivalent amount of shares in this strategy.
In contrast to `underlyingToSharesView`, this function **may** make state modifications

_Implementation for these functions in particular may vary signifcantly for different strategies_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountUnderlying | uint256 | is the amount of `underlyingToken` to calculate its conversion into strategy shares |

### userUnderlyingView

```solidity
function userUnderlyingView(address user) external view virtual returns (uint256)
```

convenience function for fetching the current underlying value of all of the `user`'s shares in
this strategy. In contrast to `userUnderlying`, this function guarantees no state modifications

### userUnderlying

```solidity
function userUnderlying(address user) external virtual returns (uint256)
```

convenience function for fetching the current underlying value of all of the `user`'s shares in
this strategy. In contrast to `userUnderlyingView`, this function **may** make state modifications

### shares

```solidity
function shares(address user) public view virtual returns (uint256)
```

convenience function for fetching the current total shares of `user` in this strategy, by
querying the `investmentManager` contract
