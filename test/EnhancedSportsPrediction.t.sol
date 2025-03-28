// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {EnhancedSportsPrediction} from "../src/EnhancedSportsPrediction.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock token for testing
contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract EnhancedSportsPredictionTest is Test {
    EnhancedSportsPrediction public prediction;
    TestToken public token;
    address public owner;
    address public oracle;
    address public user1;
    address public user2;

    bytes32 public constant TEST_MATCH_ID = bytes32("MATCH_001");
    uint256 public constant BET_AMOUNT = 100 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        oracle = vm.addr(1);
        user1 = vm.addr(2);
        user2 = vm.addr(3);

        // Deploy test token
        token = new TestToken();

        // Deploy prediction contract
        prediction = new EnhancedSportsPrediction(
            token,
            oracle,
            5 // 5% house fee
        );

        // Fund users with tokens
        token.mint(user1, 1000 * 10 ** 18);
        token.mint(user2, 1000 * 10 ** 18);

        // Approve token spending
        vm.prank(user1);
        token.approve(address(prediction), type(uint256).max);

        vm.prank(user2);
        token.approve(address(prediction), type(uint256).max);
    }

    function test_CreateCondition() public {
        uint256 endTime = block.timestamp + 1 days;

        vm.prank(oracle);
        prediction.createCondition(TEST_MATCH_ID, endTime);

        // Check if the condition was created by verifying it exists
        // This uses the auto-generated getter from the public mapping
        (
            bytes32 matchId,
            bool resolved,
            uint256 winningOutcome,
            uint256 totalPool,
            uint256 retrievedEndTime
        ) = prediction.conditions(TEST_MATCH_ID);
        assertEq(retrievedEndTime, endTime);
    }

    function test_PlaceBet() public {
        // Create condition
        uint256 endTime = block.timestamp + 1 days;
        vm.prank(oracle);
        prediction.createCondition(TEST_MATCH_ID, endTime);

        // Place bet with user1
        vm.prank(user1);
        prediction.placeBet(TEST_MATCH_ID, 1, BET_AMOUNT);

        // Verify bet was placed
        assertEq(
            prediction.getUserBetForOutcome(TEST_MATCH_ID, user1, 1),
            BET_AMOUNT
        );
        assertEq(prediction.getTotalOutcomeBet(TEST_MATCH_ID, 1), BET_AMOUNT);
    }

    function test_ResolveBetAndClaim() public {
        // Create condition
        uint256 endTime = block.timestamp + 1 days;
        vm.prank(oracle);
        prediction.createCondition(TEST_MATCH_ID, endTime);

        // Place bets
        vm.prank(user1);
        prediction.placeBet(TEST_MATCH_ID, 1, BET_AMOUNT);

        vm.prank(user2);
        prediction.placeBet(TEST_MATCH_ID, 2, BET_AMOUNT);

        // Resolve condition (outcome 1 wins)
        vm.prank(oracle);
        prediction.resolveCondition(TEST_MATCH_ID, 1);

        // Verify user1 can claim
        bool claimable = prediction.getClaimable(TEST_MATCH_ID, user1);
        assertTrue(claimable);

        // Claim payout
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        prediction.claimPayout(TEST_MATCH_ID);

        uint256 balanceAfter = token.balanceOf(user1);
        assertTrue(balanceAfter > balanceBefore, "User should receive payout");

        // Check claim status
        (bool claimed, uint256 amount) = prediction.getClaimStatus(
            TEST_MATCH_ID,
            user1
        );
        assertTrue(claimed);
        assertTrue(amount > 0);
    }
}
