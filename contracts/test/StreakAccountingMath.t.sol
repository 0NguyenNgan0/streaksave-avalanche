// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StreakAccountingMath} from "../src/libraries/StreakAccountingMath.sol";

/// @dev External wrapper around StreakAccountingMath so revert expectations operate across
///      a clean external call frame.
contract StreakAccountingMathHarness {
    function computeEpoch(uint256 timestamp, uint256 startTime, uint256 epochDuration) external pure returns (uint64) {
        return StreakAccountingMath.computeEpoch(timestamp, startTime, epochDuration);
    }

    function classifyEpochTransition(uint64 lastDepositEpoch, uint64 currentEpoch, bool hasDepositedBefore)
        external
        pure
        returns (StreakAccountingMath.EpochRelation)
    {
        return StreakAccountingMath.classifyEpochTransition(lastDepositEpoch, currentEpoch, hasDepositedBefore);
    }

    function computeConfirmedStreakTransition(uint64 currentStreak, StreakAccountingMath.EpochRelation relation)
        external
        pure
        returns (uint64)
    {
        return StreakAccountingMath.computeConfirmedStreakTransition(currentStreak, relation);
    }

    function applyWeightDelta(uint256 currentTotalWeight, uint256 oldUserWeight, uint256 newUserWeight)
        external
        pure
        returns (uint256)
    {
        return StreakAccountingMath.applyWeightDelta(currentTotalWeight, oldUserWeight, newUserWeight);
    }

    function computeEpochRewardShare(uint256 epochRewardPool, uint256 userWeight, uint256 totalWeight)
        external
        pure
        returns (uint256)
    {
        return StreakAccountingMath.computeEpochRewardShare(epochRewardPool, userWeight, totalWeight);
    }

    function computeAccumulatorDelta(uint256 yieldAmount, uint256 totalWeight, uint256 precision)
        external
        pure
        returns (uint256)
    {
        return StreakAccountingMath.computeAccumulatorDelta(yieldAmount, totalWeight, precision);
    }

    function computeAccruedReward(uint256 userWeight, uint256 accRewardPerWeight, uint256 rewardDebt, uint256 precision)
        external
        pure
        returns (uint256)
    {
        return StreakAccountingMath.computeAccruedReward(userWeight, accRewardPerWeight, rewardDebt, precision);
    }
}

