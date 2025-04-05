pragma solidity ^0.8.20;

// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Enhanced Sports Prediction Contract
/// @notice Allows users to place bets on sports events with customizable outcomes
/// @dev Implements security features like ReentrancyGuard and Ownable
contract EnhancedSportsPrediction is Ownable, ReentrancyGuard {
    IERC20 public collateralToken;
    address public oracle;
    uint256 public houseFee;
    uint256 public constant FEE_DENOMINATOR = 100;
    uint256 public totalFeesCollected;

    // Custom errors to save gas
    error ConditionAlreadyExists();
    error ConditionNotFound();
    error ConditionAlreadyResolved();
    error ConditionNotResolved();
    error BettingPeriodEnded();
    error InvalidBetAmount();
    error NoWinningBet();
    error EmptyPool();
    error NoBetsOnOutcome();
    error InvalidAddress();
    error InvalidFee();
    error NoFeesToWithdraw();
    error InvalidOutcome();
    // error BettingPeriodNotEnded();
    error AlreadyClaimed();

    struct Condition {
        bytes32 matchId;
        bool resolved;
        uint256 winningOutcome;
        uint256 totalPool;
        uint256 endTime;
        mapping(uint256 => uint256) outcomeBets;
        mapping(address => mapping(uint256 => uint256)) userBets;
        mapping(address => bool) hasClaimed;
        mapping(address => uint256) claimedAmounts;
    }

    mapping(bytes32 => Condition) public conditions;

    // Track user participation
    mapping(address => bytes32[]) private userMatches;
    mapping(address => bytes32[]) private userPayouts;
    mapping(address => mapping(bytes32 => bool)) private userParticipated;

    // Events
    event ConditionCreated(bytes32 indexed matchId, uint256 endTime);
    event BetPlaced(
        address indexed user,
        bytes32 indexed matchId,
        uint256 indexed outcome,
        uint256 amount,
        uint256 totalPool
    );
    event ConditionResolved(bytes32 indexed matchId, uint256 winningOutcome);
    event PayoutClaimed(
        address indexed user,
        bytes32 indexed matchId,
        uint256 amount
    );
    event HouseFeeCollected(bytes32 matchId, uint256 feeAmount);
    event FeesWithdrawn(address indexed owner, uint256 amount);
    event OracleChanged(address indexed oldOracle, address indexed newOracle);
    event HouseFeeChanged(uint256 oldFee, uint256 newFee);
    event ConditionEndTimeUpdated(
        bytes32 indexed matchId,
        uint256 oldEndTime,
        uint256 newEndTime
    );

    modifier onlyOracle() {
        if (msg.sender != oracle) revert InvalidAddress();
        _;
    }

    /// @notice Contract constructor
    /// @param _collateralToken Address of the ERC20 token used for bets
    /// @param _oracle Address authorized to create/resolve conditions
    /// @param _houseFee Fee percentage taken from the total pool (1-10%)
    constructor(
        IERC20 _collateralToken,
        address _oracle,
        uint256 _houseFee
    ) Ownable(msg.sender) {
        // Pass msg.sender to the Ownable constructor
        if (address(_collateralToken) == address(0)) revert InvalidAddress();
        if (_oracle == address(0)) revert InvalidAddress();

        collateralToken = _collateralToken;
        oracle = _oracle;
        setHouseFee(_houseFee);
    }

    /// @notice Creates a new betting condition
    /// @param matchId Unique identifier for the match
    /// @param endTime Timestamp after which betting is no longer allowed
    function createCondition(
        bytes32 matchId,
        uint256 endTime
    ) external onlyOracle {
        if (conditions[matchId].matchId != bytes32(0))
            revert ConditionAlreadyExists();
        if (endTime <= block.timestamp) revert BettingPeriodEnded();

        Condition storage newCondition = conditions[matchId];
        newCondition.matchId = matchId;
        newCondition.endTime = endTime;

        emit ConditionCreated(matchId, endTime);
    }

    /// @notice Places a bet on a specific outcome
    /// @param matchId The match identifier
    /// @param outcome The outcome being bet on
    /// @param amount Amount of tokens to bet
    function placeBet(
        bytes32 matchId,
        uint256 outcome,
        uint256 amount
    ) external nonReentrant {
        Condition storage condition = conditions[matchId];
        if (condition.matchId == bytes32(0)) revert ConditionNotFound();
        if (condition.resolved) revert ConditionAlreadyResolved();
        if (block.timestamp >= condition.endTime) revert BettingPeriodEnded();
        if (amount == 0) revert InvalidBetAmount();

        condition.outcomeBets[outcome] += amount;
        condition.userBets[msg.sender][outcome] += amount;
        condition.totalPool += amount;

        // Track user participation if not already tracked
        if (!userParticipated[msg.sender][matchId]) {
            userMatches[msg.sender].push(matchId);
            userParticipated[msg.sender][matchId] = true;
        }

        emit BetPlaced(
            msg.sender,
            matchId,
            outcome,
            amount,
            condition.totalPool
        );

        bool success = collateralToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) revert();
    }

    /// @notice Resolves a condition with a winning outcome
    /// @param matchId The match identifier
    /// @param winningOutcome The outcome that won
    function resolveCondition(
        bytes32 matchId,
        uint256 winningOutcome
    ) external onlyOracle {
        Condition storage condition = conditions[matchId];
        if (condition.matchId == bytes32(0)) revert ConditionNotFound();
        if (condition.resolved) revert ConditionAlreadyResolved();
        // if (block.timestamp < condition.endTime) revert BettingPeriodNotEnded();

        condition.resolved = true;
        condition.winningOutcome = winningOutcome;

        uint256 houseCut = (condition.totalPool * houseFee) / FEE_DENOMINATOR;
        totalFeesCollected += houseCut;

        emit ConditionResolved(matchId, winningOutcome);
        emit HouseFeeCollected(matchId, houseCut);
    }

    /// @notice Allows a user to claim their winnings
    /// @param matchId The match identifier
    function claimPayout(bytes32 matchId) external nonReentrant {
        Condition storage condition = conditions[matchId];
        if (!condition.resolved) revert ConditionNotResolved();
        if (condition.hasClaimed[msg.sender]) revert AlreadyClaimed();

        uint256 userBet = condition.userBets[msg.sender][
            condition.winningOutcome
        ];
        if (userBet == 0) revert NoWinningBet();

        uint256 conditionTotalPool = condition.totalPool;
        if (conditionTotalPool == 0) revert EmptyPool();

        uint256 houseCut = (conditionTotalPool * houseFee) / FEE_DENOMINATOR;
        uint256 payoutPool = conditionTotalPool - houseCut;

        uint256 outcomePool = condition.outcomeBets[condition.winningOutcome];
        if (outcomePool == 0) revert NoBetsOnOutcome();

        uint256 payout = (userBet * payoutPool) / outcomePool;

        // Update claim status, amount and payouts before transfer
        condition.hasClaimed[msg.sender] = true;
        condition.claimedAmounts[msg.sender] = payout;
        userPayouts[msg.sender].push(matchId);

        emit PayoutClaimed(msg.sender, matchId, payout);

        bool success = collateralToken.transfer(msg.sender, payout);
        if (!success) revert();
    }

    /// @notice Calculates the current odds for a specific outcome
    /// @param matchId The match identifier
    /// @param outcome The outcome to get odds for
    /// @return The current odds multiplied by 1e18
    function getOdds(
        bytes32 matchId,
        uint256 outcome
    ) external view returns (uint256) {
        Condition storage condition = conditions[matchId];
        if (condition.matchId == bytes32(0)) revert ConditionNotFound();

        uint256 totalPool = condition.totalPool;
        uint256 outcomePool = condition.outcomeBets[outcome];
        if (outcomePool == 0) revert NoBetsOnOutcome();

        // Safe multiplication by checking that totalPool * 1e18 doesn't overflow
        if (totalPool > 0 && totalPool > type(uint256).max / 1e18) {
            // If might overflow, scale down first
            return (totalPool / outcomePool) * 1e18;
        } else {
            return (totalPool * 1e18) / outcomePool;
        }
    }

    /// @notice Sets a new oracle address
    /// @param newOracle The new oracle address
    function setOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert InvalidAddress();
        address oldOracle = oracle;
        oracle = newOracle;
        emit OracleChanged(oldOracle, newOracle);
    }

    /// @notice Sets a new house fee
    /// @param _houseFee The new house fee percentage
    function setHouseFee(uint256 _houseFee) public onlyOwner {
        if (_houseFee > 10) revert InvalidFee();
        uint256 oldFee = houseFee;
        houseFee = _houseFee;
        emit HouseFeeChanged(oldFee, _houseFee);
    }

    /// @notice Withdraws collected fees to the owner
    function withdrawFees() external onlyOwner nonReentrant {
        if (totalFeesCollected == 0) revert NoFeesToWithdraw();

        uint256 feesToWithdraw = totalFeesCollected;
        totalFeesCollected = 0;

        bool success = collateralToken.transfer(owner(), feesToWithdraw);
        if (!success) revert();

        emit FeesWithdrawn(owner(), feesToWithdraw);
    }

    /// @notice Updates the end time for a betting condition
    /// @param matchId The match identifier
    /// @param newEndTime New timestamp after which betting is no longer allowed
    function updateConditionEndTime(
        bytes32 matchId,
        uint256 newEndTime
    ) external onlyOracle {
        Condition storage condition = conditions[matchId];
        if (condition.matchId == bytes32(0)) revert ConditionNotFound();
        if (condition.resolved) revert ConditionAlreadyResolved();
        if (newEndTime <= block.timestamp) revert BettingPeriodEnded();

        uint256 oldEndTime = condition.endTime;
        condition.endTime = newEndTime;

        emit ConditionEndTimeUpdated(matchId, oldEndTime, newEndTime);
    }

    /// @notice Returns the total bet a user placed on a specific outcome for a given matchId
    /// @param matchId The match identifier
    /// @param user The user address
    /// @param outcome The outcome to check
    /// @return The amount bet by the user on the outcome
    function getUserBetForOutcome(
        bytes32 matchId,
        address user,
        uint256 outcome
    ) external view returns (uint256) {
        return conditions[matchId].userBets[user][outcome];
    }

    /// @notice Returns the total amount bet on a specific outcome for a given matchId
    /// @param matchId The match identifier
    /// @param outcome The outcome to check
    /// @return The total amount bet on the outcome
    function getTotalOutcomeBet(
        bytes32 matchId,
        uint256 outcome
    ) external view returns (uint256) {
        return conditions[matchId].outcomeBets[outcome];
    }

    /// @notice Checks if a user can claim winnings for a given match
    /// @param matchId The match identifier
    /// @param user The user address
    /// @return Whether the user can claim winnings
    function getClaimable(
        bytes32 matchId,
        address user
    ) external view returns (bool) {
        Condition storage condition = conditions[matchId];
        return (condition.resolved &&
            condition.userBets[user][condition.winningOutcome] > 0 &&
            !condition.hasClaimed[user]);
    }

    /// @notice Get all matches a user has participated in
    /// @param user The user address
    /// @return Array of matchIds the user has bet on
    function getUserMatches(
        address user
    ) external view returns (bytes32[] memory) {
        return userMatches[user];
    }

    /// @notice Get all matches a user has claimed payouts for
    /// @param user The user address
    /// @return Array of matchIds the user has received payouts for
    function getUserPayouts(
        address user
    ) external view returns (bytes32[] memory) {
        return userPayouts[user];
    }

    /// @notice Check if a user has participated in a specific match
    /// @param user The user address
    /// @param matchId The match identifier
    /// @return Whether the user has participated in the match
    function hasUserParticipated(
        address user,
        bytes32 matchId
    ) external view returns (bool) {
        return userParticipated[user][matchId];
    }

    /// @notice Returns the claimed amount for a user in a given match
    /// @param matchId The match identifier
    /// @param user The address of the user
    /// @return The amount claimed by the user
    function getUserWinnings(
        bytes32 matchId,
        address user
    ) external view returns (uint256) {
        return conditions[matchId].claimedAmounts[user];
    }

    /// @notice Get the claim status and amount for a user
    /// @param matchId The match identifier
    /// @param user The user address
    /// @return claimed Whether the user has claimed their winnings
    /// @return amount The amount claimed by the user (0 if not claimed)
    function getClaimStatus(
        bytes32 matchId,
        address user
    ) external view returns (bool claimed, uint256 amount) {
        Condition storage condition = conditions[matchId];
        return (condition.hasClaimed[user], condition.claimedAmounts[user]);
    }
}
