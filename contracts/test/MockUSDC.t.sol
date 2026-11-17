// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract MockUSDCTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 private constant ONE_USDC = 1e6;

    MockUSDC private usdc;
    address private deployer;
    address private alice;
    address private bob;

    function setUp() public {
        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        usdc = new MockUSDC();
    }

    function test_Metadata() public view {
        assertEq(usdc.name(), "Mock USDC");
        assertEq(usdc.symbol(), "USDC");
    }

    function test_DecimalsMatchUSDCConvention() public view {
        assertEq(usdc.decimals(), 6);
    }

    function test_DeployerBecomesMinter() public view {
        assertEq(usdc.minter(), deployer);
    }

    function test_InitialDeployerBalanceIsZero() public view {
        assertEq(usdc.balanceOf(deployer), 0);
        assertEq(usdc.totalSupply(), 0);
    }

    function test_MintZeroAmount() public {
        vm.expectEmit(true, true, false, true, address(usdc));
        emit Transfer(address(0), alice, 0);

        usdc.mint(alice, 0);

        assertEq(usdc.balanceOf(alice), 0);
        assertEq(usdc.totalSupply(), 0);
    }

    function test_MintToDeployer() public {
        uint256 amount = 1_000 * ONE_USDC;

        vm.expectEmit(true, true, false, true, address(usdc));
        emit Transfer(address(0), deployer, amount);

        usdc.mint(deployer, amount);

        assertEq(usdc.balanceOf(deployer), amount);
        assertEq(usdc.totalSupply(), amount);
    }

    function test_MintToAnotherAddress() public {
        uint256 amount = 25 * ONE_USDC;

        vm.expectEmit(true, true, false, true, address(usdc));
        emit Transfer(address(0), alice, amount);

        usdc.mint(alice, amount);

        assertEq(usdc.balanceOf(alice), amount);
        assertEq(usdc.balanceOf(deployer), 0);
        assertEq(usdc.totalSupply(), amount);
    }

    function test_StandardERC20ApproveAndTransferFrom() public {
        uint256 minted = 50 * ONE_USDC;
        uint256 allowanceAmount = 20 * ONE_USDC;
        uint256 transferAmount = 12 * ONE_USDC;

        usdc.mint(alice, minted);

        vm.expectEmit(true, true, false, true, address(usdc));
        emit Approval(alice, bob, allowanceAmount);
        vm.prank(alice);
        assertTrue(usdc.approve(bob, allowanceAmount));
        assertEq(usdc.allowance(alice, bob), allowanceAmount);

        vm.prank(bob);
        assertTrue(usdc.transferFrom(alice, bob, transferAmount));

        assertEq(usdc.balanceOf(alice), minted - transferAmount);
        assertEq(usdc.balanceOf(bob), transferAmount);
        assertEq(usdc.allowance(alice, bob), allowanceAmount - transferAmount);
        assertEq(usdc.totalSupply(), minted);
    }

    function test_RevertWhen_NonMinterMints() public {
        vm.expectRevert(abi.encodeWithSelector(MockUSDC.MockUSDC__UnauthorizedMinter.selector, alice));
        vm.prank(alice);
        usdc.mint(alice, ONE_USDC);

        assertEq(usdc.totalSupply(), 0);
    }

    function test_RevertWhen_MintToZeroAddress() public {
        vm.expectRevert(MockUSDC.MockUSDC__InvalidRecipient.selector);
        usdc.mint(address(0), ONE_USDC);

        assertEq(usdc.totalSupply(), 0);
    }

    function test_MultipleMintsKeepBalancesAndSupplyConsistent() public {
        usdc.mint(alice, 5 * ONE_USDC);
        usdc.mint(bob, 7 * ONE_USDC);
        usdc.mint(alice, 3 * ONE_USDC);
        usdc.mint(deployer, 10 * ONE_USDC);

        assertEq(usdc.balanceOf(alice), 8 * ONE_USDC);
        assertEq(usdc.balanceOf(bob), 7 * ONE_USDC);
        assertEq(usdc.balanceOf(deployer), 10 * ONE_USDC);
        assertEq(usdc.totalSupply(), 25 * ONE_USDC);
        assertEq(usdc.balanceOf(alice) + usdc.balanceOf(bob) + usdc.balanceOf(deployer), usdc.totalSupply());
    }

    function testFuzz_MintCreditsExactAmount(uint256 amount) public {
        amount = bound(amount, 0, 1e30);

        usdc.mint(alice, amount);

        assertEq(usdc.balanceOf(alice), amount);
        assertEq(usdc.totalSupply(), amount);
    }

    function testFuzz_RevertWhen_AnyNonMinterMints(address caller, address recipient, uint256 amount) public {
        vm.assume(caller != deployer);
        vm.assume(recipient != address(0));
        amount = bound(amount, 0, 1e30);

        vm.expectRevert(abi.encodeWithSelector(MockUSDC.MockUSDC__UnauthorizedMinter.selector, caller));
        vm.prank(caller);
        usdc.mint(recipient, amount);

        assertEq(usdc.totalSupply(), 0);
    }
}
