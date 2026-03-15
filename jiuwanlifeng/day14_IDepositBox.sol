// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDepositBox {
    function getOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function storeSecret(string calldata secret) external;
    function getSecret() external view returns (string memory);
    
    // 【修复点】：这里严格规定了 getBoxType 必须带 pure
    function getBoxType() external pure returns (string memory);
    
    function getDepositTime() external view returns (uint256);
}