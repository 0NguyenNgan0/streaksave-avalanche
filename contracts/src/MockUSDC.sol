// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice Test-only ERC-20 token used by the StreakSave demo on Avalanche Fuji.
/// @dev This is a faucet-style mock of USDC for hackathon testing only. It has no
///      monetary value, is not backed by any reserve, and must never be used in
///      production. Minting is restricted to the deployer captured immutably at
///      construction; the contract has no ownership transfer, pause, blacklist or
///      other privileged functionality.
contract MockUSDC is ERC20 {
    /// @notice Number of decimals, matching the real USDC convention.
    uint8 private constant DECIMALS = 6;

    /// @notice The only address allowed to mint test tokens (the deployer).
    address public immutable minter;

    /// @notice Thrown when a mint recipient is the zero address.
    error MockUSDC__InvalidRecipient();

    /// @notice Thrown when an account other than the deployer attempts to mint.
    /// @param caller The unauthorized caller.
    error MockUSDC__UnauthorizedMinter(address caller);

    /// @dev The deployer becomes the immutable minter. No initial supply is minted;
    ///      the deploy script must explicitly mint demo balances.
    constructor() ERC20("Mock USDC", "USDC") {
        minter = msg.sender;
    }

    /// @notice Mints test tokens. Restricted to the deployer.
    /// @param to Recipient of the minted tokens. Must not be the zero address.
    /// @param amount Amount of tokens to mint, denominated in 6 decimals.
    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert MockUSDC__UnauthorizedMinter(msg.sender);
        if (to == address(0)) revert MockUSDC__InvalidRecipient();
        _mint(to, amount);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
