// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {StreakSavings} from "../src/StreakSavings.sol";

/// @title StreakSavingsHandler
/// @notice Bounded stateful fuzzing actor for StreakSavings invariants.
contract StreakSavingsHandler is Test {
    uint256 private constant ACTOR_SEED_CAP = 1_000_000 * 1e6;

    MockUSDC public immutable usdc;
    StreakSavings public immutable savings;

    address[4] public actors;
    mapping(address => uint256) public ghost_userPrincipal;
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalDirectDonations;

    constructor(MockUSDC usdc_, StreakSavings savings_) {
        usdc = usdc_;
        savings = savings_;

        actors[0] = makeAddr("inv_alice");
        actors[1] = makeAddr("inv_bob");
        actors[2] = makeAddr("inv_carol");
        actors[3] = makeAddr("inv_dave");

        for (uint256 i = 0; i < actors.length; i++) {
            vm.prank(actors[i]);
            usdc.approve(address(savings), type(uint256).max);
        }
    }

    function actorSeedCap() external pure returns (uint256) {
        return ACTOR_SEED_CAP;
    }

    function actorCount() external pure returns (uint256) {
        return 4;
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 walletBalance = usdc.balanceOf(actor);
        if (walletBalance == 0) return;

        amount = bound(amount, 1, walletBalance);

        vm.prank(actor);
        savings.deposit(amount);

        ghost_userPrincipal[actor] += amount;
        ghost_totalDeposited += amount;
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 available = savings.principalOf(actor);
        if (available == 0) return;

        amount = bound(amount, 1, available);

        vm.prank(actor);
        savings.withdraw(amount);

        ghost_userPrincipal[actor] -= amount;
        ghost_totalWithdrawn += amount;
    }

    function donateDirectly(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 walletBalance = usdc.balanceOf(actor);
        if (walletBalance == 0) return;

        amount = bound(amount, 1, walletBalance);

        vm.prank(actor);
        assertTrue(usdc.transfer(address(savings), amount));

        ghost_totalDirectDonations += amount;
    }

    function advanceTime(uint256 secondsDelta) external {
        secondsDelta = bound(secondsDelta, 1, 14 days);
        vm.warp(block.timestamp + secondsDelta);
    }
}

/// @title StreakSavingsInvariantTest
/// @notice Stateful invariant verification for principal solvency, donation isolation, and epoch clock.
contract StreakSavingsInvariantTest is StdInvariant, Test {
    uint64 private constant DEMO_EPOCH_DURATION = 60;

    MockUSDC private usdc;
    StreakSavings private savings;
    StreakSavingsHandler private handler;

    function setUp() public {
        usdc = new MockUSDC();
        savings = new StreakSavings(IERC20(address(usdc)), DEMO_EPOCH_DURATION);
        handler = new StreakSavingsHandler(usdc, savings);

        uint256 seedCap = handler.actorSeedCap();
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            usdc.mint(handler.actors(i), seedCap);
        }

        targetContract(address(handler));
    }

    function invariant_TotalPrincipalEqualsSumOfUserPrincipals() public view {
        uint256 aggregatePrincipal = 0;
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address actor = handler.actors(i);
            uint256 recorded = savings.principalOf(actor);
            assertEq(recorded, handler.ghost_userPrincipal(actor));
            aggregatePrincipal += recorded;
        }
        assertEq(savings.totalPrincipal(), aggregatePrincipal);
        assertEq(savings.totalPrincipal(), handler.ghost_totalDeposited() - handler.ghost_totalWithdrawn());
    }

    function invariant_ContractBalanceCoversTotalPrincipal() public view {
        assertGe(usdc.balanceOf(address(savings)), savings.totalPrincipal());
    }

    function invariant_ExactTokenBalanceEqualsPrincipalPlusDonations() public view {
        assertEq(usdc.balanceOf(address(savings)), savings.totalPrincipal() + handler.ghost_totalDirectDonations());
    }

    function invariant_IndividualPrincipalNeverExceedsTotalPrincipal() public view {
        uint256 total = savings.totalPrincipal();
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            assertLe(savings.principalOf(handler.actors(i)), total);
        }
    }

    function invariant_TotalWeightEqualsSumOfCachedUserWeights() public view {
        uint256 aggregate = 0;
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            aggregate += savings.weightOf(handler.actors(i));
        }
        assertEq(savings.totalWeight(), aggregate);
    }

    function invariant_WeightMatchesPrincipalAndStreak() public view {
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address actor = handler.actors(i);
            uint256 principal = savings.principalOf(actor);
            uint256 weight = savings.weightOf(actor);
            if (principal == 0) {
                assertEq(weight, 0);
                assertEq(savings.streakOf(actor), 0);
            } else {
                assertEq(weight, savings.streakOf(actor));
            }
        }
    }

    function invariant_EpochClockBoundariesAreConsistent() public view {
        uint64 ep = savings.currentEpoch();
        assertLe(savings.epochStart(ep), block.timestamp);
        assertGt(savings.epochEnd(ep), block.timestamp);
        assertEq(savings.epochEnd(ep) - savings.epochStart(ep), savings.epochDuration());
        assertEq(savings.nextEpochTimestamp(), savings.epochEnd(ep));
        assertEq(savings.timeUntilNextEpoch(), savings.epochEnd(ep) - block.timestamp);
        assertGt(savings.timeUntilNextEpoch(), 0);
        assertLe(savings.timeUntilNextEpoch(), savings.epochDuration());
    }
}
