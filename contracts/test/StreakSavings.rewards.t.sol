// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {StreakSavings} from "../src/StreakSavings.sol";

/// @dev Test-only token that attempts a nested deposit during a reward transfer.
contract RewardReentrantToken is ERC20 {
    StreakSavings private target;
    bool private reentryEnabled;

    constructor() ERC20("Reward Reentrant Token", "RRT") {}

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

/// @title StreakSavingsRewardsTest
/// @notice End-to-end contract-level integration tests for BR-01..BR-06 and T1–T8.
contract StreakSavingsRewardsTest is Test {
    uint256 private constant ONE_USDC = 1e6;
    uint256 private constant USER_FUNDS = 10_000 * ONE_USDC;
    uint256 private constant PROVIDER_FUNDS = 100_000 * ONE_USDC;
    uint64 private constant EPOCH = 60;

    MockUSDC private usdc;
    StreakSavings private savings;

    address private alice;
    address private bob;
    address private carol;

    function setUp() public {
        usdc = new MockUSDC();
        savings = new StreakSavings(IERC20(address(usdc)), EPOCH);

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        usdc.mint(alice, USER_FUNDS);
        usdc.mint(bob, USER_FUNDS);
        usdc.mint(carol, USER_FUNDS);
        usdc.mint(address(this), PROVIDER_FUNDS);

        vm.prank(alice);
        usdc.approve(address(savings), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(savings), type(uint256).max);
        vm.prank(carol);
        usdc.approve(address(savings), type(uint256).max);
        usdc.approve(address(savings), type(uint256).max);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _warpToEpoch(uint64 epoch) private {
        vm.warp(uint256(savings.startTime()) + uint256(epoch) * uint256(EPOCH));
    }

    function _deposit(address user, uint256 amount) private {
        vm.prank(user);
        savings.deposit(amount);
    }

    function _withdraw(address user, uint256 amount) private {
        vm.prank(user);
        savings.withdraw(amount);
    }

    function _addYield(uint256 amount) private {
        savings.addMockYield(amount);
    }

    function _claim(address user, uint64 epoch) private {
        vm.prank(user);
        savings.claimRewardFor(epoch);
    }

    // ---------------------------------------------------------------------
    // T1 — Alice deposits before Bob
    // ---------------------------------------------------------------------

    function test_T1_EarlierDepositAndEqualWeightsGetEqualShares() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);
        _addYield(10 * ONE_USDC);

        assertEq(savings.weightInEpoch(alice, 0), 1);
        assertEq(savings.weightInEpoch(bob, 0), 1);
        assertEq(savings.totalWeightInEpoch(0), 2);

        _warpToEpoch(1);
        assertEq(savings.rewardOf(alice), 5 * ONE_USDC);
        assertEq(savings.rewardOf(bob), 5 * ONE_USDC);

        _claim(alice, 0);
        _claim(bob, 0);

        assertEq(savings.principalOf(alice), 5 * ONE_USDC);
        assertEq(savings.principalOf(bob), 5 * ONE_USDC);
        assertEq(savings.totalRewardPool(), 0);
    }

    // ---------------------------------------------------------------------
    // T2 — Different streak ratios
    // ---------------------------------------------------------------------

    function test_T2_RewardRatioEqualsStreakWeightRatio() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);

        _warpToEpoch(1);
        _deposit(alice, 5 * ONE_USDC);

        _warpToEpoch(2);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);

        _warpToEpoch(3);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        assertEq(savings.streakOf(alice), 4);
        assertEq(savings.streakOf(bob), 2);
        assertEq(savings.weightInEpoch(alice, 3), 4);
        assertEq(savings.weightInEpoch(bob, 3), 2);
        assertEq(savings.totalWeightInEpoch(3), 6);

        _warpToEpoch(4);
        assertEq(savings.rewardOf(alice), 4 * ONE_USDC);
        assertEq(savings.rewardOf(bob), 2 * ONE_USDC);

        _claim(alice, 3);
        _claim(bob, 3);

        assertEq(savings.principalOf(alice), 20 * ONE_USDC);
        assertEq(savings.principalOf(bob), 10 * ONE_USDC);
        assertEq(savings.totalRewardPool(), 0);
    }

    // ---------------------------------------------------------------------
    // T3 — Multiple yield additions
    // ---------------------------------------------------------------------

    function test_T3_MultipleYieldAdditionsSumInOneEpoch() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);

        _addYield(2 * ONE_USDC);
        _addYield(4 * ONE_USDC);

        assertEq(savings.rewardPoolInEpoch(0), 6 * ONE_USDC);
        assertEq(savings.totalRewardPool(), 6 * ONE_USDC);

        _warpToEpoch(1);
        assertEq(savings.rewardInEpoch(alice, 0), 3 * ONE_USDC);
        assertEq(savings.rewardInEpoch(bob, 0), 3 * ONE_USDC);

        _claim(alice, 0);
        _claim(bob, 0);
        assertEq(savings.totalRewardPool(), 0);
    }

    // ---------------------------------------------------------------------
    // T4 — Claim between yield additions
    // ---------------------------------------------------------------------

    function test_T4_EarlierClaimDoesNotAffectLaterEpochPool() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _warpToEpoch(1);
        _claim(alice, 0);

        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _warpToEpoch(2);
        assertEq(savings.rewardPoolInEpoch(0), 6 * ONE_USDC);
        assertEq(savings.rewardInEpoch(alice, 0), 0);
        assertEq(savings.rewardInEpoch(bob, 0), 3 * ONE_USDC);

        assertEq(savings.rewardInEpoch(alice, 1), 3 * ONE_USDC);
        assertEq(savings.rewardInEpoch(bob, 1), 3 * ONE_USDC);

        _claim(alice, 1);
        _claim(bob, 0);
        _claim(bob, 1);

        assertEq(savings.totalRewardPool(), 0);
    }

    // ---------------------------------------------------------------------
    // T5 — Bob claims last
    // ---------------------------------------------------------------------

    function test_T5_ClaimOrderDoesNotChangeShares() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _warpToEpoch(1);
        _claim(alice, 0);
        _claim(bob, 0);

        assertEq(usdc.balanceOf(alice), USER_FUNDS - 5 * ONE_USDC + 3 * ONE_USDC);
        assertEq(usdc.balanceOf(bob), USER_FUNDS - 5 * ONE_USDC + 3 * ONE_USDC);
        assertEq(savings.totalRewardPool(), 0);
    }

    // ---------------------------------------------------------------------
    // T6 — Weight changes and immutable finalized snapshots
    // ---------------------------------------------------------------------

    function test_T6_LaterWeightChangesDoNotAlterFinalizedEpoch() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _warpToEpoch(1);
        _deposit(alice, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        assertEq(savings.weightInEpoch(alice, 0), 1);
        assertEq(savings.weightInEpoch(bob, 0), 1);
        assertEq(savings.totalWeightInEpoch(0), 2);
        assertEq(savings.weightInEpoch(bob, 1), 0);
        assertEq(savings.totalWeightInEpoch(1), 2);

        _warpToEpoch(2);
        assertEq(savings.rewardInEpoch(alice, 0), 3 * ONE_USDC);
        assertEq(savings.rewardInEpoch(bob, 0), 3 * ONE_USDC);
        assertEq(savings.rewardInEpoch(alice, 1), 6 * ONE_USDC);
        assertEq(savings.rewardInEpoch(bob, 1), 0);

        _claim(alice, 0);
        _claim(bob, 0);
        _claim(alice, 1);

        assertEq(savings.totalRewardPool(), 0);
    }

    // ---------------------------------------------------------------------
    // T7 — Withdrawal followed by yield
    // ---------------------------------------------------------------------

    function test_T7_WithdrawalAndYieldDoNotMixPrincipalWithRewards() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _warpToEpoch(1);
        _withdraw(bob, 5 * ONE_USDC);
        assertEq(savings.principalOf(bob), 0);
        assertEq(savings.streakOf(bob), 0);
        assertEq(savings.weightOf(bob), 0);

        _deposit(alice, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _warpToEpoch(2);
        _claim(bob, 0);
        _claim(alice, 0);
        _claim(alice, 1);

        assertEq(savings.principalOf(alice), 10 * ONE_USDC);
        assertEq(savings.principalOf(bob), 0);
        assertEq(savings.totalPrincipal(), 10 * ONE_USDC);
        assertEq(usdc.balanceOf(address(savings)), 10 * ONE_USDC);

        _withdraw(alice, 10 * ONE_USDC);
        assertEq(usdc.balanceOf(address(savings)), 0);
    }

    // ---------------------------------------------------------------------
    // T8 — Claim does not consume principal
    // ---------------------------------------------------------------------

    function test_T8_ClaimLeavesPrincipalFullyWithdrawable() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _addYield(10 * ONE_USDC);

        _warpToEpoch(1);
        _claim(alice, 0);

        assertEq(savings.principalOf(alice), 5 * ONE_USDC);
        assertEq(savings.totalPrincipal(), 5 * ONE_USDC);
        assertEq(savings.totalRewardPool(), 0);

        _withdraw(alice, 5 * ONE_USDC);
        assertEq(savings.principalOf(alice), 0);
        assertEq(savings.totalPrincipal(), 0);
        assertEq(usdc.balanceOf(address(savings)), 0);
    }

    // ---------------------------------------------------------------------
    // Streak and epoch rules
    // ---------------------------------------------------------------------

    function test_MultipleDepositsSameEpochNeverIncrementStreak() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(alice, 7 * ONE_USDC);
        _deposit(alice, 1 * ONE_USDC);

        assertEq(savings.streakOf(alice), 1);
        assertEq(savings.weightOf(alice), 1);
        assertEq(savings.weightInEpoch(alice, 0), 1);
        assertEq(savings.totalWeightInEpoch(0), 1);
        assertEq(savings.totalPrincipal(), 13 * ONE_USDC);

        _addYield(10 * ONE_USDC);
        _warpToEpoch(1);
        _claim(alice, 0);

        assertEq(savings.principalOf(alice), 13 * ONE_USDC);
        assertEq(savings.totalRewardPool(), 0);
    }

    function test_ConsecutiveEpochsIncrementStreakByOne() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        assertEq(savings.streakOf(alice), 1);

        _warpToEpoch(1);
        _deposit(alice, 5 * ONE_USDC);
        assertEq(savings.streakOf(alice), 2);

        _warpToEpoch(2);
        _deposit(alice, 5 * ONE_USDC);
        assertEq(savings.streakOf(alice), 3);
        assertEq(savings.weightOf(alice), 3);
        assertEq(savings.totalWeight(), 3);
        assertEq(savings.weightInEpoch(alice, 2), 3);
    }

    function test_MissingEpochResetsStreakToOne() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);

        _warpToEpoch(1);
        assertEq(savings.effectiveStreakOf(alice), 1);

        _warpToEpoch(2);
        assertEq(savings.effectiveStreakOf(alice), 0);
        assertEq(savings.streakOf(alice), 1);

        _deposit(alice, 5 * ONE_USDC);
        assertEq(savings.streakOf(alice), 1);
        assertEq(savings.weightInEpoch(alice, 2), 1);
        assertEq(savings.weightInEpoch(alice, 1), 0);
    }

    function test_FullWithdrawalResetsStreakAndStartsFresh() public {
        _warpToEpoch(0);
        _deposit(alice, 10 * ONE_USDC);

        _warpToEpoch(1);
        _deposit(alice, 10 * ONE_USDC);
        assertEq(savings.streakOf(alice), 2);
        assertEq(savings.totalWeight(), 2);

        _withdraw(alice, 20 * ONE_USDC);

        assertEq(savings.principalOf(alice), 0);
        assertEq(savings.streakOf(alice), 0);
        assertEq(savings.weightOf(alice), 0);
        assertEq(savings.totalWeight(), 0);
        assertEq(savings.totalWeightInEpoch(1), 0);
        assertEq(savings.lastDepositEpochOf(alice), 0);

        _deposit(alice, 5 * ONE_USDC);
        assertEq(savings.streakOf(alice), 1);
        assertEq(savings.weightOf(alice), 1);
        assertEq(savings.totalWeight(), 1);
        assertEq(savings.weightInEpoch(alice, 1), 1);
    }

    function test_PartialWithdrawalPreservesStreakAndWeight() public {
        _warpToEpoch(0);
        _deposit(alice, 10 * ONE_USDC);
        _withdraw(alice, 4 * ONE_USDC);

        assertEq(savings.principalOf(alice), 6 * ONE_USDC);
        assertEq(savings.streakOf(alice), 1);
        assertEq(savings.weightOf(alice), 1);

        _warpToEpoch(1);
        _deposit(alice, 5 * ONE_USDC);
        assertEq(savings.streakOf(alice), 2);
        assertEq(savings.weightOf(alice), 2);
    }

    function test_ZeroPrincipalHasZeroWeightAndCannotBeFunded() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _withdraw(alice, 5 * ONE_USDC);

        assertEq(savings.principalOf(alice), 0);
        assertEq(savings.weightOf(alice), 0);
        assertEq(savings.totalWeight(), 0);
        assertEq(savings.totalWeightInEpoch(0), 0);

        vm.expectRevert(abi.encodeWithSelector(StreakSavings.StreakSavings__NoActiveWeight.selector, uint64(0)));
        _addYield(ONE_USDC);
    }

    function test_EpochBoundaryDepositCountsForNewEpoch() public {
        uint256 start = savings.startTime();

        vm.warp(start + EPOCH - 1);
        _deposit(alice, 5 * ONE_USDC);
        assertEq(savings.lastDepositEpochOf(alice), 0);

        vm.warp(start + EPOCH);
        _deposit(alice, 5 * ONE_USDC);
        assertEq(savings.lastDepositEpochOf(alice), 1);
        assertEq(savings.streakOf(alice), 2);

        vm.warp(start + 2 * EPOCH);
        _deposit(alice, 5 * ONE_USDC);
        assertEq(savings.lastDepositEpochOf(alice), 2);
        assertEq(savings.streakOf(alice), 3);
    }

    // ---------------------------------------------------------------------
    // Claim safety and reward-solvency edge cases
    // ---------------------------------------------------------------------

    function test_ClaimReward_NoArgsClaimsLatestFinalizedEpochOnly() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _warpToEpoch(1);
        _deposit(alice, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _warpToEpoch(2);
        vm.prank(alice);
        savings.claimReward();

        assertEq(savings.rewardInEpoch(alice, 1), 0);
        assertEq(savings.rewardInEpoch(alice, 0), 6 * ONE_USDC);
        assertEq(savings.totalRewardPool(), 6 * ONE_USDC);

        _claim(alice, 0);
        assertEq(savings.totalRewardPool(), 0);
    }

    function test_DoubleClaimReverts() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _warpToEpoch(1);
        _claim(alice, 0);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(StreakSavings.StreakSavings__RewardAlreadyClaimed.selector, alice, uint64(0))
        );
        savings.claimRewardFor(0);
    }

    function test_ClaimBeforeFinalizedEpochReverts() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(StreakSavings.StreakSavings__EpochNotFinalized.selector, uint64(0), uint64(0))
        );
        savings.claimRewardFor(0);

        vm.prank(alice);
        vm.expectRevert(StreakSavings.StreakSavings__NoFinalizedEpoch.selector);
        savings.claimReward();
    }

    function test_OldRewardRemainsClaimableAfterManyEpochs() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _warpToEpoch(100);
        assertEq(savings.rewardOf(alice), 0);
        assertEq(savings.rewardInEpoch(alice, 0), 6 * ONE_USDC);

        _claim(alice, 0);
        assertEq(savings.totalRewardPool(), 0);
        assertEq(savings.principalOf(alice), 5 * ONE_USDC);
    }

    function test_RoundingDustStaysBackedAndUnallocated() public {
        _warpToEpoch(0);
        _deposit(bob, 5 * ONE_USDC);

        _warpToEpoch(1);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);
        _addYield(10 * ONE_USDC);

        assertEq(savings.weightInEpoch(alice, 1), 1);
        assertEq(savings.weightInEpoch(bob, 1), 2);
        assertEq(savings.totalWeightInEpoch(1), 3);

        _warpToEpoch(2);
        assertEq(savings.rewardInEpoch(alice, 1), 3_333_333);
        assertEq(savings.rewardInEpoch(bob, 1), 6_666_666);

        _claim(alice, 1);
        _claim(bob, 1);

        uint256 dust = 1;
        assertEq(savings.totalRewardPool(), dust);
        assertEq(savings.totalPrincipal(), 15 * ONE_USDC);
        assertEq(usdc.balanceOf(address(savings)), 15 * ONE_USDC + dust);

        _withdraw(alice, 5 * ONE_USDC);
        _withdraw(bob, 10 * ONE_USDC);
        assertEq(savings.principalOf(alice), 0);
        assertEq(savings.principalOf(bob), 0);
        assertEq(usdc.balanceOf(address(savings)), dust);
    }

    function test_FullWithdrawalAfterYieldLeavesPoolUnallocated() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);
        _addYield(6 * ONE_USDC);

        _withdraw(alice, 5 * ONE_USDC);
        _withdraw(bob, 5 * ONE_USDC);

        assertEq(savings.totalWeightInEpoch(0), 0);
        assertEq(savings.rewardPoolInEpoch(0), 6 * ONE_USDC);
        assertEq(savings.totalRewardPool(), 6 * ONE_USDC);

        _warpToEpoch(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StreakSavings.StreakSavings__NoReward.selector, alice, uint64(0)));
        savings.claimRewardFor(0);
    }

    function test_UnauthorizedYieldProviderReverts() public {
        _warpToEpoch(0);
        _deposit(alice, 5 * ONE_USDC);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StreakSavings.StreakSavings__UnauthorizedYieldProvider.selector, alice));
        savings.addMockYield(ONE_USDC);
    }

    function test_RevertWhen_AddYieldWithoutWeight() public {
        vm.expectRevert(abi.encodeWithSelector(StreakSavings.StreakSavings__NoActiveWeight.selector, uint64(0)));
        _addYield(ONE_USDC);
    }

    function test_RevertWhen_ClaimReenters() public {
        RewardReentrantToken token = new RewardReentrantToken();
        StreakSavings reentrantSavings = new StreakSavings(IERC20(address(token)), EPOCH);

        token.setTarget(reentrantSavings);
        token.mint(alice, 10 * ONE_USDC);
        token.mint(address(this), 10 * ONE_USDC);
        vm.prank(alice);
        token.approve(address(reentrantSavings), type(uint256).max);
        token.approve(address(reentrantSavings), type(uint256).max);

        vm.prank(alice);
        reentrantSavings.deposit(5 * ONE_USDC);
        reentrantSavings.addMockYield(5 * ONE_USDC);

        vm.warp(uint256(reentrantSavings.startTime()) + uint256(EPOCH));
        token.setReentryEnabled(true);

        vm.prank(alice);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reentrantSavings.claimRewardFor(0);

        assertEq(reentrantSavings.principalOf(alice), 5 * ONE_USDC);
        assertEq(reentrantSavings.totalRewardPool(), 5 * ONE_USDC);
    }

    // ---------------------------------------------------------------------
    // Fuzz integration tests
    // ---------------------------------------------------------------------

    function testFuzz_SameEpochDepositsNeverIncrementStreak(uint8 count, uint96 amount) public {
        count = uint8(bound(count, 1, 20));
        amount = uint96(bound(amount, 1, 100 * ONE_USDC));

        _warpToEpoch(0);
        for (uint256 i = 0; i < count; i++) {
            _deposit(alice, amount);
        }

        assertEq(savings.streakOf(alice), 1);
        assertEq(savings.weightOf(alice), 1);
        assertEq(savings.totalWeight(), 1);
        assertEq(savings.totalPrincipal(), uint256(amount) * count);
        assertEq(savings.weightInEpoch(alice, 0), 1);
        assertEq(savings.totalWeightInEpoch(0), 1);
    }

    function testFuzz_RewardSharesNeverExceedPool(uint96 pool) public {
        pool = uint96(bound(pool, 0, 1_000 * ONE_USDC));

        _warpToEpoch(0);
        _deposit(bob, 5 * ONE_USDC);

        _warpToEpoch(1);
        _deposit(alice, 5 * ONE_USDC);
        _deposit(bob, 5 * ONE_USDC);

        if (pool > 0) {
            _addYield(pool);
        }

        _warpToEpoch(2);
        uint256 aliceShare = savings.rewardInEpoch(alice, 1);
        uint256 bobShare = savings.rewardInEpoch(bob, 1);

        assertLe(aliceShare + bobShare, pool);
        assertEq(savings.totalPrincipal(), 15 * ONE_USDC);
        assertGe(usdc.balanceOf(address(savings)), savings.totalPrincipal() + savings.totalRewardPool());
    }
}
