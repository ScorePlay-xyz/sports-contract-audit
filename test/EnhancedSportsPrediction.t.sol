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
            bool closed,
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

    function test_UpdateConditionEndTime() public {
        // Create condition
        uint256 endTime = block.timestamp + 1 days;
        vm.prank(oracle);
        prediction.createCondition(TEST_MATCH_ID, endTime);

        // Update end time
        uint256 newEndTime = block.timestamp + 2 days;
        vm.prank(oracle);
        prediction.updateConditionEndTime(TEST_MATCH_ID, newEndTime);

        // Check if the end time was updated
        (bytes32 matchId, , , , , uint256 retrievedEndTime) = prediction
            .conditions(TEST_MATCH_ID);
        assertEq(retrievedEndTime, newEndTime);
        assertEq(matchId, TEST_MATCH_ID);
    }

    function test_CloseConditionAndRefund() public {
        // Create condition
        uint256 endTime = block.timestamp + 1 days;
        vm.prank(oracle);
        prediction.createCondition(TEST_MATCH_ID, endTime);

        // Place bets from both users
        vm.prank(user1);
        prediction.placeBet(TEST_MATCH_ID, 1, BET_AMOUNT);

        vm.prank(user2);
        prediction.placeBet(TEST_MATCH_ID, 2, BET_AMOUNT);

        // Record balance before
        uint256 user1BalanceBefore = token.balanceOf(user1);

        // Close the condition (e.g., match canceled)
        vm.prank(oracle);
        prediction.closeCondition(TEST_MATCH_ID);

        // Check if condition is marked as closed
        assertTrue(prediction.isConditionClosed(TEST_MATCH_ID));

        // Check if user can claim refund
        bool refundable = prediction.getRefundable(TEST_MATCH_ID, user1);
        assertTrue(refundable, "User should be able to claim refund");

        // Claim refund
        vm.prank(user1);
        prediction.claimRefund(TEST_MATCH_ID);

        // Verify user received their bet amount back
        uint256 user1BalanceAfter = token.balanceOf(user1);
        assertEq(
            user1BalanceAfter,
            user1BalanceBefore + BET_AMOUNT,
            "User should receive full refund"
        );

        // Verify refund was processed
        uint256 refundAmount = prediction.getUserRefund(TEST_MATCH_ID, user1);
        assertEq(
            refundAmount,
            BET_AMOUNT,
            "Refund amount should match bet amount"
        );

        // Verify user can't claim twice
        vm.expectRevert();
        vm.prank(user1);
        prediction.claimRefund(TEST_MATCH_ID);
    }

    function test_MultipleCloseConditionAndRefund() public {
        // Create condition
        uint256 endTime = block.timestamp + 1 days;
        vm.prank(oracle);
        prediction.createCondition(TEST_MATCH_ID, endTime);

        // Place multiple bets from user1 on different outcomes (3 different outcomes)
        vm.prank(user1);
        prediction.placeBet(TEST_MATCH_ID, 1, BET_AMOUNT / 4);
        
        vm.prank(user1);
        prediction.placeBet(TEST_MATCH_ID, 2, BET_AMOUNT / 4);
        
        vm.prank(user1);
        prediction.placeBet(TEST_MATCH_ID, 3, BET_AMOUNT / 2);

        // Calculate total bet amount for user1 across all outcomes
        uint256 user1TotalBet = BET_AMOUNT;

        // Place bet from user2
        vm.prank(user2);
        prediction.placeBet(TEST_MATCH_ID, 1, BET_AMOUNT);

        // Record balances before closing
        uint256 user1BalanceBefore = token.balanceOf(user1);
        uint256 user2BalanceBefore = token.balanceOf(user2);

        // Close the condition
        vm.prank(oracle);
        prediction.closeCondition(TEST_MATCH_ID);

        // Verify condition is closed
        assertTrue(prediction.isConditionClosed(TEST_MATCH_ID));

        // Check if users can claim refunds
        assertTrue(prediction.getRefundable(TEST_MATCH_ID, user1), "User1 should be able to claim refund");

        // Claim refunds
        vm.prank(user1);
        prediction.claimRefund(TEST_MATCH_ID);

        vm.prank(user2);
        prediction.claimRefund(TEST_MATCH_ID);

        // Verify users received their total bet amounts back
        uint256 user1BalanceAfter = token.balanceOf(user1);
        uint256 user2BalanceAfter = token.balanceOf(user2);
        
        assertEq(
            user1BalanceAfter,
            user1BalanceBefore + user1TotalBet,
            "User1 should receive full refund for all bets across all outcomes"
        );
        
        assertEq(
            user2BalanceAfter,
            user2BalanceBefore + BET_AMOUNT,
            "User2 should receive full refund"
        );

        // Verify refund amounts
        uint256 user1RefundAmount = prediction.getUserRefund(TEST_MATCH_ID, user1);
        
        assertEq(
            user1RefundAmount,
            user1TotalBet,
            "User1 refund amount should match total bet amount across all outcomes"
        );

        // Verify users can't claim twice
        vm.expectRevert();
        vm.prank(user1);
        prediction.claimRefund(TEST_MATCH_ID);
    }
}
