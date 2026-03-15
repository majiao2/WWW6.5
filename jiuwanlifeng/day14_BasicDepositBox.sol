// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./day14_BaseDepositBox.sol"; // 导入地基

contract BasicDepositBox is BaseDepositBox {
    function getBoxType() external pure override returns (string memory) {
        return "Basic";
    }
}