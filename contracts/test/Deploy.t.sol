// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {StreakSavings} from "../src/StreakSavings.sol";
import {Deploy} from "../script/Deploy.s.sol";

contract DeployTest is Test {
    uint256 private constant TEST_PK = 0xA11CE;
    uint256 private constant INITIAL_MINT = 1_000 * 1e6;

    Deploy private deployScript;

    function setUp() public {
        deployScript = new Deploy();
    }

    function test_Deploy_RevertsWhenPrivateKeyMissing() public {
        vm.setEnv("DEPLOYER_PRIVATE_KEY", "");
        vm.expectRevert(Deploy.Deploy__MissingOrInvalidPrivateKey.selector);
        deployScript.run();

        vm.expectRevert(Deploy.Deploy__MissingOrInvalidPrivateKey.selector);
        deployScript.deployContracts(0, 60, address(0), 0, true);
    }

    function test_Deploy_RevertsOnUnsupportedChainId() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(Deploy.Deploy__UnsupportedChainId.selector, 1));
        deployScript.deployContracts(TEST_PK, 60, address(0), 0, false);

        vm.chainId(deployScript.ANVIL_CHAIN_ID());
        vm.expectRevert(
            abi.encodeWithSelector(Deploy.Deploy__UnsupportedChainId.selector, deployScript.ANVIL_CHAIN_ID())
        );
        deployScript.deployContracts(TEST_PK, 60, address(0), 0, false);
    }

    function test_Deploy_RevertsWhenEpochDurationIsZero() public {
        vm.chainId(deployScript.FUJI_CHAIN_ID());
        vm.expectRevert(abi.encodeWithSelector(Deploy.Deploy__InvalidEpochDuration.selector, 0));
        deployScript.deployContracts(TEST_PK, 0, address(0), 0, false);
    }

    function test_Deploy_SucceedsOnFujiChainIdAndVerifiesConfig() public {
        vm.chainId(deployScript.FUJI_CHAIN_ID());
        address expectedDeployer = vm.addr(TEST_PK);

        (MockUSDC usdc, StreakSavings savings) =
            deployScript.deployContracts(TEST_PK, 60, address(0), INITIAL_MINT, false);

        assertGt(address(usdc).code.length, 0);
        assertGt(address(savings).code.length, 0);
        assertEq(usdc.decimals(), 6);
        assertEq(usdc.minter(), expectedDeployer);
        assertEq(usdc.balanceOf(expectedDeployer), INITIAL_MINT);
        assertEq(usdc.totalSupply(), INITIAL_MINT);
        assertEq(address(savings.usdc()), address(usdc));
        assertEq(savings.epochDuration(), 60);
        assertEq(savings.totalPrincipal(), 0);
        assertEq(savings.totalWeight(), 0);
        assertEq(savings.totalRewardPool(), 0);
        assertEq(savings.yieldProvider(), expectedDeployer);
        assertEq(savings.currentEpoch(), 0);
    }

    function test_Deploy_CanUseExistingMockUSDCAndLocalAnvil() public {
        vm.chainId(deployScript.ANVIL_CHAIN_ID());
        address deployer = vm.addr(TEST_PK);

        vm.prank(deployer);
        MockUSDC existing = new MockUSDC();

        (MockUSDC usdc, StreakSavings savings) =
            deployScript.deployContracts(TEST_PK, 7 days, address(existing), INITIAL_MINT, true);

        assertEq(address(usdc), address(existing));
        assertEq(usdc.balanceOf(deployer), INITIAL_MINT);
        assertEq(address(savings.usdc()), address(existing));
        assertEq(savings.epochDuration(), 7 days);
    }
}
