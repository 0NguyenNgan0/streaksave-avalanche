// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {StreakAccountingMath} from "./libraries/StreakAccountingMath.sol";

/// @title StreakSavings
/// @notice StreakSave principal vault, epoch clock, streak and mock-yield rewards for Mock USDC.
/// @dev Implements the confirmed MVP rules (BR-01..BR-06):
///      - one streak check-in per epoch;
///      - full withdrawal resets the streak;
///      - weight = streak while principal > 0, otherwise 0;
///      - end-of-epoch weight snapshots per epoch, written only while that epoch is current;
///      - epoch-scoped reward pools and permanent, double-claim-safe reward claims.
///      Epoch snapshot mechanism: `weightInEpoch[user][epoch]` and `totalWeightInEpoch[epoch]`
///      are updated only by actions taken during `epoch`. Once `currentEpoch()` advances, no
///      function can write to the closed epoch, so the last value written during the epoch is
///      exactly the end-of-epoch snapshot. Claims require `epoch < currentEpoch()`, which makes
///      finalization explicit without a transaction or a loop over users.
///      The contract never uses its token balance as the source of user principal or rewards.
contract StreakSavings is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Recorded per-user state.
    /// @param principal Deposited Mock USDC, excluding rewards.
    /// @param streak Consecutive check-in count. Zero means no active streak.
    /// @param lastDepositEpoch Epoch of the most recent counted check-in.
    /// @param weight Cached active weight: `streak` while principal > 0, otherwise zero.
    struct UserInfo {
        uint256 principal;
        uint64 streak;
        uint64 lastDepositEpoch;
        uint256 weight;
    }

    /// @notice Mock USDC used for principal and mock yield. This token has no monetary value.
    IERC20 public immutable usdc;

    /// @notice Duration of each saving epoch in seconds, fixed at deployment.
    uint64 public immutable epochDuration;

    /// @notice Deployment timestamp anchoring epoch 0.
    uint64 public immutable startTime;

    /// @notice Account allowed to fund mock yield. Set to the deployer (demo account).
    address public immutable yieldProvider;

    /// @notice Sum of all recorded user principal.
    uint256 public totalPrincipal;

    /// @notice Sum of cached user weights. Epoch snapshots are the authoritative reward weights.
    uint256 public totalWeight;

    /// @notice Total mock yield funded minus reward amounts already claimed.
    /// @dev Includes rounding dust and any yield that could not be allocated; the token balance
    ///      always covers this liability.
    uint256 public totalRewardPool;

    mapping(address user => UserInfo info) private _users;

    /// @notice End-of-epoch weight snapshot for a user, written only during that epoch.
    mapping(address user => mapping(uint64 epoch => uint256 weight)) public weightInEpoch;

    /// @notice Sum of user weights that checked in during an epoch, written only during that epoch.
    mapping(uint64 epoch => uint256 weight) public totalWeightInEpoch;

    /// @notice Mock yield assigned to an epoch.
    mapping(uint64 epoch => uint256 amount) public rewardPoolInEpoch;

    /// @notice Whether a user has claimed a finalized epoch.
    mapping(address user => mapping(uint64 epoch => bool claimed)) public claimedInEpoch;

    /// @notice Emitted when a user deposits principal.
    event Deposit(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws principal.
    event Withdraw(address indexed user, uint256 amount, uint256 principalRemaining);

    /// @notice Emitted when a deposit changes the user's streak.
    event StreakUpdated(address indexed user, uint64 indexed epoch, uint64 oldStreak, uint64 newStreak);

    /// @notice Emitted when a full withdrawal clears the user's streak.
    event StreakReset(address indexed user, uint64 indexed epoch, uint64 previousStreak);

    /// @notice Emitted when the yield provider funds an epoch's reward pool.
    event MockYieldAdded(address indexed provider, uint64 indexed epoch, uint256 amount, uint256 epochRewardPool);

    /// @notice Emitted when a user claims reward from one finalized epoch.
    event RewardClaimed(address indexed user, uint64 indexed epoch, uint256 amount);

    /// @notice Thrown when the configured token is the zero address or has no code.
    error StreakSavings__InvalidToken();

    /// @notice Thrown when the configured epoch duration is zero.
    error StreakSavings__InvalidEpochDuration();

    /// @notice Thrown when a deposit, withdrawal or yield amount is zero.
    error StreakSavings__ZeroAmount();

    /// @notice Thrown when a withdrawal exceeds the caller's recorded principal.
    error StreakSavings__InsufficientPrincipal(uint256 requested, uint256 available);

    /// @notice Thrown when the token balance change does not match the requested amount.
    error StreakSavings__TransferMismatch(uint256 expected, uint256 received);

    /// @notice Thrown when querying an epoch for a timestamp earlier than deployment.
    error StreakSavings__TimestampBeforeStart(uint256 timestamp, uint256 startTime);

    /// @notice Thrown when an account other than `yieldProvider` calls `addMockYield`.
    error StreakSavings__UnauthorizedYieldProvider(address caller);

    /// @notice Thrown when funding yield for an epoch with no checked-in weight.
    error StreakSavings__NoActiveWeight(uint64 epoch);

    /// @notice Thrown when claiming an epoch that has not closed yet.
    error StreakSavings__EpochNotFinalized(uint64 epoch, uint64 currentEpoch);

    /// @notice Thrown when a user already claimed an epoch.
    error StreakSavings__RewardAlreadyClaimed(address user, uint64 epoch);

    /// @notice Thrown when a user has no claimable reward for an epoch.
    error StreakSavings__NoReward(address user, uint64 epoch);

    /// @notice Thrown when `claimReward()` is called before any epoch has closed.
    error StreakSavings__NoFinalizedEpoch();

    /// @param usdc_ Mock USDC token address. Must be a deployed contract.
    /// @param epochDuration_ Duration of each epoch in seconds. Must be non-zero.
    constructor(IERC20 usdc_, uint64 epochDuration_) {
        if (address(usdc_) == address(0) || address(usdc_).code.length == 0) {
            revert StreakSavings__InvalidToken();
        }
        if (epochDuration_ == 0) {
            revert StreakSavings__InvalidEpochDuration();
        }

        usdc = usdc_;
        epochDuration = epochDuration_;
        startTime = SafeCast.toUint64(block.timestamp);
        yieldProvider = msg.sender;
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice Returns the recorded principal of a user.
    function principalOf(address user) external view returns (uint256) {
        return _users[user].principal;
    }

    /// @notice Returns the stored streak. After a missed epoch this remains historical until the
    ///         next deposit resets it; use `effectiveStreakOf` for display eligibility.
    function streakOf(address user) external view returns (uint256) {
        return uint256(_users[user].streak);
    }

    /// @notice Returns the streak that is still continuable during the current epoch.
    /// @dev Returns zero when principal is zero or when at least one full epoch was missed.
    function effectiveStreakOf(address user) external view returns (uint256) {
        UserInfo storage userInfo = _users[user];
        if (userInfo.principal == 0 || userInfo.streak == 0) return 0;
        if (uint256(userInfo.lastDepositEpoch) + 1 < uint256(currentEpoch())) return 0;
        return uint256(userInfo.streak);
    }

    /// @notice Returns the cached active weight of a user.
    function weightOf(address user) external view returns (uint256) {
        return _users[user].weight;
    }

    /// @notice Returns the epoch of the user's most recent counted check-in.
    function lastDepositEpochOf(address user) external view returns (uint64) {
        return _users[user].lastDepositEpoch;
    }

    /// @notice Returns the current zero-indexed epoch based on block.timestamp.
    function currentEpoch() public view returns (uint64) {
        return SafeCast.toUint64((block.timestamp - uint256(startTime)) / uint256(epochDuration));
    }

    /// @notice Computes the epoch index for any timestamp at or after deployment.
    function epochAt(uint256 timestamp) external view returns (uint64) {
        if (timestamp < uint256(startTime)) {
            revert StreakSavings__TimestampBeforeStart(timestamp, uint256(startTime));
        }
        return SafeCast.toUint64((timestamp - uint256(startTime)) / uint256(epochDuration));
    }

    /// @notice Returns the inclusive start timestamp of a given epoch.
    function epochStart(uint64 epoch) public view returns (uint256) {
        return uint256(startTime) + uint256(epoch) * uint256(epochDuration);
    }

    /// @notice Returns the exclusive end timestamp of a given epoch.
    function epochEnd(uint64 epoch) public view returns (uint256) {
        return uint256(startTime) + (uint256(epoch) + 1) * uint256(epochDuration);
    }

    /// @notice Returns the timestamp when the next epoch begins.
    function nextEpochTimestamp() external view returns (uint256) {
        return epochEnd(currentEpoch());
    }

    /// @notice Returns seconds remaining until the current epoch ends.
    function timeUntilNextEpoch() external view returns (uint256) {
        return epochEnd(currentEpoch()) - block.timestamp;
    }

    /// @notice Whether an epoch has closed and its weight snapshot is immutable.
    function isEpochFinalized(uint64 epoch) public view returns (bool) {
        return epoch < currentEpoch();
    }

    /// @notice Returns a user's reward for a finalized, unclaimed epoch.
    function rewardInEpoch(address user, uint64 epoch) public view returns (uint256) {
        if (epoch >= currentEpoch()) return 0;
        if (claimedInEpoch[user][epoch]) return 0;
        return _pendingReward(user, epoch);
    }

    /// @notice Returns the claimable reward for the latest finalized epoch only.
    /// @dev This intentionally does not sum every historical epoch: the frontend-compatible
    ///      zero-argument `claimReward()` claims this same epoch, and older unclaimed epochs stay
    ///      claimable indefinitely through `claimRewardFor(epoch)` and `rewardInEpoch`.
    function rewardOf(address user) external view returns (uint256) {
        uint64 epoch = currentEpoch();
        if (epoch == 0) return 0;
        return rewardInEpoch(user, epoch - 1);
    }

    // ---------------------------------------------------------------------
    // Principal and streak actions
    // ---------------------------------------------------------------------

    /// @notice Deposits Mock USDC, credits principal and performs the epoch's single check-in.
    /// @dev Additional deposits in the same epoch increase principal without changing the streak.
    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert StreakSavings__ZeroAmount();
        _pullTokens(msg.sender, amount);

        UserInfo storage user = _users[msg.sender];
        uint64 epoch = currentEpoch();
        uint64 oldStreak = user.streak;
        uint256 oldWeight = user.weight;

        user.principal += amount;
        totalPrincipal += amount;

        StreakAccountingMath.EpochRelation relation =
            StreakAccountingMath.classifyEpochTransition(user.lastDepositEpoch, epoch, oldStreak > 0);
        uint64 newStreak = StreakAccountingMath.computeConfirmedStreakTransition(oldStreak, relation);
        uint256 newWeight = uint256(newStreak);

        user.streak = newStreak;
        user.lastDepositEpoch = epoch;
        user.weight = newWeight;

        totalWeight = StreakAccountingMath.applyWeightDelta(totalWeight, oldWeight, newWeight);
        _setEpochWeight(msg.sender, epoch, newWeight);

        emit Deposit(msg.sender, amount);
        if (newStreak != oldStreak) {
            emit StreakUpdated(msg.sender, epoch, oldStreak, newStreak);
        }
    }

    /// @notice Withdraws recorded principal. A full withdrawal resets the streak and weight.
    /// @dev Partial withdrawals preserve the streak and weight. Rewards are never touched.
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert StreakSavings__ZeroAmount();

        UserInfo storage user = _users[msg.sender];
        uint256 available = user.principal;
        if (amount > available) revert StreakSavings__InsufficientPrincipal(amount, available);

        uint256 remaining = available - amount;
        user.principal = remaining;
        totalPrincipal -= amount;

        if (remaining == 0) {
            uint64 epoch = currentEpoch();
            uint64 oldStreak = user.streak;
            uint256 oldWeight = user.weight;

            if (oldWeight > 0) {
                totalWeight = StreakAccountingMath.applyWeightDelta(totalWeight, oldWeight, 0);
                user.weight = 0;
            }

            _setEpochWeight(msg.sender, epoch, 0);
            user.streak = 0;
            user.lastDepositEpoch = 0;

            if (oldStreak > 0) {
                emit StreakReset(msg.sender, epoch, oldStreak);
            }
        }

        emit Withdraw(msg.sender, amount, remaining);
        usdc.safeTransfer(msg.sender, amount);
    }

    // ---------------------------------------------------------------------
    // Mock yield and reward claims
    // ---------------------------------------------------------------------

    /// @notice Funds the current epoch's mock reward pool. Restricted to the demo yield provider.
    /// @dev Reverts when the current epoch has no checked-in weight, so yield cannot be assigned
    ///      to an epoch with no possible beneficiaries.
    function addMockYield(uint256 amount) external nonReentrant {
        if (msg.sender != yieldProvider) revert StreakSavings__UnauthorizedYieldProvider(msg.sender);
        if (amount == 0) revert StreakSavings__ZeroAmount();

        uint64 epoch = currentEpoch();
        if (totalWeightInEpoch[epoch] == 0) revert StreakSavings__NoActiveWeight(epoch);

        _pullTokens(msg.sender, amount);

        rewardPoolInEpoch[epoch] += amount;
        totalRewardPool += amount;

        emit MockYieldAdded(msg.sender, epoch, amount, rewardPoolInEpoch[epoch]);
    }

    /// @notice Claims the caller's reward for the latest finalized epoch.
    /// @dev To claim an older epoch that is still unclaimed, use `claimRewardFor(epoch)`.
    function claimReward() external nonReentrant {
        uint64 epoch = currentEpoch();
        if (epoch == 0) revert StreakSavings__NoFinalizedEpoch();
        _claimReward(msg.sender, epoch - 1);
    }

    /// @notice Claims the caller's reward for a specific finalized epoch.
    /// @dev Unclaimed rewards never expire and double claims are rejected.
    function claimRewardFor(uint64 epoch) external nonReentrant {
        uint64 current = currentEpoch();
        if (epoch >= current) revert StreakSavings__EpochNotFinalized(epoch, current);
        _claimReward(msg.sender, epoch);
    }

    // ---------------------------------------------------------------------
    // Internal accounting
    // ---------------------------------------------------------------------

    function _claimReward(address user, uint64 epoch) internal {
        if (claimedInEpoch[user][epoch]) revert StreakSavings__RewardAlreadyClaimed(user, epoch);

        uint256 reward = _pendingReward(user, epoch);
        if (reward == 0) revert StreakSavings__NoReward(user, epoch);

        claimedInEpoch[user][epoch] = true;
        totalRewardPool -= reward;

        // Emitted before the transfer (CEI). All entry points are nonReentrant; the lint is
        // conservative because this internal function is reachable from a public call graph.
        // forge-lint: disable-next-line(reentrancy-events)
        emit RewardClaimed(user, epoch, reward);
        usdc.safeTransfer(user, reward);
    }

    function _pendingReward(address user, uint64 epoch) internal view returns (uint256) {
        uint256 userWeight = weightInEpoch[user][epoch];
        uint256 epochWeight = totalWeightInEpoch[epoch];
        if (userWeight == 0 || epochWeight == 0) return 0;
        return StreakAccountingMath.computeEpochRewardShare(rewardPoolInEpoch[epoch], userWeight, epochWeight);
    }

    /// @dev Records the user's weight for `epoch`, keeping the per-epoch total in sync.
    function _setEpochWeight(address user, uint64 epoch, uint256 newWeight) internal {
        uint256 oldWeight = weightInEpoch[user][epoch];
        if (oldWeight == newWeight) return;

        weightInEpoch[user][epoch] = newWeight;
        totalWeightInEpoch[epoch] =
            StreakAccountingMath.applyWeightDelta(totalWeightInEpoch[epoch], oldWeight, newWeight);
    }

    /// @dev Pulls tokens and verifies the exact balance delta.
    function _pullTokens(address from, uint256 amount) internal {
        uint256 balanceBefore = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(from, address(this), amount);
        uint256 received = usdc.balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert StreakSavings__TransferMismatch(amount, received);
    }
}