/// @title StreakAccountingMathTest
/// @notice Unit and fuzz verification for Groups D, E and F math primitives.
/// @dev Stateful integration on StreakSavings.sol remains intentionally gated on
///      unresolved team decisions BL-01, BL-02, BL-03, BL-10, BL-11 and BL-13.
contract StreakAccountingMathTest is Test {
    uint256 private constant ONE_USDC = 1e6;
    uint256 private constant PRECISION = 1e18;

    StreakAccountingMathHarness private math;

    function setUp() public {
        math = new StreakAccountingMathHarness();
    }

    // ---------------------------------------------------------------------
    // Group D — Confirmed streak transition rules & BL-01 gate
    // ---------------------------------------------------------------------

    function test_Streak_FirstDepositStartsAtOne() public view {
        StreakAccountingMath.EpochRelation rel = math.classifyEpochTransition(0, 5, false);
        assertEq(uint256(rel), uint256(StreakAccountingMath.EpochRelation.FirstDeposit));
        assertEq(math.computeConfirmedStreakTransition(0, rel), 1);
    }

    function test_Streak_ConsecutiveEpochIncrementsByOne() public view {
        StreakAccountingMath.EpochRelation rel = math.classifyEpochTransition(4, 5, true);
        assertEq(uint256(rel), uint256(StreakAccountingMath.EpochRelation.ConsecutiveEpoch));
        assertEq(math.computeConfirmedStreakTransition(3, rel), 4);
    }

    function test_Streak_MissedOneOrMoreEpochsResetsToOne() public view {
        StreakAccountingMath.EpochRelation missedOne = math.classifyEpochTransition(4, 6, true);
        assertEq(uint256(missedOne), uint256(StreakAccountingMath.EpochRelation.MissedEpoch));
        assertEq(math.computeConfirmedStreakTransition(10, missedOne), 1);

        StreakAccountingMath.EpochRelation missedMany = math.classifyEpochTransition(4, 100, true);
        assertEq(uint256(missedMany), uint256(StreakAccountingMath.EpochRelation.MissedEpoch));
        assertEq(math.computeConfirmedStreakTransition(10, missedMany), 1);
    }

    function test_Streak_RevertWhen_EpochGoesBackward() public {
        vm.expectRevert(abi.encodeWithSelector(StreakAccountingMath.StreakAccountingMath__BackwardEpoch.selector, 5, 4));
        math.classifyEpochTransition(5, 4, true);
    }

    /// @notice Verifies that same-epoch behavior (BL-01) is classified without guessing a
    ///         business outcome and explicitly reverts until team approval is recorded.
    function test_Streak_PendingBL01_SameEpochTransitionIsClassifiedAndGated() public {
        StreakAccountingMath.EpochRelation rel = math.classifyEpochTransition(7, 7, true);
        assertEq(uint256(rel), uint256(StreakAccountingMath.EpochRelation.SameEpoch));

        vm.expectRevert(StreakAccountingMath.StreakAccountingMath__UnapprovedSameEpochRule.selector);
        math.computeConfirmedStreakTransition(3, rel);
    }

    function testFuzz_Streak_ConfirmedConsecutiveAndResetRules(uint64 currentStreak, uint64 lastEpoch, uint64 gap)
        public
        view
    {
        currentStreak = uint64(bound(currentStreak, 1, type(uint64).max - 1));
        lastEpoch = uint64(bound(lastEpoch, 0, type(uint64).max - 10_000));
        gap = uint64(bound(gap, 1, 10_000));

        uint64 nextEpoch = lastEpoch + gap;
        StreakAccountingMath.EpochRelation rel = math.classifyEpochTransition(lastEpoch, nextEpoch, true);
        uint64 updated = math.computeConfirmedStreakTransition(currentStreak, rel);

        if (gap == 1) {
            assertEq(uint256(rel), uint256(StreakAccountingMath.EpochRelation.ConsecutiveEpoch));
            assertEq(updated, currentStreak + 1);
        } else {
            assertEq(uint256(rel), uint256(StreakAccountingMath.EpochRelation.MissedEpoch));
            assertEq(updated, 1);
        }
    }

    // ---------------------------------------------------------------------
    // Group E — Weight delta accounting (Plan §16.4 Safeguard 5)
    // ---------------------------------------------------------------------

    function test_Weight_AdditionFromZero() public view {
        uint256 totalWeight = math.applyWeightDelta(0, 0, 1);
        assertEq(totalWeight, 1);
    }

    function test_Weight_ReductionAndZeroing() public view {
        uint256 totalWeight = 10;
        totalWeight = math.applyWeightDelta(totalWeight, 4, 0);
        assertEq(totalWeight, 6);
    }

    /// @notice Plan §16.4: progressing streak 0 -> 1 -> 2 -> 3 -> 4 must produce
    ///         totalWeight == 4, never 0 + 1 + 2 + 3 + 4 = 10.
    function test_Weight_RepeatedUpdatesDoNotAccumulateStaleWeight() public view {
        uint256 totalWeight = 0;
        totalWeight = math.applyWeightDelta(totalWeight, 0, 1);
        totalWeight = math.applyWeightDelta(totalWeight, 1, 2);
        totalWeight = math.applyWeightDelta(totalWeight, 2, 3);
        totalWeight = math.applyWeightDelta(totalWeight, 3, 4);
        assertEq(totalWeight, 4);
    }

    function test_Weight_MultiUserTotalWeightConsistency() public view {
        uint256 wAlice = 0;
        uint256 wBob = 0;
        uint256 totalWeight = 0;

        totalWeight = math.applyWeightDelta(totalWeight, wAlice, 2);
        wAlice = 2;
        totalWeight = math.applyWeightDelta(totalWeight, wBob, 5);
        wBob = 5;
        assertEq(totalWeight, wAlice + wBob);

        totalWeight = math.applyWeightDelta(totalWeight, wAlice, 3);
        wAlice = 3;
        totalWeight = math.applyWeightDelta(totalWeight, wBob, 0);
        wBob = 0;
        assertEq(totalWeight, wAlice + wBob);
        assertEq(totalWeight, 3);
    }

    function test_Weight_RevertWhen_OldWeightExceedsTotalWeight() public {
        vm.expectRevert(
            abi.encodeWithSelector(StreakAccountingMath.StreakAccountingMath__WeightUnderflow.selector, 3, 4)
        );
        math.applyWeightDelta(3, 4, 1);
    }

    function testFuzz_Weight_MultiUserUpdatesMaintainExactSum(uint64[4] memory w1, uint64[4] memory w2) public view {
        uint256 totalWeight = 0;
        uint256[4] memory current;

        for (uint256 i = 0; i < 4; i++) {
            totalWeight = math.applyWeightDelta(totalWeight, current[i], w1[i]);
            current[i] = w1[i];
        }
        assertEq(totalWeight, uint256(current[0]) + current[1] + current[2] + current[3]);

        for (uint256 i = 0; i < 4; i++) {
            totalWeight = math.applyWeightDelta(totalWeight, current[i], w2[i]);
            current[i] = w2[i];
        }
        assertEq(totalWeight, uint256(current[0]) + current[1] + current[2] + current[3]);
    }

    // ---------------------------------------------------------------------
    // Group F — Mathematical verification of MVP Plan v3 T1–T8 scenarios
    // ---------------------------------------------------------------------

    /// @notice T1: Alice deposits before Bob in the same epoch with equal weight (1 each).
    ///         Mathematical result: share = pool * 1 / 2 = 5 USDC each out of 10 USDC.
    function test_T1_Math_DepositOrderDoesNotDistortEqualEpochWeightShare() public view {
        uint256 totalWeight = 0;
        totalWeight = math.applyWeightDelta(totalWeight, 0, 1); // Alice
        totalWeight = math.applyWeightDelta(totalWeight, 0, 1); // Bob
        uint256 pool = 10 * ONE_USDC;

        assertEq(math.computeEpochRewardShare(pool, 1, totalWeight), 5 * ONE_USDC);
        assertEq(math.computeEpochRewardShare(pool, 1, totalWeight), 5 * ONE_USDC);
    }

    /// @notice T2: Plan §4.4 exact example — Alice/Bob/Carol weights 4/2/1, pool = 7 USDC.
    ///         Mathematical result: 4 USDC, 2 USDC, 1 USDC.
    function test_T2_Math_RewardRatioEqualsStreakWeightRatio() public view {
        uint256 wAlice = 4;
        uint256 wBob = 2;
        uint256 wCarol = 1;
        uint256 totalWeight = wAlice + wBob + wCarol;
        uint256 pool = 7 * ONE_USDC;

        uint256 rAlice = math.computeEpochRewardShare(pool, wAlice, totalWeight);
        uint256 rBob = math.computeEpochRewardShare(pool, wBob, totalWeight);
        uint256 rCarol = math.computeEpochRewardShare(pool, wCarol, totalWeight);

        assertEq(rAlice, 4 * ONE_USDC);
        assertEq(rBob, 2 * ONE_USDC);
        assertEq(rCarol, 1 * ONE_USDC);
        assertEq(rAlice + rBob + rCarol, pool);
    }

    /// @notice T3: Two yield additions (3 USDC + 4 USDC = 7 USDC) with weights 4 and 3.
    ///         Mathematical result:
    ///         - Model A aggregates into one epoch pool (7 USDC), producing exact 4 USDC & 3 USDC.
    ///         - Model B divides per addition: floor(3e24 / 7) + floor(4e24 / 7) = 1e24 - 1,
    ///           resulting in at most 1 base-unit rounding dust per user without double-counting
    ///           and strictly preserving total payout <= 7 USDC.
    function test_T3_Math_TwoYieldAdditionsSumWithoutDoubleCounting() public view {
        uint256 wAlice = 4;
        uint256 wBob = 3;
        uint256 totalWeight = wAlice + wBob;

        // Model A sum across two additions in one epoch:
        uint256 pool = 3 * ONE_USDC + 4 * ONE_USDC;
        assertEq(math.computeEpochRewardShare(pool, wAlice, totalWeight), 4 * ONE_USDC);
        assertEq(math.computeEpochRewardShare(pool, wBob, totalWeight), 3 * ONE_USDC);

        // Model B accumulator: no double counting, floor-rounding dust <= 1 wei per user:
        uint256 acc = 0;
        acc += math.computeAccumulatorDelta(3 * ONE_USDC, totalWeight, PRECISION);
        acc += math.computeAccumulatorDelta(4 * ONE_USDC, totalWeight, PRECISION);
        uint256 aliceAcc = math.computeAccruedReward(wAlice, acc, 0, PRECISION);
        uint256 bobAcc = math.computeAccruedReward(wBob, acc, 0, PRECISION);
        assertGe(aliceAcc, 4 * ONE_USDC - 1);
        assertLe(aliceAcc, 4 * ONE_USDC);
        assertGe(bobAcc, 3 * ONE_USDC - 1);
        assertLe(bobAcc, 3 * ONE_USDC);
        assertLe(aliceAcc + bobAcc, pool);
    }

    /// @notice T4: Alice claims between two yield additions (7 USDC then 14 USDC; weights 4 and 3).
    ///         Mathematical result:
    ///         - After add #1 (7 USDC): Alice accrued = 4 USDC -> claims 4 USDC, rewardDebt becomes 4 USDC.
    ///         - After add #2 (14 USDC): Alice total acc = 4 * (1 + 2) = 12 USDC; pending = 12 - 4 = 8 USDC.
    ///         - Total received by Alice = 4 + 8 = 12 USDC; Bob receives 3 + 6 = 9 USDC. Sum = 21 USDC.
    function test_T4_Math_ClaimBetweenTwoYieldAdditionsPreservesLaterShare() public view {
        uint256 wAlice = 4;
        uint256 wBob = 3;
        uint256 totalWeight = wAlice + wBob;
        uint256 acc = 0;

        acc += math.computeAccumulatorDelta(7 * ONE_USDC, totalWeight, PRECISION);
        uint256 aliceClaim1 = math.computeAccruedReward(wAlice, acc, 0, PRECISION);
        uint256 aliceDebt = (wAlice * acc) / PRECISION;
        assertEq(aliceClaim1, 4 * ONE_USDC);

        acc += math.computeAccumulatorDelta(14 * ONE_USDC, totalWeight, PRECISION);
        uint256 aliceClaim2 = math.computeAccruedReward(wAlice, acc, aliceDebt, PRECISION);
        uint256 bobClaim = math.computeAccruedReward(wBob, acc, 0, PRECISION);

        assertEq(aliceClaim2, 8 * ONE_USDC);
        assertEq(aliceClaim1 + aliceClaim2, 12 * ONE_USDC);
        assertEq(bobClaim, 9 * ONE_USDC);
        assertEq(aliceClaim1 + aliceClaim2 + bobClaim, 21 * ONE_USDC);
    }

    /// @notice T5: Bob claims last after Alice claimed earlier and a second yield addition occurred.
    ///         Mathematical result: rounding dust stays in pool, Bob never loses his entitlement or reverts.
    function test_T5_Math_LastClaimerReceivesFullRemainingShare() public view {
        uint256 wAlice = 1;
        uint256 wBob = 2;
        uint256 totalWeight = wAlice + wBob;
        uint256 pool1 = 10 * ONE_USDC; // not divisible by 3 -> 3.333333 & 6.666666
        uint256 pool2 = 5 * ONE_USDC; // not divisible by 3 -> 1.666666 & 3.333333

        uint256 acc = math.computeAccumulatorDelta(pool1, totalWeight, PRECISION);
        uint256 aliceFirst = math.computeAccruedReward(wAlice, acc, 0, PRECISION);
        uint256 aliceDebt = (wAlice * acc) / PRECISION;

        acc += math.computeAccumulatorDelta(pool2, totalWeight, PRECISION);
        uint256 aliceSecond = math.computeAccruedReward(wAlice, acc, aliceDebt, PRECISION);
        uint256 bobTotal = math.computeAccruedReward(wBob, acc, 0, PRECISION);

        assertLe(aliceFirst + aliceSecond + bobTotal, pool1 + pool2);
        // Bob with weight 2/3 of 15 USDC expects 10_000_000 minus at most 1 wei of floor rounding
        assertGe(bobTotal, 9_999_999);
    }

    /// @notice T6: User updates weight from 3 to 4; totalWeight = 5 - 3 + 4 = 6 (never 5 + 4 = 9).
    function test_T6_Math_WeightUpdateSubtractsOldWeightBeforeAddingNew() public view {
        uint256 totalWeight = 5; // Alice=3, Bob=2
        totalWeight = math.applyWeightDelta(totalWeight, 3, 4);
        assertEq(totalWeight, 6);

        uint256 pool = 6 * ONE_USDC;
        assertEq(math.computeEpochRewardShare(pool, 4, totalWeight), 4 * ONE_USDC);
        assertEq(math.computeEpochRewardShare(pool, 2, totalWeight), 2 * ONE_USDC);
    }

    /// @notice T7: Alice withdraws principal (weight becomes 0 before new yield is added);
    ///         subsequent yield of 6 USDC goes 100% to Bob (weight 2).
    function test_T7_Math_ZeroWeightAfterWithdrawalReceivesZeroFutureYield() public view {
        uint256 wAlice = 4;
        uint256 wBob = 2;
        uint256 totalWeight = wAlice + wBob;
        uint256 acc = math.computeAccumulatorDelta(6 * ONE_USDC, totalWeight, PRECISION);

        uint256 aliceCredit = math.computeAccruedReward(wAlice, acc, 0, PRECISION);
        assertEq(aliceCredit, 4 * ONE_USDC);

        // Alice withdraws -> newWeight = 0
        totalWeight = math.applyWeightDelta(totalWeight, wAlice, 0);
        wAlice = 0;
        assertEq(totalWeight, 2);

        // Second yield of 6 USDC while Alice has weight 0
        acc += math.computeAccumulatorDelta(6 * ONE_USDC, totalWeight, PRECISION);
        uint256 aliceAdditional = math.computeAccruedReward(wAlice, acc, 0, PRECISION);
        uint256 bobTotal = math.computeAccruedReward(wBob, acc, 0, PRECISION);

        assertEq(aliceAdditional, 0);
        assertEq(bobTotal, 2 * ONE_USDC + 6 * ONE_USDC);
        assertEq(aliceCredit + bobTotal, 12 * ONE_USDC);
    }

    /// @notice T8: Floor rounding preserves `sum(shares) <= rewardPool`, leaving principal intact.
    function test_T8_Math_FloorRoundingNeverExceedsRewardPoolAndPreservesPrincipal() public view {
        uint256 pool = 1_000_001; // 1.000001 USDC
        uint256 totalWeight = 7;
        uint256 s1 = math.computeEpochRewardShare(pool, 2, totalWeight);
        uint256 s2 = math.computeEpochRewardShare(pool, 3, totalWeight);
        uint256 s3 = math.computeEpochRewardShare(pool, 2, totalWeight);

        assertLe(s1 + s2 + s3, pool);
        assertLe(pool - (s1 + s2 + s3), 2);
    }

    function test_RevertWhen_ZeroActiveWeightOrInvalidPrecision() public {
        vm.expectRevert(StreakAccountingMath.StreakAccountingMath__NoActiveWeight.selector);
        math.computeEpochRewardShare(ONE_USDC, 1, 0);

        vm.expectRevert(StreakAccountingMath.StreakAccountingMath__NoActiveWeight.selector);
        math.computeAccumulatorDelta(ONE_USDC, 0, PRECISION);

        vm.expectRevert(StreakAccountingMath.StreakAccountingMath__InvalidPrecision.selector);
        math.computeAccumulatorDelta(ONE_USDC, 1, 0);

        vm.expectRevert(StreakAccountingMath.StreakAccountingMath__InvalidPrecision.selector);
        math.computeAccruedReward(1, PRECISION, 0, 0);
    }

    function testFuzz_RewardMath_SumOfSharesNeverExceedsPool(uint128 pool, uint32 wAlice, uint32 wBob, uint32 wCarol)
        public
        view
    {
        uint256 wa = bound(wAlice, 1, 1_000_000);
        uint256 wb = bound(wBob, 1, 1_000_000);
        uint256 wc = bound(wCarol, 1, 1_000_000);
        uint256 totalWeight = wa + wb + wc;
        uint256 p = bound(pool, 0, 1e18);

        uint256 ra = math.computeEpochRewardShare(p, wa, totalWeight);
        uint256 rb = math.computeEpochRewardShare(p, wb, totalWeight);
        uint256 rc = math.computeEpochRewardShare(p, wc, totalWeight);

        assertLe(ra + rb + rc, p);
        assertLe(p - (ra + rb + rc), 2);
    }
}
