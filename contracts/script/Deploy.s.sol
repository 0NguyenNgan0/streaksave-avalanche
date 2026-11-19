// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {StreakSavings} from "../src/StreakSavings.sol";

/// @title Deploy
/// @notice Safe Foundry deployment and post-deployment verification script for StreakSave.
/// @dev Enforces explicit private key presence, supported chain ID validation (Avalanche Fuji
///      43113 by default, or Anvil 31337 when explicitly enabled), constructor argument
///      validation, and on-chain post-deployment verification checks. Never logs private keys.
contract Deploy is Script {
    uint256 public constant FUJI_CHAIN_ID = 43113;
    uint256 public constant ANVIL_CHAIN_ID = 31337;
    uint64 public constant DEFAULT_DEMO_EPOCH_DURATION = 60;

    error Deploy__MissingOrInvalidPrivateKey();
    error Deploy__UnsupportedChainId(uint256 chainId);
    error Deploy__InvalidEpochDuration(uint256 duration);
    error Deploy__InvalidExistingToken(address token);
    error Deploy__VerificationFailed(string check);

    /// @notice Entry point for `forge script`. Reads configuration from environment variables.
    function run() external returns (MockUSDC usdc, StreakSavings savings) {
        uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        if (deployerPrivateKey == 0) revert Deploy__MissingOrInvalidPrivateKey();

        string memory rawDurationStr = vm.envOr("EPOCH_DURATION", string(""));
        uint256 rawDuration =
            bytes(rawDurationStr).length == 0 ? uint256(DEFAULT_DEMO_EPOCH_DURATION) : vm.parseUint(rawDurationStr);
        if (rawDuration == 0 || rawDuration > type(uint64).max) {
            revert Deploy__InvalidEpochDuration(rawDuration);
        }

        string memory rawUsdc = vm.envOr("MOCK_USDC_ADDRESS", string(""));
        address existingUsdc = bytes(rawUsdc).length == 0 ? address(0) : vm.parseAddress(rawUsdc);

        string memory rawMintStr = vm.envOr("INITIAL_DEMO_MINT", string(""));
        uint256 initialDemoMint = bytes(rawMintStr).length == 0 ? 0 : vm.parseUint(rawMintStr);

        string memory rawLocalStr = vm.envOr("ALLOW_LOCAL_CHAIN", string(""));
        bool allowLocalChain = keccak256(bytes(rawLocalStr)) == keccak256("true");

        return deployContracts(deployerPrivateKey, uint64(rawDuration), existingUsdc, initialDemoMint, allowLocalChain);
    }

    /// @notice Executes deployment and post-deploy verification with explicit parameters.
    /// @param deployerPrivateKey Private key of the deployer wallet (must be non-zero).
    /// @param epochDuration Epoch duration in seconds (must be non-zero).
    /// @param existingUsdc Optional existing MockUSDC address; address(0) deploys a new MockUSDC.
    /// @param initialDemoMint Optional initial MockUSDC amount (6 decimals) minted to deployer.
    /// @param allowLocalChain Whether local Anvil chain ID (31337) is permitted for dry runs.
    function deployContracts(
        uint256 deployerPrivateKey,
        uint64 epochDuration,
        address existingUsdc,
        uint256 initialDemoMint,
        bool allowLocalChain
    ) public returns (MockUSDC usdc, StreakSavings savings) {
        if (deployerPrivateKey == 0) revert Deploy__MissingOrInvalidPrivateKey();
        if (epochDuration == 0) revert Deploy__InvalidEpochDuration(epochDuration);

        bool isFuji = block.chainid == FUJI_CHAIN_ID;
        bool isAllowedLocal = allowLocalChain && block.chainid == ANVIL_CHAIN_ID;
        if (!isFuji && !isAllowedLocal) {
            revert Deploy__UnsupportedChainId(block.chainid);
        }

        if (existingUsdc != address(0) && existingUsdc.code.length == 0) {
            revert Deploy__InvalidExistingToken(existingUsdc);
        }

        address deployer = vm.addr(deployerPrivateKey);
        bool deployedNewUsdc = existingUsdc == address(0);

        vm.startBroadcast(deployerPrivateKey);

        if (deployedNewUsdc) {
            usdc = new MockUSDC();
        } else {
            usdc = MockUSDC(existingUsdc);
        }

        if (initialDemoMint > 0) {
            usdc.mint(deployer, initialDemoMint);
        }

        savings = new StreakSavings(IERC20(address(usdc)), epochDuration);

        vm.stopBroadcast();

        _verifyDeployment(usdc, savings, deployer, epochDuration, deployedNewUsdc, initialDemoMint);

        console2.log("=== StreakSave Deployment Summary ===");
        console2.log("Chain ID:        ", block.chainid);
        console2.log("Deployer:        ", deployer);
        console2.log("MockUSDC:        ", address(usdc));
        console2.log("StreakSavings:   ", address(savings));
        console2.log("Epoch Duration:  ", uint256(savings.epochDuration()));
        console2.log("Start Time:      ", uint256(savings.startTime()));
    }

    function _verifyDeployment(
        MockUSDC usdc,
        StreakSavings savings,
        address deployer,
        uint64 expectedEpochDuration,
        bool deployedNewUsdc,
        uint256 expectedInitialMint
    ) private view {
        if (address(usdc).code.length == 0) {
            revert Deploy__VerificationFailed("MockUSDC has no code");
        }
        if (address(savings).code.length == 0) revert Deploy__VerificationFailed("StreakSavings has no code");
        if (usdc.decimals() != 6) revert Deploy__VerificationFailed("MockUSDC decimals != 6");

        if (deployedNewUsdc) {
            if (usdc.minter() != deployer) revert Deploy__VerificationFailed("MockUSDC minter != deployer");
            if (usdc.totalSupply() != expectedInitialMint) {
                revert Deploy__VerificationFailed("MockUSDC totalSupply mismatch");
            }
            if (usdc.balanceOf(deployer) != expectedInitialMint) {
                revert Deploy__VerificationFailed("Deployer initial balance mismatch");
            }
        }

        if (address(savings.usdc()) != address(usdc)) {
            revert Deploy__VerificationFailed("StreakSavings usdc mismatch");
        }
        if (savings.epochDuration() != expectedEpochDuration) {
            revert Deploy__VerificationFailed("StreakSavings epochDuration mismatch");
        }
        if (savings.totalPrincipal() != 0) {
            revert Deploy__VerificationFailed("StreakSavings totalPrincipal != 0");
        }
        if (savings.totalWeight() != 0) {
            revert Deploy__VerificationFailed("StreakSavings totalWeight != 0");
        }
        if (savings.totalRewardPool() != 0) {
            revert Deploy__VerificationFailed("StreakSavings totalRewardPool != 0");
        }
        if (savings.yieldProvider() != deployer) {
            revert Deploy__VerificationFailed("StreakSavings yieldProvider != deployer");
        }
        if (savings.currentEpoch() != 0) {
            revert Deploy__VerificationFailed("StreakSavings initial epoch != 0");
        }
    }
}
