// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title StreakAccountingMath
/// @notice Pure mathematical helpers for confirmed StreakSave MVP rules.
/// @dev Encodes only the rules explicitly confirmed in Team Dimple's MVP Execution Plan v3
///      (epoch calculation, consecutive/missed streak transitions, old/new weight delta
///      accounting, and pro-rata / accumulator reward formulas). Unapproved business rules
///      such as same-epoch deposit behavior (BL-01) are intentionally rejected rather than
///      guessed so no unapproved policy is silently baked into contract code.
library StreakAccountingMath {
    /// @notice Relationship between a deposit epoch and the user's prior deposit epoch.
    enum EpochRelation {
        FirstDeposit,
        SameEpoch,
        ConsecutiveEpoch,
        MissedEpoch
    }

    /// @notice Thrown when `epochDuration` is zero.
    error StreakAccountingMath__InvalidEpochDuration();

    /// @notice Thrown when `timestamp` is earlier than `startTime`.
    error StreakAccountingMath__TimestampBeforeStart(uint256 timestamp, uint256 startTime);

    /// @notice Thrown when `currentEpoch` precedes `lastDepositEpoch`.
    error StreakAccountingMath__BackwardEpoch(uint64 lastDepositEpoch, uint64 currentEpoch);

    /// @notice Thrown when attempting to evaluate a same-epoch streak transition before BL-01 is approved.
    error StreakAccountingMath__UnapprovedSameEpochRule();

    /// @notice Thrown when subtracting `oldUserWeight` would underflow `currentTotalWeight`.
    error StreakAccountingMath__WeightUnderflow(uint256 currentTotalWeight, uint256 oldUserWeight);

    /// @notice Thrown when distributing yield with zero active total weight.
    error StreakAccountingMath__NoActiveWeight();

    /// @notice Thrown when accumulator precision is zero.
    error StreakAccountingMath__InvalidPrecision();

    /// @notice Thrown when `rewardDebt` exceeds total accumulated entitlement.
    error StreakAccountingMath__RewardDebtExceedsAccrued(uint256 accrued, uint256 rewardDebt);

    /// @notice Computes the zero-indexed epoch for `timestamp`.
    function computeEpoch(uint256 timestamp, uint256 startTime, uint256 epochDuration) internal pure returns (uint64) {
        if (epochDuration == 0) revert StreakAccountingMath__InvalidEpochDuration();
        if (timestamp < startTime) revert StreakAccountingMath__TimestampBeforeStart(timestamp, startTime);
        return SafeCast.toUint64((timestamp - startTime) / epochDuration);
    }

    /// @notice Classifies how `currentEpoch` relates to `lastDepositEpoch`.
    function classifyEpochTransition(uint64 lastDepositEpoch, uint64 currentEpoch, bool hasDepositedBefore)
        internal
        pure
        returns (EpochRelation)
    {
        if (!hasDepositedBefore) return EpochRelation.FirstDeposit;
        if (currentEpoch < lastDepositEpoch) {
            revert StreakAccountingMath__BackwardEpoch(lastDepositEpoch, currentEpoch);
        }
        if (currentEpoch == lastDepositEpoch) return EpochRelation.SameEpoch;
        if (currentEpoch == lastDepositEpoch + 1) return EpochRelation.ConsecutiveEpoch;
        return EpochRelation.MissedEpoch;
    }

    /// @notice Applies only the streak transitions explicitly confirmed by MVP Execution Plan v3 §4.3.
    /// @dev Reverts on `EpochRelation.SameEpoch` because BL-01 is not yet approved.
    function computeConfirmedStreakTransition(uint64 currentStreak, EpochRelation relation)
        internal
        pure
        returns (uint64)
    {
        if (relation == EpochRelation.FirstDeposit) return 1;
        if (relation == EpochRelation.ConsecutiveEpoch) return currentStreak + 1;
        if (relation == EpochRelation.MissedEpoch) return 1;
        revert StreakAccountingMath__UnapprovedSameEpochRule();
    }

    /// @notice Updates global weight using the mandatory `-oldWeight + newWeight` rule (Plan §16.4).
    function applyWeightDelta(uint256 currentTotalWeight, uint256 oldUserWeight, uint256 newUserWeight)
        internal
        pure
        returns (uint256)
    {
        if (oldUserWeight > currentTotalWeight) {
            revert StreakAccountingMath__WeightUnderflow(currentTotalWeight, oldUserWeight);
        }
        return currentTotalWeight - oldUserWeight + newUserWeight;
    }

    /// @notice Computes a user's pro-rata share of an epoch reward pot using floor division (Model A).
    function computeEpochRewardShare(uint256 epochRewardPool, uint256 userWeight, uint256 totalWeight)
        internal
        pure
        returns (uint256)
    {
        if (totalWeight == 0) revert StreakAccountingMath__NoActiveWeight();
        if (userWeight == 0 || epochRewardPool == 0) return 0;
        return (epochRewardPool * userWeight) / totalWeight;
    }

    /// @notice Computes the `accRewardPerWeight` increment for a yield addition (Model B).
    function computeAccumulatorDelta(uint256 yieldAmount, uint256 totalWeight, uint256 precision)
        internal
        pure
        returns (uint256)
    {
        if (precision == 0) revert StreakAccountingMath__InvalidPrecision();
        if (totalWeight == 0) revert StreakAccountingMath__NoActiveWeight();
        return (yieldAmount * precision) / totalWeight;
    }

    /// @notice Computes pending reward from accumulator state and user checkpoint debt (Model B).
    function computeAccruedReward(uint256 userWeight, uint256 accRewardPerWeight, uint256 rewardDebt, uint256 precision)
        internal
        pure
        returns (uint256)
    {
        if (precision == 0) revert StreakAccountingMath__InvalidPrecision();
        uint256 accumulated = (userWeight * accRewardPerWeight) / precision;
        if (rewardDebt > accumulated) {
            revert StreakAccountingMath__RewardDebtExceedsAccrued(accumulated, rewardDebt);
        }
        return accumulated - rewardDebt;
    }
}
