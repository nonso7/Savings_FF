// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {TimeLockSavings} from "../src/Savings.sol";
import {MyToken} from "./mockUsdc.t.sol";

contract timeLockSavingsTest is Test {
    address user1;
    address user2;
    TimeLockSavings timelocksaving;
    MyToken mytoken;

    function setUp() public {
        // Initialize user addresses
        user1 = vm.addr(1); // Generate address with private key 1
        user2 = vm.addr(2); // Generate address with private key 2

        // Deploy MyToken
        mytoken = new MyToken();

        // Deploy TimeLockSavings with MyToken address
        timelocksaving = new TimeLockSavings(address(mytoken));

        mytoken.approve(address(user1), 1000);

        // Mint tokens to users and approve TimeLockSavings contract
        vm.startPrank(user1);
        mytoken.mint(user1, 1000);
        mytoken.approve(address(timelocksaving), 1000);
        vm.stopPrank();

        vm.startPrank(user2);
        mytoken.mint(user2, 1000);
        mytoken.approve(address(timelocksaving), 1000);
        vm.stopPrank();
    }

    function testCalculateRewardMismatch() public {
        // User1 deposits 100 tokens
        vm.prank(user1);
        timelocksaving.deposit(100);

        // Fast forward to 60 days (MIN_LOCK_PERIOD)
        vm.warp(block.timestamp + 60 days);

        // Get deposit info
        (,,, uint256 reward,) = timelocksaving.getDepositInfo(user1, 0);

        // Expected reward: 2% of 100 ether = 2 ether
        uint256 expectedReward = (100 * timelocksaving.BASE_REWARD_RATE()) / timelocksaving.BASIS_POINTS();
        assertEq(expectedReward, 2, "Expected reward should be 2 ether");

        // Actual reward (incorrect due to parameter swap)
        uint256 incorrectReward = timelocksaving.calculateReward(60 days, 100);
        console.log("Incorrect reward:", incorrectReward);
        assertTrue(incorrectReward != expectedReward, "Reward is incorrect due to parameter mismatch");

        // Verify incorrect calculation
        // Expected in calculateReward: (_timeElapsed = 60 days, _amount = 100 ether)
        // Actual: treats 60 days as _amount and 100 ether as _timeElapsed
        uint256 wrongReward = (60 days * timelocksaving.BASE_REWARD_RATE()) / timelocksaving.BASIS_POINTS();
        assertNotEq(reward, wrongReward, "Reward matches incorrect calculation");
    }

    function testEmergencyWithdrawCausesInsolvency() public {
        // User1 deposits 100 tokens
        vm.prank(user1);
        timelocksaving.deposit(100);

        // Fast forward to 60 days
        vm.warp(block.timestamp + 60 days);

        // Owner performs emergency withdrawal
        vm.prank(address(this)); // Assuming test contract is the owner
        timelocksaving.emergencyWithdraw();

        // User1 tries to withdraw (expects 100 ether + 2 ether reward)

        vm.prank(user1);
        vm.expectRevert();
        timelocksaving.withdraw(0);
    }

    function testSmallDepositZeroReward() public {
        // User1 deposits 49 tokens
        vm.prank(user1);
        timelocksaving.deposit(49);

        // Fast forward to 60 days
        vm.warp(block.timestamp + 60 days);

        // Check reward
        (,,, uint256 reward,) = timelocksaving.getDepositInfo(user1, 0);
        assertEq(reward, 0, "Reward is zero due to integer division truncation");
    }

    function testDoubleWithdrawal() public {
        // User1 deposits 100 tokens
        vm.prank(user1);
        timelocksaving.deposit(100);

        // Fast forward to 60 days
        vm.warp(block.timestamp + 60 days);

        // Mint extra tokens to contract to simulate excess funds
        vm.prank(address(this));
        mytoken.mint(address(timelocksaving), 1000);
        console.log(mytoken.balanceOf(address(timelocksaving)));

        // Withdraw once
        vm.prank(user1);
        timelocksaving.withdraw(1);

        // Withdraw again (should fail but doesn’t due to missing withdrawn check)
        vm.prank(user1);
        timelocksaving.withdraw(1); // Succeeds if contract has funds

        // Check user balance
        uint256 userBalance = mytoken.balanceOf(user1);
        console.log("User balance after double withdrawal:", userBalance);
        assertTrue(userBalance > 102 ether, "User received extra funds from double withdrawal");
    }
}
