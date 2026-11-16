// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StreakSavings
/// @notice StreakSave principal vault for Mock USDC on Avalanche Fuji.
/// @dev Only principal accounting is implemented at this stage. Epoch, streak and
///      reward accounting are intentionally absent until the blocking business rules
///      in docs/BL-DECISIONS-PROPOSAL.md are approved by the team. The contract never
///      uses its token balance as the source of user principal.
contract StreakSavings is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Mock USDC used for deposits. This token has no monetary value.
    IERC20 public immutable usdc;

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

    /// @param usdc_ Mock USDC token address. Must be a deployed contract.
    constructor(IERC20 usdc_) {
        if (address(usdc_) == address(0) || address(usdc_).code.length == 0) {
            revert StreakSavings__InvalidToken();
        }
        usdc = usdc_;
    }

    /// @notice Returns the recorded principal of a user.
    /// @param user The user to query.
    /// @return The user's principal, excluding any future rewards.
    function principalOf(address user) external view returns (uint256) {
        return _principal[user];
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
