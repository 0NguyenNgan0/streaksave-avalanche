// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {StreakSavings} from "../src/StreakSavings.sol";

/// @dev Test-only token that burns a 1% fee on transfers, used to exercise the
///      balance-delta guard in StreakSavings.deposit.
contract FeeOnTransferToken is ERC20 {
    constructor() ERC20("Fee Token", "FEE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        uint256 fee = value / 100;
        super._update(from, address(0), fee);
        super._update(from, to, value - fee);
    }
}

/// @dev Test-only token that calls back into StreakSavings during a transfer,
///      used to prove that the reentrancy guard blocks nested deposits/withdrawals.
contract ReentrantToken is ERC20 {
    StreakSavings private target;
    bool private reentryEnabled;

    constructor() ERC20("Reentrant Token", "RE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTarget(StreakSavings target_) external {
        target = target_;
    }

    function setReentryEnabled(bool enabled) external {
        reentryEnabled = enabled;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (reentryEnabled && from != address(0) && to != address(0)) {
            reentryEnabled = false;
            target.deposit(1);
        }
        super._update(from, to, value);
    }
}

contract StreakSavingsTest is Test {
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount, uint256 principalRemaining);

    uint256 private constant ONE_USDC = 1e6;
    uint256 private constant USER_FUNDS = 10_000 * ONE_USDC;
    uint64 private constant DEFAULT_EPOCH_DURATION = 60;
    uint64 private constant PROD_EPOCH_DURATION = 7 days;

    MockUSDC private usdc;
    StreakSavings private savings;

    address private alice;
    address private bob;
    address private carol;

    function setUp() public {
        usdc = new MockUSDC();
        savings = new StreakSavings(IERC20(address(usdc)), DEFAULT_EPOCH_DURATION);

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        usdc.mint(alice, USER_FUNDS);
        usdc.mint(bob, USER_FUNDS);
        usdc.mint(carol, USER_FUNDS);

        vm.prank(alice);
        usdc.approve(address(savings), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(savings), type(uint256).max);
        vm.prank(carol);
        usdc.approve(address(savings), type(uint256).max);
    }

    function _deposit(address user, uint256 amount) private {
        vm.prank(user);
        savings.deposit(amount);
    }

    function _withdraw(address user, uint256 amount) private {
        vm.prank(user);
        savings.withdraw(amount);
    }

    // ---------------------------------------------------------------------
    // Initial state and constructor
    // ---------------------------------------------------------------------

    function test_InitialState() public view {
        assertEq(address(savings.usdc()), address(usdc));
        assertEq(savings.epochDuration(), DEFAULT_EPOCH_DURATION);
        assertEq(savings.startTime(), block.timestamp);
        assertEq(savings.totalPrincipal(), 0);
        assertEq(savings.principalOf(alice), 0);
        assertEq(usdc.balanceOf(address(savings)), 0);
    }

    function test_ConstructorRejectsZeroToken() public {
        vm.expectRevert(StreakSavings.StreakSavings__InvalidToken.selector);
        new StreakSavings(IERC20(address(0)), DEFAULT_EPOCH_DURATION);
    }

    function test_ConstructorRejectsNonContractToken() public {
        vm.expectRevert(StreakSavings.StreakSavings__InvalidToken.selector);
        new StreakSavings(IERC20(address(0xBEEF)), DEFAULT_EPOCH_DURATION);
    }

    function test_Epoch_RevertWhen_DurationIsZero() public {
        vm.expectRevert(StreakSavings.StreakSavings__InvalidEpochDuration.selector);
        new StreakSavings(IERC20(address(usdc)), 0);
    }

    // ---------------------------------------------------------------------
    // Group B — Principal accounting consistency and edge cases
    // ---------------------------------------------------------------------

    function test_DepositCreditsPrincipal() public {
        uint256 amount = 5 * ONE_USDC;
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.expectEmit(true, false, false, true, address(savings));
        emit Deposit(alice, amount);

        _deposit(alice, amount);

        assertEq(savings.principalOf(alice), amount);
        assertEq(savings.totalPrincipal(), amount);
        assertEq(usdc.balanceOf(address(savings)), amount);
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore - amount);
    }

    function test_DepositMultipleTimesAccumulates() public {
        _deposit(alice, 5 * ONE_USDC);
        _deposit(alice, 7 * ONE_USDC);

        assertEq(savings.principalOf(alice), 12 * ONE_USDC);
        assertEq(savings.totalPrincipal(), 12 * ONE_USDC);
    }

    function test_MultipleUsersPrincipalSumEqualsTotal() public {
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 10 * ONE_USDC);
        _deposit(carol, 15 * ONE_USDC);

        assertEq(savings.totalPrincipal(), 30 * ONE_USDC);
        assertEq(
            savings.principalOf(alice) + savings.principalOf(bob) + savings.principalOf(carol), savings.totalPrincipal()
        );
        assertEq(usdc.balanceOf(address(savings)), savings.totalPrincipal());
    }

    function test_DirectDonationDoesNotChangePrincipal() public {
        _deposit(alice, 5 * ONE_USDC);

        vm.prank(alice);
        usdc.transfer(address(savings), 2 * ONE_USDC);

        assertEq(savings.principalOf(alice), 5 * ONE_USDC);
        assertEq(savings.totalPrincipal(), 5 * ONE_USDC);
        assertEq(usdc.balanceOf(address(savings)), 7 * ONE_USDC);
        assertGe(usdc.balanceOf(address(savings)), savings.totalPrincipal());
    }

    function test_DirectDonationBeforeAnyDepositDoesNotAffectPrincipal() public {
        vm.prank(alice);
        usdc.transfer(address(savings), 3 * ONE_USDC);

        assertEq(savings.totalPrincipal(), 0);
        assertEq(savings.principalOf(alice), 0);
        assertEq(usdc.balanceOf(address(savings)), 3 * ONE_USDC);

        _deposit(bob, 5 * ONE_USDC);
        assertEq(savings.principalOf(bob), 5 * ONE_USDC);
        assertEq(savings.totalPrincipal(), 5 * ONE_USDC);
        assertEq(usdc.balanceOf(address(savings)), 8 * ONE_USDC);
    }

    function test_WithdrawThenDepositAgain() public {
        _deposit(alice, 10 * ONE_USDC);
        _withdraw(alice, 10 * ONE_USDC);
        _deposit(alice, 3 * ONE_USDC);

        assertEq(savings.principalOf(alice), 3 * ONE_USDC);
        assertEq(savings.totalPrincipal(), 3 * ONE_USDC);
        assertEq(usdc.balanceOf(address(savings)), 3 * ONE_USDC);
    }

    function test_WithdrawPartial() public {
        _deposit(alice, 10 * ONE_USDC);
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.expectEmit(true, false, false, true, address(savings));
        emit Withdraw(alice, 4 * ONE_USDC, 6 * ONE_USDC);

        _withdraw(alice, 4 * ONE_USDC);

        assertEq(savings.principalOf(alice), 6 * ONE_USDC);
        assertEq(savings.totalPrincipal(), 6 * ONE_USDC);
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + 4 * ONE_USDC);
        assertEq(usdc.balanceOf(address(savings)), 6 * ONE_USDC);
    }

    function test_MultiplePartialWithdrawalsThenFullWithdraw() public {
        _deposit(alice, 10 * ONE_USDC);
        _withdraw(alice, 3 * ONE_USDC);
        _withdraw(alice, 2 * ONE_USDC);
        assertEq(savings.principalOf(alice), 5 * ONE_USDC);

        _withdraw(alice, 5 * ONE_USDC);
        assertEq(savings.principalOf(alice), 0);
        assertEq(savings.totalPrincipal(), 0);
        assertEq(usdc.balanceOf(address(savings)), 0);
    }

    function test_WithdrawFull() public {
        _deposit(alice, 10 * ONE_USDC);
        _withdraw(alice, 10 * ONE_USDC);

        assertEq(savings.principalOf(alice), 0);
        assertEq(savings.totalPrincipal(), 0);
        assertEq(usdc.balanceOf(address(savings)), 0);
    }

    function test_WithdrawOnlyOwnPrincipal() public {
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);

        _withdraw(alice, 5 * ONE_USDC);

        assertEq(savings.principalOf(alice), 0);
        assertEq(savings.principalOf(bob), 5 * ONE_USDC);
        assertEq(savings.totalPrincipal(), 5 * ONE_USDC);
        assertEq(usdc.balanceOf(address(savings)), 5 * ONE_USDC);
    }

    function test_RevertWhen_WithdrawExceedsPrincipal() public {
        _deposit(alice, 5 * ONE_USDC);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                StreakSavings.StreakSavings__InsufficientPrincipal.selector, 6 * ONE_USDC, 5 * ONE_USDC
            )
        );
        savings.withdraw(6 * ONE_USDC);

        assertEq(savings.principalOf(alice), 5 * ONE_USDC);
        assertEq(savings.totalPrincipal(), 5 * ONE_USDC);
    }

    function test_RevertWhen_WithdrawWithoutDeposit() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(StreakSavings.StreakSavings__InsufficientPrincipal.selector, ONE_USDC, 0)
        );
        savings.withdraw(ONE_USDC);
    }

    function test_RevertWhen_DepositZero() public {
        vm.prank(alice);
        vm.expectRevert(StreakSavings.StreakSavings__ZeroAmount.selector);
        savings.deposit(0);
    }

    function test_RevertWhen_WithdrawZero() public {
        _deposit(alice, ONE_USDC);

        vm.prank(alice);
        vm.expectRevert(StreakSavings.StreakSavings__ZeroAmount.selector);
        savings.withdraw(0);
    }

    function test_RevertWhen_DepositWithoutApproval() public {
        vm.prank(carol);
        usdc.approve(address(savings), 0);

        vm.prank(carol);
        vm.expectRevert();
        savings.deposit(ONE_USDC);

        assertEq(savings.totalPrincipal(), 0);
        assertEq(savings.principalOf(carol), 0);
    }

    function test_RevertWhen_DepositExceedsBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        savings.deposit(USER_FUNDS + 1);

        assertEq(savings.totalPrincipal(), 0);
        assertEq(savings.principalOf(alice), 0);
    }

    function test_ContractBalanceCoversPrincipal() public {
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 7 * ONE_USDC);

        assertGe(usdc.balanceOf(address(savings)), savings.totalPrincipal());
        assertEq(usdc.balanceOf(address(savings)), 12 * ONE_USDC);
    }

    function test_RevertWhen_FeeOnTransferDeposit() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        StreakSavings feeSavings = new StreakSavings(IERC20(address(feeToken)), DEFAULT_EPOCH_DURATION);

        feeToken.mint(alice, 100 * ONE_USDC);
        vm.prank(alice);
        feeToken.approve(address(feeSavings), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                StreakSavings.StreakSavings__TransferMismatch.selector, 100 * ONE_USDC, 99 * ONE_USDC
            )
        );
        feeSavings.deposit(100 * ONE_USDC);

        assertEq(feeSavings.totalPrincipal(), 0);
        assertEq(feeSavings.principalOf(alice), 0);
        assertEq(feeToken.balanceOf(address(feeSavings)), 0);
    }

    function test_RevertWhen_DepositReenters() public {
        ReentrantToken reentrantToken = new ReentrantToken();
        StreakSavings reentrantSavings = new StreakSavings(IERC20(address(reentrantToken)), DEFAULT_EPOCH_DURATION);

        reentrantToken.setTarget(reentrantSavings);
        reentrantToken.mint(alice, 10 * ONE_USDC);
        vm.prank(alice);
        reentrantToken.approve(address(reentrantSavings), type(uint256).max);
        reentrantToken.setReentryEnabled(true);

        vm.prank(alice);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reentrantSavings.deposit(ONE_USDC);

        assertEq(reentrantSavings.totalPrincipal(), 0);
    }

    function test_RevertWhen_WithdrawReenters() public {
        ReentrantToken reentrantToken = new ReentrantToken();
        StreakSavings reentrantSavings = new StreakSavings(IERC20(address(reentrantToken)), DEFAULT_EPOCH_DURATION);

        reentrantToken.setTarget(reentrantSavings);
        reentrantToken.mint(alice, 10 * ONE_USDC);
        vm.prank(alice);
        reentrantToken.approve(address(reentrantSavings), type(uint256).max);

        vm.prank(alice);
        reentrantSavings.deposit(5 * ONE_USDC);

        reentrantToken.setReentryEnabled(true);

        vm.prank(alice);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reentrantSavings.withdraw(ONE_USDC);

        assertEq(reentrantSavings.principalOf(alice), 5 * ONE_USDC);
        assertEq(reentrantSavings.totalPrincipal(), 5 * ONE_USDC);
    }

    // ---------------------------------------------------------------------
    // Group C — Epoch clock and boundaries
    // ---------------------------------------------------------------------

    function test_Epoch_InitialEpochAtDeployment() public view {
        uint256 start = savings.startTime();
        assertEq(savings.currentEpoch(), 0);
        assertEq(savings.epochStart(0), start);
        assertEq(savings.epochEnd(0), start + DEFAULT_EPOCH_DURATION);
        assertEq(savings.nextEpochTimestamp(), start + DEFAULT_EPOCH_DURATION);
        assertEq(savings.timeUntilNextEpoch(), DEFAULT_EPOCH_DURATION);
    }

    function test_Epoch_OneSecondBeforeBoundary() public {
        uint256 start = savings.startTime();
        vm.warp(start + DEFAULT_EPOCH_DURATION - 1);

        assertEq(savings.currentEpoch(), 0);
        assertEq(savings.timeUntilNextEpoch(), 1);
        assertEq(savings.nextEpochTimestamp(), start + DEFAULT_EPOCH_DURATION);
    }

    function test_Epoch_ExactBoundaryTransition() public {
        uint256 start = savings.startTime();
        vm.warp(start + DEFAULT_EPOCH_DURATION);

        assertEq(savings.currentEpoch(), 1);
        assertEq(savings.epochStart(1), start + DEFAULT_EPOCH_DURATION);
        assertEq(savings.epochEnd(1), start + 2 * DEFAULT_EPOCH_DURATION);
        assertEq(savings.timeUntilNextEpoch(), DEFAULT_EPOCH_DURATION);
    }

    function test_Epoch_OneSecondAfterBoundary() public {
        uint256 start = savings.startTime();
        vm.warp(start + DEFAULT_EPOCH_DURATION + 1);

        assertEq(savings.currentEpoch(), 1);
        assertEq(savings.timeUntilNextEpoch(), DEFAULT_EPOCH_DURATION - 1);
    }

    function test_Epoch_MultiEpochProgression() public {
        uint256 start = savings.startTime();
        vm.warp(start + 5 * DEFAULT_EPOCH_DURATION + 17);

        assertEq(savings.currentEpoch(), 5);
        assertEq(savings.epochStart(5), start + 5 * DEFAULT_EPOCH_DURATION);
        assertEq(savings.epochEnd(5), start + 6 * DEFAULT_EPOCH_DURATION);
        assertEq(savings.timeUntilNextEpoch(), DEFAULT_EPOCH_DURATION - 17);
    }

    function test_Epoch_ConfigurableSevenDayProductionDuration() public {
        StreakSavings prodSavings = new StreakSavings(IERC20(address(usdc)), PROD_EPOCH_DURATION);
        uint256 start = prodSavings.startTime();

        assertEq(prodSavings.epochDuration(), PROD_EPOCH_DURATION);
        assertEq(prodSavings.currentEpoch(), 0);

        vm.warp(start + PROD_EPOCH_DURATION - 1);
        assertEq(prodSavings.currentEpoch(), 0);
        assertEq(prodSavings.timeUntilNextEpoch(), 1);

        vm.warp(start + PROD_EPOCH_DURATION);
        assertEq(prodSavings.currentEpoch(), 1);
        assertEq(prodSavings.timeUntilNextEpoch(), PROD_EPOCH_DURATION);
    }

    function test_Epoch_EpochAtViewAndRevertWhenBeforeStart() public {
        vm.warp(1_700_000_000);
        StreakSavings timedSavings = new StreakSavings(IERC20(address(usdc)), DEFAULT_EPOCH_DURATION);
        uint256 start = timedSavings.startTime();

        assertEq(timedSavings.epochAt(start), 0);
        assertEq(timedSavings.epochAt(start + 59), 0);
        assertEq(timedSavings.epochAt(start + 60), 1);
        assertEq(timedSavings.epochAt(start + 185), 3);

        vm.expectRevert(
            abi.encodeWithSelector(StreakSavings.StreakSavings__TimestampBeforeStart.selector, start - 1, start)
        );
        timedSavings.epochAt(start - 1);
    }

    function test_Epoch_EpochAtRevertWhen_OverflowUint64() public {
        StreakSavings oneSecondEpoch = new StreakSavings(IERC20(address(usdc)), 1);
        uint256 overflowValue = uint256(type(uint64).max) + 1;
        uint256 overflowTimestamp = uint256(oneSecondEpoch.startTime()) + overflowValue;

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 64, overflowValue));
        oneSecondEpoch.epochAt(overflowTimestamp);
    }

    // ---------------------------------------------------------------------
    // Fuzz tests (principal and epoch clock)
    // ---------------------------------------------------------------------

    function testFuzz_DepositWithdrawKeepAccountingInSync(
        uint256 aliceAmount,
        uint256 bobAmount,
        uint256 withdrawAmount
    ) public {
        aliceAmount = bound(aliceAmount, 1, 1_000 * ONE_USDC);
        bobAmount = bound(bobAmount, 1, 1_000 * ONE_USDC);
        withdrawAmount = bound(withdrawAmount, 0, aliceAmount);

        _deposit(alice, aliceAmount);
        _deposit(bob, bobAmount);

        if (withdrawAmount > 0) {
            _withdraw(alice, withdrawAmount);
        }

        uint256 aliceRemaining = aliceAmount - withdrawAmount;

        assertEq(savings.principalOf(alice), aliceRemaining);
        assertEq(savings.principalOf(bob), bobAmount);
        assertEq(savings.totalPrincipal(), aliceRemaining + bobAmount);
        assertEq(usdc.balanceOf(address(savings)), savings.totalPrincipal());
    }

    function testFuzz_MultipleUsersSumEqualsTotal(uint256 aliceAmount, uint256 bobAmount, uint256 carolAmount) public {
        aliceAmount = bound(aliceAmount, 1, 1_000 * ONE_USDC);
        bobAmount = bound(bobAmount, 1, 1_000 * ONE_USDC);
        carolAmount = bound(carolAmount, 1, 1_000 * ONE_USDC);

        _deposit(alice, aliceAmount);
        _deposit(bob, bobAmount);
        _deposit(carol, carolAmount);

        assertEq(
            savings.principalOf(alice) + savings.principalOf(bob) + savings.principalOf(carol), savings.totalPrincipal()
        );
        assertGe(usdc.balanceOf(address(savings)), savings.totalPrincipal());
    }

    function testFuzz_Epoch_BoundariesAndCountdownAreConsistent(uint64 duration, uint64 elapsed) public {
        duration = uint64(bound(duration, 1, 365 days));
        elapsed = uint64(bound(elapsed, 0, 10 * 365 days));

        StreakSavings customSavings = new StreakSavings(IERC20(address(usdc)), duration);
        uint256 start = customSavings.startTime();
        uint256 targetTime = start + uint256(elapsed);

        vm.warp(targetTime);

        uint64 ep = customSavings.currentEpoch();
        assertEq(ep, customSavings.epochAt(targetTime));
        assertEq(uint256(ep), uint256(elapsed) / uint256(duration));
        assertLe(customSavings.epochStart(ep), targetTime);
        assertGt(customSavings.epochEnd(ep), targetTime);
        assertEq(customSavings.epochEnd(ep) - customSavings.epochStart(ep), duration);
        assertEq(customSavings.nextEpochTimestamp(), customSavings.epochEnd(ep));
        assertEq(customSavings.timeUntilNextEpoch(), customSavings.epochEnd(ep) - targetTime);
        assertGt(customSavings.timeUntilNextEpoch(), 0);
        assertLe(customSavings.timeUntilNextEpoch(), duration);
    }
}
