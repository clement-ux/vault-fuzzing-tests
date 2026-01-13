// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.31;

import {Vm} from "@forge-std/Vm.sol";

library Logger {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function decimals(uint256 amount, uint256 decimal, bool withSeparator, bool trimZeros)
        public
        view
        returns (string memory)
    {
        uint256 integerPart = amount / (10 ** decimal);
        uint256 fractionalPart = amount % (10 ** decimal);

        string memory intStr = withSeparator ? addCommas(vm.toString(integerPart)) : vm.toString(integerPart);
        string memory fracStr =
            trimZeros ? removeTrailingZeros(vm.toString(fractionalPart)) : vm.toString(fractionalPart);

        return bytes(fracStr).length > 0 ? string(abi.encodePacked(intStr, ".", fracStr)) : intStr;
    }

    function addCommas(string memory str) internal pure returns (string memory) {
        bytes memory b = bytes(str);
        uint256 len = b.length;

        if (len <= 3) return str;

        uint256 newLen = len + (len - 1) / 3;
        bytes memory result = new bytes(newLen);
        uint256 j = 0;

        for (uint256 i = 0; i < len; i++) {
            if (i > 0 && (len - i) % 3 == 0) {
                result[j++] = "_";
            }
            result[j++] = b[i];
        }

        return string(result);
    }

    function removeTrailingZeros(string memory str) internal pure returns (string memory) {
        bytes memory b = bytes(str);
        uint256 len = b.length;

        while (len > 0 && b[len - 1] == "0") {
            len--;
        }

        if (len > 0 && b[len - 1] == ".") {
            len--;
        }

        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = b[i];
        }

        return string(result);
    }

    function formatTime(uint256 _seconds) public pure returns (string memory) {
        uint256 _years = _seconds / 365 days;
        uint256 _days = (_seconds % 365 days) / 1 days;
        uint256 _hours = (_seconds % 1 days) / 1 hours;
        uint256 _minutes = (_seconds % 1 hours) / 1 minutes;
        uint256 _secs = _seconds % 1 minutes;

        return string(
            abi.encodePacked(
                vm.toString(_years),
                "y ",
                vm.toString(_days),
                "d ",
                vm.toString(_hours),
                "h ",
                vm.toString(_minutes),
                "m ",
                vm.toString(_secs),
                "s (",
                vm.toString(_seconds),
                " seconds)"
            )
        );
    }
}
