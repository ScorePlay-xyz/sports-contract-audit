// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedSportsPrediction} from "../src/EnhancedSportsPrediction.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Simple mock token for deployment
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract EnhancedSportsPredictionScript is Script {
    EnhancedSportsPrediction public predictionContract;
    MockToken public token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy mock token
        token = new MockToken();

        // Deploy prediction contract with:
        // - Mock token as collateral
        // - Script caller as oracle
        // - 5% house fee
        predictionContract = new EnhancedSportsPrediction(token, msg.sender, 5);

        vm.stopBroadcast();
    }
}
