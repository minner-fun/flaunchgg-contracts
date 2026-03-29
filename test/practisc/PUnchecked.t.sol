// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

contract PUncheckedTest is Test {
    function setUp() public {
        console.log('setUp');
    }

    // 测试1: 验证默认情况下溢出会 revert
    function test_OverflowWillRevert() public {
        console.log('test_OverflowWillRevert');
        uint a = type(uint).max;

        // 期望下一行会 revert（因为溢出）
        vm.expectRevert();
        a++; // ❌ 溢出会 revert

        console.log('This line will never execute');
    }

    // 测试2: 使用 unchecked 允许溢出发生
    function test_UncheckedOverflow() public {
        console.log('test_UncheckedOverflow');
        uint a = type(uint).max;
        console.log('Before overflow, a =', a);

        unchecked {
            a++; // ✅ 在 unchecked 中，溢出不会 revert
        }

        console.log('After overflow, a =', a);
        // 溢出后 a 会变成 0
        assertEq(a, 0, 'After overflow, value should wrap to 0');
    }

    // 测试3: 对比 checked vs unchecked
    function test_CheckedVsUnchecked() public {
        console.log('test_CheckedVsUnchecked');

        // Unchecked: 溢出会回绕到 0
        uint uncheckedValue = type(uint).max;
        unchecked {
            uncheckedValue++;
        }
        console.log('Unchecked overflow result:', uncheckedValue);
        assertEq(uncheckedValue, 0);

        // Checked: 溢出会 revert
        uint checkedValue = type(uint).max;
        vm.expectRevert();
        checkedValue++;

        console.log('Test passed!');
    }

    // 测试4: 下溢测试（underflow）
    function test_Underflow() public {
        console.log('test_Underflow');

        // 默认情况：下溢会 revert
        uint a = 0;
        vm.expectRevert();
        a--; // ❌ 下溢会 revert

        // unchecked 情况：下溢会回绕到最大值
        uint b = 0;
        unchecked {
            b--; // ✅ 回绕到 type(uint256).max
        }
        console.log('After underflow, b =', b);
        assertEq(b, type(uint).max);
    }
}
