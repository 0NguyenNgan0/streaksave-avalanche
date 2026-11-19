// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {StreakSavings} from "../src/StreakSavings.sol";

/// @title StreakSavingsRewardsHandler
/// @notice Bounded stateful fuzzing actor for principal, weight and reward invariants.
contract StreakSavingsRewardsHandler is Test {
    uint256 private constant ACTOR_SEED_CAP = 1_000_000 * 1e6;

    MockUSDC public immutable usdc;
    StreakSavings public immutable savings;
    address public immutable provider;

    address[3] public actors;

    mapping(address => uint256) public ghostPrincipal;
    uint256 public ghostYieldAdded;
    uint256 public ghostRewardClaimed;

    constructor(MockUSDC usdc_, StreakSavings savings_, address provider_) {
        usdc = usdc_;
        savings = savings_;
        provider = provider_;

        actors[0] = makeAddr("reward_inv_alice");
        actors[1] = makeAddr("reward_inv_bob");
        actors[2] = makeAddr("reward_inv_carol");

        for (uint256 i = 0; i < actors.length; i++) {
            vm.prank(actors[i]);
            usdc.approve(address(savings), type(uint256).max);
        }
    }

    function actorCount() external pure returns (uint256) {
        return 3;
    }

    function actorSeedCap() external pure returns (uint256) {
        return ACTOR_SEED_CAP;
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 walletBalance = usdc.balanceOf(actor);
        if (walletBalance == 0) return;

        amount = bound(amount, 1, walletBalance);

        vm.prank(actor);
        savings.deposit(amount);

        ghostPrincipal[actor] += amount;
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 available = savings.principalOf(actor);
        if (available == 0) return;

        amount = bound(amount, 1, available);

        vm.prank(actor);
        savings.withdraw(amount);

        ghostPrincipal[actor] -= amount;
    }

    function addYield(uint256 amount) external {
        uint64 epoch = savings.currentEpoch();
        if (savings.totalWeightInEpoch(epoch) == 0) return;

        uint256 providerBalance = usdc.balanceOf(provider);
        if (providerBalance == 0) return;

        amount = bound(amount, 1, providerBalance);

        vm.prank(provider);
        savings.addMockYield(amount);

        ghostYieldAdded += amount;
    }

    function claimFor(uint256 actorSeed, uint256 epochSeed) external {
        uint64 current = savings.currentEpoch();
        if (current == 0) return;

        address actor = actors[actorSeed % actors.length];
        uint64 epoch = uint64(bound(epochSeed, 0, uint256(current - 1)));

        uint256 beforePool = savings.totalRewardPool();
        vm.prank(actor);
        try savings.claimRewardFor(epoch) {
            ghostRewardClaimed += beforePool - savings.totalRewardPool();
        } catch {}
    }

    function claimLatest(uint256 actorSeed) external {
        if (savings.currentEpoch() == 0) return;

        address actor = actors[actorSeed % actors.length];

        uint256 beforePool = savings.totalRewardPool();
        vm.prank(actor);
        try savings.claimReward() {
            ghostRewardClaimed += beforePool - savings.totalRewardPool();
        } catch {}
    }

    function advanceTime(uint256 secondsDelta) external {
        secondsDelta = bound(secondsDelta, 1, 5 * 60);
        vm.warp(block.timestamp + secondsDelta);
    }
}

/// @title StreakSavingsRewardsInvariantTest
/// @notice Principal solvency, reward solvency, weight consistency and pool conservation.
contract StreakSavingsRewardsInvariantTest is StdInvariant, Test {
    uint64 private constant DEMO_EPOCH_DURATION = 60;
    uint256 private constant PROVIDER_FUNDS = 1_000_000 * 1e6;

    MockUSDC private usdc;
    StreakSavings private savings;
    StreakSavingsRewardsHandler private handler;

    function setUp() public {
        usdc = new MockUSDC();
        savings = new StreakSavings(IERC20(address(usdc)), DEMO_EPOCH_DURATION);
        handler = new StreakSavingsRewardsHandler(usdc, savings, address(this));

        usdc.mint(address(this), PROVIDER_FUNDS);
        usdc.approve(address(savings), type(uint256).max);

        uint256 seedCap = handler.actorSeedCap();
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            usdc.mint(handler.actors(i), seedCap);
        }

        targetContract(address(handler));
    }

    function invariant_TotalPrincipalEqualsGhostPrincipal() public view {
        uint256 aggregate = 0;
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address actor = handler.actors(i);
            uint256 recorded = savings.principalOf(actor);
            assertEq(recorded, handler.ghostPrincipal(actor));
            aggregate += recorded;
        }
        assertEq(savings.totalPrincipal(), aggregate);
    }

    function invariant_ContractBalanceCoversPrincipalAndRewards() public view {
        assertGe(usdc.balanceOf(address(savings)), savings.totalPrincipal() + savings.totalRewardPool());
    }

    function invariant_RewardPoolEqualsYieldAddedMinusClaims() public view {
        assertEq(savings.totalRewardPool(), handler.ghostYieldAdded() - handler.ghostRewardClaimed());
    }

    function invariant_TotalWeightEqualsCachedUserWeights() public view {
        uint256 aggregate = 0;
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            aggregate += savings.weightOf(handler.actors(i));
        }
        assertEq(savings.totalWeight(), aggregate);
    }

    function invariant_CurrentEpochWeightEqualsSumOfUserSnapshots() public view {
        uint64 epoch = savings.currentEpoch();
        uint256 aggregate = 0;
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            aggregate += savings.weightInEpoch(handler.actors(i), epoch);
        }
        assertEq(savings.totalWeightInEpoch(epoch), aggregate);
    }

    function invariant_EpochSnapshotsRespectWeightCap() public view {
        uint64 epoch = savings.currentEpoch();
        uint256 epochWeight = savings.totalWeightInEpoch(epoch);
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            assertLe(savings.weightInEpoch(handler.actors(i), epoch), epochWeight);
        }
    }

    function invariant_PrincipalNeverExceedsTotal() public view {
        uint256 total = savings.totalPrincipal();
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            assertLe(savings.principalOf(handler.actors(i)), total);
        }
    }
}
