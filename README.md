## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Enhanced Sports Prediction Contract Documentation

### Overview
The Enhanced Sports Prediction Contract is a Solidity smart contract that enables users to place bets on sports events with customizable outcomes. It incorporates security mechanisms such as `Ownable` and `ReentrancyGuard` to enhance security and efficiency.

### Features
- Users can place bets on events outcomes.
- Oracle resolves event outcomes.
- House fees are collected on each event.
- Secure payout and refund mechanisms.
- Only an authorized oracle can create and resolve matches.

### Contract Components

#### Imports
- `ERC20`: For handling collateral token transactions.
- `Ownable`: To restrict privileged functions to the contract owner.
- `ReentrancyGuard`: To prevent reentrancy attacks.

#### State Variables
- `collateralToken (IERC20)`: ERC20 token used for bets.
- `oracle (address)`: Address authorized to create and resolve matches.
- `houseFee (uint256)`: Percentage fee taken from the total pool.
- `totalFeesCollected (uint256)`: Tracks total fees collected by the house.
- `conditions (mapping)`: Stores match conditions and betting details.
- `userMatches (mapping)`: Tracks matches each user participated in.
- `userPayouts (mapping)`: Tracks users who claimed payouts.

### Errors
Custom errors are used to save gas:
- `ConditionAlreadyExists()`: A match condition is already created.
- `ConditionNotFound()`: Attempting to interact with a non-existent match.
- `ConditionAlreadyResolved()`: The match outcome has been declared.
- `ConditionNotResolved()`: The match outcome has not yet been declared.
- `BettingPeriodEnded()`: Betting is closed for the match.
- `InvalidBetAmount()`: Bet amount must be greater than zero.
- `NoWinningBet()`: User has no winning bet to claim.
- `AlreadyClaimed()`: User has already claimed their winnings.

### Events
- `ConditionCreated(bytes32 matchId, uint256 endTime)`: Emitted when a match condition is created.
- `BetPlaced(address user, bytes32 matchId, uint256 outcome, uint256 amount, uint256 totalPool)`: Emitted when a bet is placed.
- `ConditionResolved(bytes32 matchId, uint256 winningOutcome)`: Emitted when an oracle declares the match outcome.
- `PayoutClaimed(address user, bytes32 matchId, uint256 amount)`: Emitted when a user claims their winnings.
- `HouseFeeCollected(bytes32 matchId, uint256 feeAmount)`: Emitted when the house collects its fee.
- `FeesWithdrawn(address owner, uint256 amount)`: Emitted when the contract owner withdraws fees.
- `ConditionClosedForRefund(bytes32 matchId)`: Emitted when a match is canceled and bets are refunded.

### Functions

#### Constructor
```solidity
constructor(IERC20 _collateralToken, address _oracle, uint256 _houseFee)
```
- Initializes the contract with collateral token, oracle, and house fee.
- Ensures valid addresses and fee values.

#### createCondition
```solidity
function createCondition(bytes32 matchId, uint256 endTime) external onlyOracle
```
- Creates a new betting condition for a match.
- Ensures that the match does not already exist and that the betting period is valid.

#### placeBet
```solidity
function placeBet(bytes32 matchId, uint256 outcome, uint256 amount) external nonReentrant
```
- Allows users to place bets on a given match and outcome.
- Transfers collateral tokens from the user to the contract.

#### resolveCondition
```solidity
function resolveCondition(bytes32 matchId, uint256 winningOutcome) external onlyOracle
```
- Resolves a match by specifying the winning outcome.
- Calculates and collects house fees.

#### claimPayout
```solidity
function claimPayout(bytes32 matchId) external nonReentrant
```
- Allows users to claim winnings if they bet on the correct outcome.
- Ensures users have not already claimed their rewards.

#### closeCondition (Refund Mechanism)
```solidity
function closeCondition(bytes32 matchId) external onlyOracle
```
- Allows the oracle to close a match without resolution.
- Triggers refunds for all users who placed bets on the match.
- Emits `ConditionClosedForRefund` event.

### Security Measures
- **Reentrancy Protection**: Prevents reentrancy attacks in critical functions.
- **Ownership Restrictions**: Only the contract owner can modify key parameters.
- **Oracle Authorization**: Only the oracle can create and resolve matches.

### Usage
1. Oracle creates a match using `createCondition()`.
2. Users place bets using `placeBet()`.
3. Oracle resolves the match using `resolveCondition()`.
4. Winners claim rewards using `claimPayout()`.
5. In case of match cancellation, the oracle calls `closeCondition()` to refund bets.
6. Fees can be withdrawn by the contract owner using `withdrawFees()`.

### Conclusion
The Enhanced Sports Prediction Contract provides a secure and efficient way to place and settle sports bets with clear rules, automated payouts, and oracle-based resolution. The addition of refund mechanisms ensures fairness in case of event cancellations.

