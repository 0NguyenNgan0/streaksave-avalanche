// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title StreakSavings
/// @notice StreakSave principal vault and epoch clock for Mock USDC on Avalanche Fuji.
/// @dev Principal accounting and the configurable global epoch clock are implemented.
///      Streak updates, weight accounting and reward accounting remain intentionally
///      absent until the blocking business rules (BL-01, BL-02, BL-03, BL-10, BL-11,
///      BL-13) in docs/MEMBER-A-TECHNICAL-DECISIONS.md are approved by the team.
///      The contract never uses its token balance as the source of user principal.
contract StreakSavings is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Mock USDC used for deposits. This token has no monetary value.
    IERC20 public immutable usdc;

    /// @notice Duration of each saving epoch in seconds, fixed at deployment.
    uint64 public immutable epochDuration;

    /// @notice Deployment timestamp anchoring epoch 0.
    uint64 public immutable startTime;

    /// @notice Sum of all recorded user principal.
    uint256 public totalPrincipal;

    mapping(address user => uint256 principal) private _principal;

    /// @notice Emitted when a user deposits principal.
    /// @param user The depositor.
    /// @param amount Amount of Mock USDC deposited, in token units (6 decimals).
    event Deposit(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws principal.
    /// @param user The withdrawer.
    /// @param amount Amount of Mock USDC withdrawn, in token units (6 decimals).
    /// @param principalRemaining Principal left after the withdrawal.
    event Withdraw(address indexed user, uint256 amount, uint256 principalRemaining);

    /// @notice Thrown when the configured token is the zero address or has no code.
    error StreakSavings__InvalidToken();

    /// @notice Thrown when the configured epoch duration is zero.
    error StreakSavings__InvalidEpochDuration();

    /// @notice Thrown when a deposit or withdrawal amount is zero.
    error StreakSavings__ZeroAmount();

    /// @notice Thrown when a withdrawal exceeds the caller's recorded principal.
    /// @param requested Amount requested.
    /// @param available Amount of principal available.
    error StreakSavings__InsufficientPrincipal(uint256 requested, uint256 available);

    /// @notice Thrown when the token balance change does not match the requested amount.
    /// @param expected Amount requested.
    /// @param received Amount actually received by the contract.
    error StreakSavings__TransferMismatch(uint256 expected, uint256 received);

    /// @notice Thrown when querying an epoch for a timestamp earlier than deployment.
    /// @param timestamp Timestamp queried.
    /// @param startTime Deployment start timestamp.
    error StreakSavings__TimestampBeforeStart(uint256 timestamp, uint256 startTime);

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
    }

    /// @notice Returns the recorded principal of a user.
    /// @param user The user to query.
    /// @return The user's principal, excluding any future rewards.
    function principalOf(address user) external view returns (uint256) {
        return _principal[user];
    }

    /// @notice Returns the current zero-indexed epoch based on block.timestamp.
    /// @return The current epoch index.
    function currentEpoch() public view returns (uint64) {
        return SafeCast.toUint64((block.timestamp - uint256(startTime)) / uint256(epochDuration));
    }

    /// @notice Computes the epoch index for any timestamp at or after deployment.
    /// @param timestamp Unix timestamp in seconds. Must be >= startTime.
    /// @return The zero-indexed epoch containing `timestamp`.
    function epochAt(uint256 timestamp) external view returns (uint64) {
        if (timestamp < uint256(startTime)) {
            revert StreakSavings__TimestampBeforeStart(timestamp, uint256(startTime));
        }
        return SafeCast.toUint64((timestamp - uint256(startTime)) / uint256(epochDuration));
    }

    /// @notice Returns the inclusive start timestamp of a given epoch.
    /// @param epoch Zero-indexed epoch number.
    /// @return Unix timestamp when `epoch` begins.
    function epochStart(uint64 epoch) public view returns (uint256) {
        return uint256(startTime) + uint256(epoch) * uint256(epochDuration);
    }

    /// @notice Returns the exclusive end timestamp of a given epoch (start of `epoch + 1`).
    /// @param epoch Zero-indexed epoch number.
    /// @return Unix timestamp when `epoch` ends.
    function epochEnd(uint64 epoch) public view returns (uint256) {
        return uint256(startTime) + (uint256(epoch) + 1) * uint256(epochDuration);
    }

    /// @notice Returns the timestamp when the next epoch begins.
    /// @return Unix timestamp of `currentEpoch() + 1` start.
    function nextEpochTimestamp() external view returns (uint256) {
        return epochEnd(currentEpoch());
    }

    /// @notice Returns seconds remaining until the current epoch ends.
    /// @return Remaining seconds in `[1, epochDuration]`.
    function timeUntilNextEpoch() external view returns (uint256) {
        return epochEnd(currentEpoch()) - block.timestamp;
    }

    /// @notice Deposits Mock USDC and credits the caller's principal.
    /// @dev Pulls funds first so the actual received amount can be verified. The
    ///      reentrancy guard protects the external token call; state is credited only
    ///      after the balance delta is confirmed.
    /// @param amount Amount of Mock USDC to deposit, in token units (6 decimals).
    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert StreakSavings__ZeroAmount();

        uint256 balanceBefore = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = usdc.balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert StreakSavings__TransferMismatch(amount, received);

        _principal[msg.sender] += amount;
        totalPrincipal += amount;

        emit Deposit(msg.sender, amount);
    }

    /// @notice Withdraws recorded principal. Rewards are not touched.
    /// @dev Follows checks-effects-interactions: principal is reduced before the
    ///      external transfer, and the function is non-reentrant.
    /// @param amount Amount of Mock USDC to withdraw, in token units (6 decimals).
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert StreakSavings__ZeroAmount();

        uint256 available = _principal[msg.sender];
        if (amount > available) revert StreakSavings__InsufficientPrincipal(amount, available);

        uint256 remaining = available - amount;
        _principal[msg.sender] = remaining;
        totalPrincipal -= amount;

        usdc.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, remaining);
    }
}
