// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

contract StreakSavingsTest is Test {
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount, uint256 principalRemaining);

    uint256 private constant ONE_USDC = 1e6;
    uint256 private constant USER_FUNDS = 10_000 * ONE_USDC;

    MockUSDC private usdc;
    StreakSavings private savings;

    address private alice;
    address private bob;
    address private carol;

    function setUp() public {
        usdc = new MockUSDC();
        savings = new StreakSavings(IERC20(address(usdc)));

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
        assertEq(savings.totalPrincipal(), 0);
        assertEq(savings.principalOf(alice), 0);
        assertEq(usdc.balanceOf(address(savings)), 0);
    }

    function test_ConstructorRejectsZeroToken() public {
        vm.expectRevert(StreakSavings.StreakSavings__InvalidToken.selector);
        new StreakSavings(IERC20(address(0)));
    }

    function test_ConstructorRejectsNonContractToken() public {
        vm.expectRevert(StreakSavings.StreakSavings__InvalidToken.selector);
        new StreakSavings(IERC20(address(0xBEEF)));
    }

    // ---------------------------------------------------------------------
    // P1 — principal accounting consistency
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

    function test_WithdrawThenDepositAgain() public {
        _deposit(alice, 10 * ONE_USDC);
        _withdraw(alice, 10 * ONE_USDC);
        _deposit(alice, 3 * ONE_USDC);

        assertEq(savings.principalOf(alice), 3 * ONE_USDC);
        assertEq(savings.totalPrincipal(), 3 * ONE_USDC);
        assertEq(usdc.balanceOf(address(savings)), 3 * ONE_USDC);
    }

    // ---------------------------------------------------------------------
    // P2 — withdrawal limits and partial/full withdrawal
    // ---------------------------------------------------------------------

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

    // ---------------------------------------------------------------------
    // P6 — the contract balance always covers recorded principal
    // ---------------------------------------------------------------------

    function test_ContractBalanceCoversPrincipal() public {
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 7 * ONE_USDC);

        assertGe(usdc.balanceOf(address(savings)), savings.totalPrincipal());
        assertEq(usdc.balanceOf(address(savings)), 12 * ONE_USDC);
    }

    function test_RevertWhen_FeeOnTransferDeposit() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        StreakSavings feeSavings = new StreakSavings(IERC20(address(feeToken)));

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

    // ---------------------------------------------------------------------
    // Fuzz invariants
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
}
